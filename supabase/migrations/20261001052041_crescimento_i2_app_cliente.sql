-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I2 · Servidor da app do cliente
--
--   1. Registo do cliente: registar_cliente() cria (ou liga, pelo telefone
--      confirmado por SMS) a linha em clientes do utilizador autenticado;
--      meu_perfil() devolve os dados que a app precisa.
--   2. Cardápio por cozinha (preço, disponível, prato do dia). O servidor
--      calcula o preço dos pedidos da app: orcamento_pedido() devolve o
--      orçamento ao checkout e o trigger trg_pedidos_00_cardapio reescreve os
--      itens, o subtotal, a zona e a taxa de entrega de qualquer pedido criado
--      por uma sessão da app. Os preços enviados pela app são ignorados.
--   3. meus_amigos(): amigos convidados (primeiro nome e dias restantes) para C1.
--   4. Push (Expo): dispositivos_push, registar_token_push(), remover_token_push().
--   5. Textos das notificações N2, N3, N4 e N8 (texto_notificacao) e funções do
--      serviço de envio (Edge Function enviar-notificacoes), só para service_role.
--
-- Não liga nenhum interruptor.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Registo do cliente
-- -----------------------------------------------------------------------------
-- Telefone confirmado pelo Supabase Auth (SMS). Se já existir um cliente com o
-- mesmo telefone sem utilizador associado (registado pelo operador), é ligado a
-- este utilizador em vez de se criar um duplicado: o histórico conta para
-- "cliente não novo" no programa de indicação.
create or replace function registar_cliente(p_nome text, p_tipo text default 'Particular', p_nif text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_telefone text;
  v_cliente  uuid;
  v_nome     text := nullif(trim(p_nome), '');
begin
  if v_uid is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  select id into v_cliente from clientes where auth_user_id = v_uid and deletado_em is null;
  if found then
    return v_cliente;
  end if;
  if v_nome is null or length(v_nome) > 80 then
    raise exception 'nome_invalido' using errcode = 'P0001';
  end if;
  if p_tipo not in ('Particular', 'Empresa') then
    raise exception 'tipo_invalido' using errcode = 'P0001';
  end if;
  if p_tipo = 'Empresa' and nullif(trim(p_nif), '') is null then
    raise exception 'nif_obrigatorio' using errcode = 'P0001';
  end if;

  select normalizar_telefone(phone) into v_telefone from auth.users where id = v_uid;
  if v_telefone is null then
    raise exception 'telefone_nao_confirmado' using errcode = 'P0001';
  end if;

  select id into v_cliente from clientes
   where normalizar_telefone(telefone) = v_telefone and deletado_em is null
   order by criado_em limit 1
   for update;
  if found then
    if exists (select 1 from clientes where id = v_cliente and auth_user_id is not null) then
      raise exception 'telefone_ja_associado' using errcode = 'P0001';
    end if;
    update clientes set auth_user_id = v_uid, atualizado_em = now() where id = v_cliente;
    perform preparar_cliente_programa(v_cliente);
    perform registar_auditoria('cliente_ligado_app', 'clientes', v_cliente, '{}'::jsonb);
  else
    insert into clientes (nome, tipo, telefone, nif, auth_user_id, dispositivo_id)
    values (v_nome, p_tipo, v_telefone, nullif(trim(p_nif), ''), v_uid, 'servidor')
    returning id into v_cliente;
    perform registar_auditoria('cliente_registado_app', 'clientes', v_cliente, '{}'::jsonb);
  end if;
  return v_cliente;
end $$;

-- Dados do próprio cliente para a app (a tabela clientes não é legível pelas apps)
create or replace function meu_perfil() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'cliente_id', c.id,
           'nome', c.nome,
           'primeiro_nome', split_part(trim(c.nome), ' ', 1),
           'tipo', c.tipo,
           'telefone', c.telefone,
           'codigo', ci.codigo,
           'pseudonimo', pd.pseudonimo,
           'tem_ligacao', exists (select 1 from ligacoes_indicacao l
                                   where l.indicado_id = c.id and l.deletado_em is null),
           'cliente_novo', not cliente_ja_comprou(c.id))
    from clientes c
    left join codigos_indicacao ci on ci.cliente_id = c.id
    left join perfil_destaques pd on pd.cliente_id = c.id
   where c.auth_user_id = auth.uid() and auth.uid() is not null and c.deletado_em is null;
$$;

-- -----------------------------------------------------------------------------
-- 2. Cardápio e preço dos pedidos
-- -----------------------------------------------------------------------------
create table cardapio (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cozinha_id       uuid not null default cozinha_padrao() references cozinhas(id),
  prato_base_id    uuid references pratos_base(id),
  nome             text not null,
  descricao        text,
  categoria        text,
  preco            integer not null check (preco > 0),
  foto_url         text,
  disponivel       boolean not null default true,
  do_dia           boolean not null default false,
  ordem            integer not null default 0
);
create index cardapio_cozinha_idx on cardapio (cozinha_id, disponivel, ordem);
create index cardapio_prato_base_idx on cardapio (prato_base_id);
comment on table cardapio is
  'Sincronização: Last-write-wins com atualizado_em; escrita só com cozinhas.gerir. O preço do pedido vem sempre daqui (servidor).';

alter table cardapio enable row level security;
create policy ler on cardapio for select to authenticated using (deletado_em is null);
create policy criar on cardapio for insert to authenticated with check (tem_permissao('cozinhas.gerir'));
create policy editar on cardapio for update to authenticated
  using (tem_permissao('cozinhas.gerir')) with check (tem_permissao('cozinhas.gerir'));
grant select, insert, update on cardapio to authenticated;

-- Orçamento calculado no servidor. Itens: [{cardapio_id, qtd, componentes_excluidos?, componentes_ajustados?}].
-- Devolve os itens com nome, prato_base_id e preço do cardápio, o subtotal, a
-- zona e a taxa de entrega do ponto, e o desconto de indicação (com o motivo).
create or replace function orcamento_pedido(p_itens jsonb, p_ponto_entrega uuid,
                                            p_cozinha uuid default null, p_grupo uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_cliente  uuid := cliente_actual();
  v_cozinha  uuid := case when funcionalidade_activa('multi_cozinha')
                          then coalesce(p_cozinha, cozinha_padrao()) else cozinha_padrao() end;
  v_item     jsonb;
  v_qtd      numeric;
  v_card     cardapio;
  v_itens    jsonb := '[]';
  v_subtotal integer := 0;
  v_ponto    pontos_entrega;
  v_zona     zonas;
  v_taxa     integer := 0;
  v_desc     record;
begin
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'pedido_vazio' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_itens) > 30 then
    raise exception 'itens_a_mais' using errcode = 'P0001';
  end if;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    begin
      v_qtd := (v_item ->> 'qtd')::numeric;
      select * into v_card from cardapio
       where id = (v_item ->> 'cardapio_id')::uuid and deletado_em is null;
    exception when invalid_text_representation then
      raise exception 'item_indisponivel' using errcode = 'P0001';
    end;
    if v_qtd is null or v_qtd <> trunc(v_qtd) or v_qtd < 1 or v_qtd > 50 then
      raise exception 'quantidade_invalida' using errcode = 'P0001';
    end if;
    if v_card.id is null or not v_card.disponivel or v_card.cozinha_id <> v_cozinha then
      raise exception 'item_indisponivel' using errcode = 'P0001', detail = v_item ->> 'cardapio_id';
    end if;
    v_itens := v_itens || jsonb_strip_nulls(jsonb_build_object(
      'cardapio_id', v_card.id,
      'prato_base_id', v_card.prato_base_id,
      'nome', v_card.nome,
      'qtd', v_qtd::int,
      'preco_unitario', v_card.preco,
      'componentes_excluidos', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_excluidos', 'null') end,
      'componentes_ajustados', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_ajustados', 'null') end));
    v_subtotal := v_subtotal + v_qtd::int * v_card.preco;
    v_card := null;
  end loop;

  -- Pedido de grupo: o ponto e a taxa são os do grupo (fase I6)
  if p_grupo is null then
    if p_ponto_entrega is null then
      raise exception 'ponto_obrigatorio' using errcode = 'P0001';
    end if;
    select * into v_ponto from pontos_entrega where id = p_ponto_entrega and deletado_em is null;
    if not found
       or (v_cliente is not null
           and v_ponto.criado_por_cliente is distinct from v_cliente
           and not exists (select 1 from enderecos_cliente e
                            where e.ponto_entrega_id = v_ponto.id and e.cliente_id = v_cliente
                              and e.deletado_em is null)) then
      raise exception 'ponto_invalido' using errcode = 'P0001';
    end if;
    select * into v_zona from zonas where id = v_ponto.zona_id and deletado_em is null;
    if not found then
      raise exception 'ponto_sem_zona' using errcode = 'P0001';
    end if;
    v_taxa := round(coalesce(v_zona.taxa, 0))::int;
  end if;

  select * into v_desc from avaliar_desconto_indicacao(v_cliente, p_ponto_entrega);

  return jsonb_build_object(
    'itens', v_itens,
    'subtotal', v_subtotal,
    'zona_id', v_zona.id,
    'zona_nome', v_zona.nome,
    'taxa_entrega', v_taxa,
    'desconto', coalesce(v_desc.valor, 0),
    'motivo_desconto', v_desc.motivo,
    'total', greatest(v_subtotal + v_taxa - coalesce(v_desc.valor, 0), 0));
end $$;

-- Pedidos criados por uma sessão da app: itens, subtotal, zona e taxa vêm do
-- servidor. SECURITY INVOKER: só aqui se sabe quem escreve. Corre antes de
-- trg_pedidos_0_validar_itens (ordem por nome), que valida os itens já normalizados.
create or replace function pedidos_precos_cardapio() returns trigger
language plpgsql set search_path = public as $$
declare
  o jsonb;
begin
  if e_escrita_cliente() then
    o := orcamento_pedido(new.itens, new.ponto_entrega_id, new.cozinha_id, new.grupo_id);
    new.itens := o -> 'itens';
    new.subtotal := (o ->> 'subtotal')::int;
    new.taxa_entrega := (o ->> 'taxa_entrega')::int;
    if new.grupo_id is null then
      new.zona_id := (o ->> 'zona_id')::uuid;
    end if;
  end if;
  return new;
end $$;

create trigger trg_pedidos_00_cardapio
before insert on pedidos
for each row execute function pedidos_precos_cardapio();

-- Itens e valores de um pedido não mudam depois de criado: as apps só têm UPDATE
-- em hora_prometida, observacoes, atualizado_em e deletado_em (privilégios de coluna de I1).

-- -----------------------------------------------------------------------------
-- 3. Amigos convidados (C1)
-- -----------------------------------------------------------------------------
create or replace function meus_amigos()
returns table (primeiro_nome text, ligado_em timestamptz, expira_em timestamptz, dias_restantes integer,
               estado text, pedidos_com_ganho integer, ganho_total integer)
language sql stable security definer set search_path = public as $$
  select split_part(trim(c.nome), ' ', 1),
         l.ligado_em,
         l.expira_em,
         case when l.expira_em is not null and l.expira_em > now()
              then ceil(extract(epoch from l.expira_em - now()) / 86400)::int end,
         case when l.expira_em is null then 'aguarda_primeiro_pedido'
              when l.expira_em > now() then 'activo'
              else 'expirado' end,
         (select count(*)::int from ganhos_indicacao g
           where g.indicado_id = l.indicado_id and g.indicador_id = l.indicador_id
             and g.estado in ('confirmado', 'pago') and g.deletado_em is null),
         (select coalesce(sum(g.valor), 0)::int from ganhos_indicacao g
           where g.indicado_id = l.indicado_id and g.indicador_id = l.indicador_id
             and g.estado in ('confirmado', 'pago') and g.deletado_em is null)
    from ligacoes_indicacao l
    join clientes c on c.id = l.indicado_id
   where l.indicador_id = cliente_actual() and l.deletado_em is null
   order by (l.expira_em is not null and l.expira_em <= now()), l.expira_em nulls first, l.ligado_em desc;
$$;

-- -----------------------------------------------------------------------------
-- 4. Push (Expo)
-- -----------------------------------------------------------------------------
create table dispositivos_push (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid not null references clientes(id),
  token            text not null unique,
  plataforma       text check (plataforma in ('ios', 'android', 'web')),
  activo           boolean not null default true
);
create index dispositivos_push_cliente_idx on dispositivos_push (cliente_id) where activo;
comment on table dispositivos_push is
  'Sincronização: Só servidor (registar_token_push / remover_token_push); não sincroniza para o telemóvel.';
alter table dispositivos_push enable row level security;
revoke all on dispositivos_push from anon, authenticated;

create or replace function registar_token_push(p_token text, p_plataforma text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
begin
  if v_cliente is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  if p_token is null or p_token !~ '^(ExponentPushToken|ExpoPushToken)\[[^\]]+\]$' then
    raise exception 'token_invalido' using errcode = 'P0001';
  end if;
  insert into dispositivos_push (cliente_id, token, plataforma, activo, dispositivo_id)
  values (v_cliente, p_token, p_plataforma, true, 'servidor')
  on conflict (token) do update
    set cliente_id = excluded.cliente_id, plataforma = excluded.plataforma,
        activo = true, atualizado_em = now(), deletado_em = null;
end $$;

create or replace function remover_token_push(p_token text) returns void
language sql security definer set search_path = public as $$
  update dispositivos_push set activo = false, atualizado_em = now()
   where token = p_token and cliente_id = cliente_actual();
$$;

-- -----------------------------------------------------------------------------
-- 5. Notificações: textos e serviço de envio
-- -----------------------------------------------------------------------------
create or replace function formatar_kz(p_valor numeric) returns text
language sql immutable set search_path = public as $$
  select regexp_replace(round(coalesce(p_valor, 0))::bigint::text, '(\d)(?=(\d{3})+$)', '\1.', 'g') || ' Kz';
$$;

-- N2 é enfileirada por ligar_indicacao só com o nome do indicado: acrescenta os
-- valores garantidos da ligação acabada de criar (mesma transacção).
create or replace function notificacoes_completar_dados() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  lig ligacoes_indicacao;
begin
  if new.codigo = 'N2' and not (new.dados ? 'ganho_por_pedido') then
    select * into lig from ligacoes_indicacao
     where indicador_id = new.cliente_id and deletado_em is null
     order by ligado_em desc limit 1;
    if found then
      new.dados := new.dados || jsonb_build_object('ganho_por_pedido', lig.ganho_por_pedido_garantido,
                                                   'duracao_dias', lig.duracao_dias_garantida);
    end if;
  end if;
  return new;
end $$;

create trigger trg_1_completar_dados
before insert on notificacoes_fila
for each row execute function notificacoes_completar_dados();

-- Textos da secção 11 (marca, valores e nomes a partir dos dados da fila)
create or replace function texto_notificacao(p_codigo text, p_dados jsonb, out titulo text, out corpo text)
language sql stable set search_path = public as $$
  select 'Manda Bué',
         case p_codigo
           when 'N2' then format('%s entrou com o teu código! Ganhas %s em cada pedido durante %s dias.',
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'Um amigo'),
                                 formatar_kz((p_dados ->> 'ganho_por_pedido')::numeric),
                                 p_dados ->> 'duracao_dias')
           when 'N3' then format('+%s: o pedido de %s foi entregue. Saldo desta semana: %s.',
                                 formatar_kz((p_dados ->> 'valor')::numeric),
                                 coalesce(nullif(p_dados ->> 'indicado_nome', ''), 'um amigo'),
                                 formatar_kz((p_dados ->> 'saldo_semana')::numeric))
           when 'N4' then format('Passaste os %s esta semana. Os próximos ganhos ficam em verificação e são pagos assim que confirmarmos os pedidos.',
                                 formatar_kz((p_dados ->> 'limite')::numeric))
           when 'N8' then format('Pagámos %s por %s. Referência: %s.',
                                 formatar_kz((p_dados ->> 'valor')::numeric),
                                 case p_dados ->> 'metodo'
                                   when 'multicaixa_express' then 'Multicaixa Express'
                                   when 'unitel_money' then 'Unitel Money'
                                   else coalesce(p_dados ->> 'metodo', '') end,
                                 p_dados ->> 'referencia')
         end;
$$;

-- Notificações por enviar (I2: N2, N3, N4, N8), com o interruptor da funcionalidade
-- ligado, e os tokens activos de cada cliente.
create or replace function notificacoes_pendentes(p_limite integer default 100)
returns table (id uuid, cliente_id uuid, codigo text, titulo text, corpo text, dados jsonb, tokens text[])
language sql stable security definer set search_path = public as $$
  select n.id, n.cliente_id, n.codigo, t.titulo, t.corpo, n.dados,
         coalesce((select array_agg(d.token order by d.atualizado_em desc) from dispositivos_push d
                    where d.cliente_id = n.cliente_id and d.activo and d.deletado_em is null), '{}')
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
   where n.enviada_em is null and n.deletado_em is null
     and n.codigo in ('N2', 'N3', 'N4', 'N8')
     and funcionalidade_activa(funcionalidade_da_notificacao(n.codigo))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$$;

create or replace function marcar_notificacoes_enviadas(p_ids uuid[]) returns integer
language sql security definer set search_path = public as $$
  with u as (update notificacoes_fila set enviada_em = now(), atualizado_em = now()
              where id = any(p_ids) and enviada_em is null returning 1)
  select count(*)::int from u;
$$;

create or replace function desactivar_tokens_push(p_tokens text[]) returns integer
language sql security definer set search_path = public as $$
  with u as (update dispositivos_push set activo = false, atualizado_em = now()
              where token = any(p_tokens) and activo returning 1)
  select count(*)::int from u;
$$;

-- Agenda o envio de minuto a minuto (pg_cron + pg_net), como agendar_jobs().
-- As migrações não activam extensões: correr depois de activar pg_cron e pg_net,
-- com o URL da Edge Function (e o segredo, se ENVIO_SEGREDO estiver definido).
create or replace function agendar_envio_notificacoes(p_url text, p_segredo text default null) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format(
    $f$select cron.schedule('enviar-notificacoes', '* * * * *',
         %L)$f$,
    format('select net.http_post(url := %L, headers := %L::jsonb, body := ''{}''::jsonb)',
           p_url, jsonb_build_object('Content-Type', 'application/json', 'x-envio-segredo', coalesce(p_segredo, ''))));
  return 'agendado';
end $$;

-- -----------------------------------------------------------------------------
-- 6. Privilégios
-- -----------------------------------------------------------------------------
-- API da app do cliente
revoke execute on function registar_cliente(text, text, text)          from public, anon;
revoke execute on function meu_perfil()                                from public, anon;
revoke execute on function orcamento_pedido(jsonb, uuid, uuid, uuid)   from public, anon;
revoke execute on function meus_amigos()                               from public, anon;
revoke execute on function registar_token_push(text, text)             from public, anon;
revoke execute on function remover_token_push(text)                    from public, anon;
grant execute on function registar_cliente(text, text, text), meu_perfil(), orcamento_pedido(jsonb, uuid, uuid, uuid),
                          meus_amigos(), registar_token_push(text, text), remover_token_push(text)
  to authenticated;

-- Funções de trigger e do serviço de envio: nunca chamáveis pelas apps
revoke execute on function pedidos_precos_cardapio()                   from public, anon, authenticated;
revoke execute on function notificacoes_completar_dados()              from public, anon, authenticated;
revoke execute on function texto_notificacao(text, jsonb)              from public, anon, authenticated;
revoke execute on function notificacoes_pendentes(integer)             from public, anon, authenticated;
revoke execute on function marcar_notificacoes_enviadas(uuid[])        from public, anon, authenticated;
revoke execute on function desactivar_tokens_push(text[])              from public, anon, authenticated;
revoke execute on function agendar_envio_notificacoes(text, text)      from public, anon, authenticated;
revoke execute on function formatar_kz(numeric)                        from public, anon, authenticated;
grant execute on function notificacoes_pendentes(integer), marcar_notificacoes_enviadas(uuid[]),
                          desactivar_tokens_push(text[]), texto_notificacao(text, jsonb), formatar_kz(numeric)
  to service_role;
