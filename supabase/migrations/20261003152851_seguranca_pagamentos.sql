-- Segurança do Convida e Ganha e dos pagamentos na entrega (análise de fraude de 3/10/2026).
--  1. Limite "mesmo local": conta só os amigos DA MESMA PESSOA na mesma morada. Num prédio, os
--     vizinhos convidados por pessoas diferentes deixam de se bloquear (o caso que se quer travar é
--     uma pessoa com várias contas falsas em casa, todas indicadas por ela).
--  2. Levantamento só para quem já tem pelo menos um pedido seu entregue e pago.
--  3. Desconto de boas-vindas só a partir de parametros.desconto_subtotal_minimo (2 000 Kz por
--     defeito; 0 desliga): o desconto sai da margem do prato e não pode ser maior do que ela.
--  4. Pagamentos electrónicos na entrega (Multicaixa Express, TPA, Unitel Money, Transferência):
--     o estafeta tem de escrever a referência da transacção e fotografar o comprovativo; a mesma
--     referência não serve para dois pedidos; o gerente confere (ou rejeita) cada um antes de
--     fechar a caixa. Métodos fora da lista são recusados (um nome inventado escapava à caixa).

-- ---------------------------------------------------------------- 3. desconto mínimo
alter table parametros add column desconto_subtotal_minimo integer not null default 2000
  check (desconto_subtotal_minimo between 0 and 1000000);
comment on column parametros.desconto_subtotal_minimo is
  'Subtotal mínimo (sem a taxa de entrega) para o desconto de boas-vindas do Convida e Ganha; 0 = sem mínimo';

-- ---------------------------------------------------------------- 4. comprovativos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprovativos', 'comprovativos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

create table comprovativos_pagamento (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  pedido_id        uuid not null references pedidos(id),
  caixa_id         uuid not null references caixa(id),
  cozinha_id       uuid not null references cozinhas(id),
  metodo           text not null,
  valor            numeric not null,
  referencia       text not null,
  referencia_chave text not null,             -- referência sem espaços e em maiúsculas
  caminho          text not null,             -- ficheiro no bucket comprovativos
  registado_por    uuid references funcionarios(id),
  estado           text not null default 'por_conferir' check (estado in ('por_conferir', 'conferido', 'rejeitado')),
  conferido_por    uuid references funcionarios(id),
  conferido_em     timestamptz,
  nota             text
);
create unique index comprovativos_referencia_key on comprovativos_pagamento (metodo, referencia_chave)
  where deletado_em is null;
create index comprovativos_caixa_idx on comprovativos_pagamento (caixa_id);
create index comprovativos_pedido_idx on comprovativos_pagamento (pedido_id);
create index comprovativos_cozinha_idx on comprovativos_pagamento (cozinha_id);
create index comprovativos_registado_idx on comprovativos_pagamento (registado_por);
create index comprovativos_conferido_idx on comprovativos_pagamento (conferido_por);

create trigger trg_0_so_servidor before insert or update or delete on comprovativos_pagamento
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on comprovativos_pagamento
for each row execute function sync_receber();
alter table comprovativos_pagamento enable row level security;
revoke all on comprovativos_pagamento from anon;
revoke insert, update, delete, truncate on comprovativos_pagamento from authenticated;
grant select on comprovativos_pagamento to authenticated;
create policy ler on comprovativos_pagamento for select to authenticated
  using (deletado_em is null and (pode_na_cozinha('vendas.registar', cozinha_id) or tem_permissao('pedidos.gerir')));
comment on table comprovativos_pagamento is 'Sincronização: só servidor (registado na entrega, conferido no fecho da caixa). Telemóvel só lê.';

-- Caminho: <pedido_id>/<ficheiro>.jpg, de um pedido ainda por entregar
create or replace function comprovativo_caminho_valido(p_nome text) returns boolean
language sql stable security definer set search_path = public as $$
  select split_part(p_nome, '/', 3) = ''
     and split_part(p_nome, '/', 2) ~ '^[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$'
     and exists (select 1 from pedidos x where x.id::text = split_part(p_nome, '/', 1)
                    and x.deletado_em is null and x.estado in ('em_preparacao', 'em_entrega'));
$$;
-- Quem vê a foto: quem confere a caixa da cozinha do pedido, ou quem gere pedidos
create or replace function comprovativo_visivel(p_nome text) returns boolean
language sql stable security definer set search_path = public as $$
  select tem_permissao('pedidos.gerir')
      or exists (select 1 from pedidos x where x.id::text = split_part(p_nome, '/', 1)
                    and pode_na_cozinha('vendas.registar', x.cozinha_id));
$$;
revoke execute on function comprovativo_caminho_valido(text) from public, anon;
revoke execute on function comprovativo_visivel(text) from public, anon;
grant execute on function comprovativo_caminho_valido(text) to authenticated;
grant execute on function comprovativo_visivel(text) to authenticated;

create policy comprovativos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'comprovativos'
              and (tem_permissao('entregas.registar') or tem_permissao('pedidos.gerir'))
              and comprovativo_caminho_valido(name));
create policy comprovativos_ler on storage.objects for select to authenticated
  using (bucket_id = 'comprovativos' and (owner = auth.uid() or comprovativo_visivel(name)));
-- Sem políticas de troca nem de apagar: o comprovativo fica como foi enviado

-- Na entrega: valida cada pagamento e regista os electrónicos para conferir
create or replace function pedidos_registar_comprovativos() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  x        jsonb;
  v_metodo text;
  v_ref    text;
  v_cam    text;
begin
  if not (new.estado = 'entregue_pago' and old.estado is distinct from 'entregue_pago') then
    return new;
  end if;
  for x in select * from jsonb_array_elements(coalesce(new.parcelas, '[]')) loop
    v_metodo := x ->> 'metodo';
    if v_metodo is null or v_metodo not in ('Dinheiro', 'Multicaixa Express', 'TPA', 'Unitel Money', 'Transferência') then
      raise exception 'metodo_invalido' using errcode = 'P0001', detail = coalesce(v_metodo, '');
    end if;
    continue when v_metodo = 'Dinheiro';
    v_ref := nullif(trim(x ->> 'referencia'), '');
    if v_ref is null or length(v_ref) < 4 or length(v_ref) > 60 then
      raise exception 'referencia_obrigatoria' using errcode = 'P0001', detail = v_metodo;
    end if;
    v_cam := x ->> 'comprovativo';
    if v_cam is null or split_part(v_cam, '/', 1) <> new.id::text
       or not exists (select 1 from storage.objects o where o.bucket_id = 'comprovativos' and o.name = v_cam) then
      raise exception 'comprovativo_obrigatorio' using errcode = 'P0001', detail = v_metodo;
    end if;
    begin
      insert into comprovativos_pagamento (dispositivo_id, sincronizado_em, pedido_id, caixa_id, cozinha_id, metodo, valor,
                                           referencia, referencia_chave, caminho, registado_por)
      values ('servidor', now(), new.id, new.caixa_id, new.cozinha_id, v_metodo, (x ->> 'valor')::numeric,
              v_ref, upper(regexp_replace(v_ref, '\s', '', 'g')), v_cam, funcionario_actual());
    exception when unique_violation then
      raise exception 'referencia_repetida' using errcode = 'P0001', detail = v_ref;
    end;
  end loop;
  return new;
end $$;
revoke execute on function pedidos_registar_comprovativos() from public, anon, authenticated;
create trigger trg_comprovativos after update of estado on pedidos
for each row execute function pedidos_registar_comprovativos();

-- O gerente confere (ou rejeita, com nota) cada pagamento electrónico com a caixa ainda aberta
create or replace function conferir_comprovativo(p_comprovativo uuid, p_conferido boolean, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  k      comprovativos_pagamento;
  v_func uuid;
begin
  select * into k from comprovativos_pagamento where id = p_comprovativo and deletado_em is null for update;
  if not found then raise exception 'comprovativo_inexistente' using errcode = 'P0001'; end if;
  perform caixa_para_gerir(k.caixa_id, true);
  v_func := funcionario_actual();
  if p_conferido is null then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if not p_conferido and nullif(trim(p_nota), '') is null then
    raise exception 'nota_obrigatoria' using errcode = 'P0001';
  end if;
  if p_nota is not null and length(p_nota) > 300 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  update comprovativos_pagamento
     set estado = case when p_conferido then 'conferido' else 'rejeitado' end,
         conferido_por = v_func, conferido_em = now(), nota = nullif(trim(p_nota), ''), atualizado_em = now()
   where id = k.id;
  perform registar_auditoria(case when p_conferido then 'comprovativo_conferido' else 'comprovativo_rejeitado' end,
                             'comprovativos_pagamento', k.id,
                             jsonb_build_object('pedido_id', k.pedido_id, 'metodo', k.metodo, 'valor', k.valor,
                                                'referencia', k.referencia, 'nota', nullif(trim(p_nota), '')));
end $$;
revoke execute on function conferir_comprovativo(uuid, boolean, text) from public, anon;
grant execute on function conferir_comprovativo(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------- 1, 2, 3 e 4: funções actualizadas
create or replace function processar_ganho_indicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p               parametros;
  lig             ligacoes_indicacao;
  v_tipo_local    text;
  nivel_ind       text;
  total_sem       int;
  indicados_local int;
  v_estado        text := 'confirmado';
  v_motivo        text := null;
  v_ganho         uuid;
  g               record;
begin
  -- Estorno de um pedido já pago: ganhos ainda não pagos são anulados
  if old.estado = 'entregue_pago' and new.estado <> 'entregue_pago' then
    for g in update ganhos_indicacao
                set estado = 'anulado', motivo = 'pedido_estornado'
              where pedido_id = new.id and estado in ('em_verificacao','confirmado')
             returning id loop
      perform registar_auditoria('ganho_indicacao_anulado', 'ganhos_indicacao', g.id,
                                 jsonb_build_object('motivo', 'pedido_estornado', 'pedido_id', new.id));
    end loop;
    return new;
  end if;

  if new.estado <> 'entregue_pago' or old.estado = 'entregue_pago' then
    return new;
  end if;
  if not funcionalidade_activa('indicacao') then return new; end if;

  select * into p from parametros where unico;
  select * into lig from ligacoes_indicacao
   where indicado_id = new.cliente_id and deletado_em is null
   for update;
  if not found then return new; end if;

  -- 1.º pedido pago: arranca o período (duração garantida na ligação)
  if lig.expira_em is null then
    update ligacoes_indicacao
       set primeiro_pedido_id = new.id,
           expira_em = coalesce(new.entregue_em, now()) + make_interval(days => lig.duracao_dias_garantida),
           desconto_usado = (new.desconto_indicacao > 0)
     where id = lig.id
    returning * into lig;
  end if;

  if now() > lig.expira_em then return new; end if;
  if exists (select 1 from ganhos_indicacao where pedido_id = new.id) then
    return new;
  end if;

  -- Sinal forte: mesmo dispositivo (campo comum dispositivo_id; linhas criadas
  -- pelo servidor têm dispositivo_id = 'servidor' e não contam)
  if exists (
    select 1 from pedidos a
     where a.cliente_id = lig.indicador_id
       and a.dispositivo_id is not null and a.dispositivo_id <> 'servidor'
       and a.dispositivo_id in (select b.dispositivo_id from pedidos b
                                 where b.cliente_id = new.cliente_id
                                   and b.dispositivo_id is not null
                                   and b.dispositivo_id <> 'servidor')) then
    v_estado := 'anulado'; v_motivo := 'mesmo_dispositivo';
  end if;

  -- Sinal médio: mesmo número de levantamento
  if v_estado = 'confirmado' and exists (
    select 1 from pagamentos_indicacao a
     where a.indicador_id = lig.indicador_id and a.numero_destino is not null
       and a.numero_destino in (select b.numero_destino from pagamentos_indicacao b
                                 where b.indicador_id = new.cliente_id
                                   and b.numero_destino is not null)) then
    v_estado := 'em_verificacao'; v_motivo := 'numero_pagamento_partilhado';
  end if;

  -- Limite por local residencial: amigos DA MESMA PESSOA na mesma morada (vizinhos de prédio
  -- convidados por pessoas diferentes não se bloqueiam uns aos outros)
  select tipo into v_tipo_local from pontos_entrega where id = new.ponto_entrega_id;
  if v_estado = 'confirmado' and v_tipo_local = 'residencial' then
    select count(distinct g2.indicado_id) into indicados_local
      from pontos_entrega_proximos(new.ponto_entrega_id) pp(id)
      join pedidos x on x.ponto_entrega_id = pp.id
      join ganhos_indicacao g2 on g2.pedido_id = x.id
     where g2.estado <> 'anulado'
       and g2.indicador_id = lig.indicador_id
       and g2.indicado_id <> new.cliente_id;
    if indicados_local >= p.max_indicados_por_local then
      v_estado := 'em_verificacao'; v_motivo := 'limite_local';
    end if;
  end if;

  -- Limite semanal (não se aplica a Embaixadores)
  if v_estado = 'confirmado' then
    select nivel into nivel_ind from codigos_indicacao where cliente_id = lig.indicador_id;
    if nivel_ind is distinct from 'embaixador' then
      select coalesce(sum(valor), 0) into total_sem
        from ganhos_indicacao
       where indicador_id = lig.indicador_id
         and estado in ('confirmado','pago')
         and confirmado_em >= inicio_semana_luanda();
      if total_sem >= p.limite_verificacao_semanal then
        v_estado := 'em_verificacao'; v_motivo := 'limite_semanal';
      end if;
    end if;
  end if;

  insert into ganhos_indicacao
    (pedido_id, indicador_id, indicado_id, valor, estado, motivo, confirmado_em, dispositivo_id)
  values
    (new.id, lig.indicador_id, new.cliente_id, lig.ganho_por_pedido_garantido, v_estado, v_motivo,
     case when v_estado = 'confirmado' then now() end, 'servidor')
  returning id into v_ganho;

  perform registar_auditoria('ganho_indicacao_criado', 'ganhos_indicacao', v_ganho,
    jsonb_build_object('estado', v_estado, 'motivo', v_motivo, 'pedido_id', new.id));

  if v_estado = 'confirmado' then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N3', jsonb_build_object(
      'pedido_id', new.id,
      'valor', lig.ganho_por_pedido_garantido,
      'indicado_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = new.cliente_id),
      'saldo_semana', (select coalesce(sum(valor), 0) from ganhos_indicacao
                        where indicador_id = lig.indicador_id and estado in ('confirmado','pago')
                          and confirmado_em >= inicio_semana_luanda())));
  elsif v_estado = 'em_verificacao' and v_motivo = 'limite_semanal'
        and not exists (select 1 from ganhos_indicacao
                         where indicador_id = lig.indicador_id
                           and motivo = 'limite_semanal'
                           and criado_em >= inicio_semana_luanda()
                           and pedido_id <> new.id) then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N4', jsonb_build_object('limite', p.limite_verificacao_semanal));
  end if;

  return new;
end $$;

create or replace function avaliar_desconto_indicacao(p_cliente uuid, p_ponto uuid)
returns table (valor int, motivo text)
language plpgsql stable security definer set search_path = public as $$
declare
  p      parametros;
  lig    ligacoes_indicacao;
  v_tipo text;
  usados int;
begin
  if not funcionalidade_activa('indicacao') then
    return query select 0, 'programa_inactivo'; return;
  end if;
  select * into p from parametros where unico;
  select * into lig from ligacoes_indicacao where indicado_id = p_cliente and deletado_em is null;
  if not found then return query select 0, 'sem_ligacao'; return; end if;
  if lig.desconto_usado then return query select 0, 'desconto_usado'; return; end if;
  if cliente_ja_comprou(p_cliente) then return query select 0, 'cliente_nao_novo'; return; end if;

  -- Já há um pedido em curso com o desconto (evita o desconto em dois pedidos)
  if exists (select 1 from pedidos
              where cliente_id = p_cliente and desconto_indicacao > 0 and deletado_em is null
                and estado not in ('cancelado','estornado')) then
    return query select 0, 'desconto_em_curso'; return;
  end if;

  select tipo into v_tipo from pontos_entrega where id = p_ponto;
  -- Limite por local residencial: só conta os descontos de amigos da mesma pessoa
  if v_tipo = 'residencial' then
    select count(*) into usados
      from pontos_entrega_proximos(p_ponto) pp(id)
      join pedidos x on x.ponto_entrega_id = pp.id
      join ligacoes_indicacao l2 on l2.indicado_id = x.cliente_id and l2.deletado_em is null
     where x.desconto_indicacao > 0 and x.estado = 'entregue_pago' and x.deletado_em is null
       and l2.indicador_id = lig.indicador_id;
    if usados >= p.max_descontos_por_local then
      return query select 0, 'limite_local'; return;
    end if;
  end if;

  -- Valor garantido no momento da ligação (não o parâmetro actual)
  return query select lig.desconto_garantido, 'ok';
end $$;

create or replace function calcular_desconto_indicacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  g pedidos_grupo;
begin
  if new.grupo_id is not null then
    g := grupo_para_adesao(new.grupo_id);
    new.ponto_entrega_id := g.ponto_entrega_id;
    new.cozinha_id := g.cozinha_id;
  end if;

  if new.cozinha_id is null then
    new.cozinha_id := cozinha_padrao();
  end if;

  -- O servidor ignora qualquer valor enviado pela app e recalcula
  select d.valor into new.desconto_indicacao
    from avaliar_desconto_indicacao(new.cliente_id, new.ponto_entrega_id) d;
  -- Nunca mais do que o valor do pedido: o valor final não fica negativo
  new.desconto_indicacao := least(coalesce(new.desconto_indicacao, 0),
                                  greatest(coalesce(new.subtotal, 0) + coalesce(new.taxa_entrega, 0), 0));
  -- O desconto de boas-vindas só vale a partir do subtotal mínimo (sai da margem dos pratos)
  if coalesce(new.subtotal, 0) < (select desconto_subtotal_minimo from parametros where unico) then
    new.desconto_indicacao := 0;
  end if;
  return new;
end $function$;

create or replace function orcamento_pedido(p_itens jsonb, p_ponto_entrega uuid, p_cozinha uuid DEFAULT NULL::uuid, p_grupo uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cliente  uuid := cliente_actual();
  v_cozinha  uuid;
  v_item     jsonb;
  v_qtd      numeric;
  v_card     cardapio;
  v_itens    jsonb := '[]';
  v_subtotal integer := 0;
  v_ponto    pontos_entrega;
  v_zona     zonas;
  v_taxa     integer := 0;
  v_desc     record;
  v_desconto integer;
  v_motivo   text;
  v_grupo    pedidos_grupo;
  v_estimada integer;
  v_extra    integer;
  v_opcoes   jsonb;
  v_texto    text;
  v_preco    integer;
begin
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'pedido_vazio' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_itens) > 30 then
    raise exception 'itens_a_mais' using errcode = 'P0001';
  end if;

  -- Cozinha do pedido (I8): a do grupo; senão a escolhida pelo cliente (com multi_cozinha);
  -- senão a cozinha por defeito. Tem de estar activa para aceitar pedidos.
  if p_grupo is not null then
    v_grupo := grupo_para_adesao(p_grupo);
    v_cozinha := v_grupo.cozinha_id;
  elsif funcionalidade_activa('multi_cozinha') then
    v_cozinha := coalesce(p_cozinha, cozinha_padrao());
  else
    v_cozinha := cozinha_padrao();
  end if;
  if not cozinha_aceita_pedidos(v_cozinha) then
    raise exception 'cozinha_indisponivel' using errcode = 'P0001';
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
    -- Prato montado (I9): as opções escolhidas validam-se e somam ao preço
    v_extra := 0; v_opcoes := null; v_texto := null;
    if funcionalidade_activa('pratos_montaveis') then
      select o.extra, o.opcoes, o.descricao into v_extra, v_opcoes, v_texto
        from opcoes_do_item(v_card.id, v_item -> 'opcoes') o;
    end if;
    v_preco := v_card.preco + coalesce(v_extra, 0);
    v_itens := v_itens || jsonb_strip_nulls(jsonb_build_object(
      'cardapio_id', v_card.id,
      'prato_base_id', v_card.prato_base_id,
      'nome', v_card.nome || coalesce(' (' || v_texto || ')', ''),
      'qtd', v_qtd::int,
      'preco_unitario', v_preco,
      'opcoes', case when v_texto is not null then v_opcoes end,
      'componentes_excluidos', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_excluidos', 'null') end,
      'componentes_ajustados', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_ajustados', 'null') end));
    v_subtotal := v_subtotal + v_qtd::int * v_preco;
    v_card := null;
  end loop;

  -- Pedido de grupo (I6): o ponto é o do grupo; a taxa da entrega única é repartida no
  -- fecho do grupo (fechar_grupo_interno), por isso aqui fica 0 e devolve-se a estimativa.
  if p_grupo is not null then
    select * into v_ponto from pontos_entrega where id = v_grupo.ponto_entrega_id;
    select * into v_zona from zonas where id = v_ponto.zona_id and deletado_em is null;
    if not found then
      raise exception 'ponto_sem_zona' using errcode = 'P0001';
    end if;
    v_estimada := taxa_grupo_estimada(p_grupo, v_cliente);
  else
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

  select * into v_desc from avaliar_desconto_indicacao(v_cliente, v_ponto.id);
  -- O desconto nunca passa o valor do pedido (subtotal + taxa)
  v_desconto := least(coalesce(v_desc.valor, 0), v_subtotal + v_taxa);
  v_motivo := v_desc.motivo;
  -- O desconto de boas-vindas só vale a partir do subtotal mínimo (sai da margem dos pratos)
  if v_desconto > 0 and v_subtotal < (select desconto_subtotal_minimo from parametros where unico) then
    v_desconto := 0;
    v_motivo := 'pedido_minimo';
  end if;

  return jsonb_build_object(
    'itens', v_itens,
    'subtotal', v_subtotal,
    'zona_id', v_zona.id,
    'zona_nome', v_zona.nome,
    'taxa_entrega', v_taxa,
    'desconto', v_desconto,
    'motivo_desconto', v_motivo,
    'desconto_subtotal_minimo', (select desconto_subtotal_minimo from parametros where unico),
    'total', v_subtotal + v_taxa - v_desconto,
    'taxa_grupo_estimada', v_estimada);
end $function$;

create or replace function pedir_levantamento(p_valor integer, p_metodo text, p_numero text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cliente uuid := cliente_actual();
  p         parametros;
  v_numero  text := normalizar_telefone(p_numero);
  v_lote    uuid := gen_random_uuid();
  v_p1      int;
begin
  if not funcionalidade_activa('indicacao') then
    raise exception 'programa_inactivo' using errcode = 'P0001';
  end if;
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if p_metodo is null or p_metodo not in ('multicaixa_express','unitel_money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if v_numero is null or length(v_numero) <> 9 then
    raise exception 'numero_invalido' using errcode = 'P0001';
  end if;

  -- Só levanta quem já é cliente: pelo menos um pedido seu entregue e pago
  if not exists (select 1 from pedidos where cliente_id = v_cliente and estado = 'entregue_pago'
                                         and deletado_em is null) then
    raise exception 'sem_compra_propria' using errcode = 'P0001';
  end if;

  select * into p from parametros where unico;
  -- Um pedido de cada vez por cliente (evita gastar o mesmo saldo duas vezes)
  perform pg_advisory_xact_lock(hashtext('saldo_indicacao:' || v_cliente::text));

  if p_valor is null or p_valor < p.levantamento_minimo then
    raise exception 'abaixo_minimo' using errcode = 'P0001';
  end if;
  if p_valor > saldo_disponivel_de(v_cliente) then
    raise exception 'saldo_insuficiente' using errcode = 'P0001';
  end if;

  if p_valor > p.limite_parcelamento then
    v_p1 := ceil(p_valor / 2.0);
    insert into pagamentos_indicacao
      (indicador_id, valor, tipo, metodo, numero_destino, lote_id, parcela, total_parcelas, dispositivo_id)
    values
      (v_cliente, v_p1,           'levantamento', p_metodo, v_numero, v_lote, 1, 2, 'servidor'),
      (v_cliente, p_valor - v_p1, 'levantamento', p_metodo, v_numero, v_lote, 2, 2, 'servidor');
  else
    insert into pagamentos_indicacao
      (indicador_id, valor, tipo, metodo, numero_destino, lote_id, dispositivo_id)
    values (v_cliente, p_valor, 'levantamento', p_metodo, v_numero, v_lote, 'servidor');
  end if;

  perform registar_auditoria('levantamento_pedido', 'pagamentos_indicacao', v_lote,
    jsonb_build_object('valor', p_valor, 'metodo', p_metodo));
  return v_lote;
end $function$;

create or replace function resumo_caixa(p_caixa uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c        caixa := caixa_para_gerir(p_caixa, false);
  v_vendas numeric;
  v_pedidos int;
  v_pac    numeric;
  v_npac   int;
  v_sang   numeric;
  v_comp   jsonb;
begin
  select coalesce(sum((p ->> 'valor')::numeric), 0), count(distinct v.pedido_id)
    into v_vendas, v_pedidos
    from vendas v cross join lateral jsonb_array_elements(v.parcelas) p
   where v.caixa_id = c.id and v.deletado_em is null and p ->> 'metodo' = 'Dinheiro';
  select coalesce(sum(preco), 0), count(*) into v_pac, v_npac
    from adesoes_pacote
   where caixa_id = c.id and metodo = 'loja' and deletado_em is null and estado in ('activa', 'reembolsada');
  select coalesce(sum((s ->> 'valor')::numeric), 0) into v_sang from jsonb_array_elements(c.sangrias) s;
  -- Pagamentos electrónicos da caixa: referência e foto do comprovativo, para conferir antes de fechar
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', k.id, 'pedido_id', k.pedido_id, 'cliente_nome', cl.nome, 'metodo', k.metodo, 'valor', k.valor,
           'referencia', k.referencia, 'caminho', k.caminho, 'estado', k.estado, 'nota', k.nota,
           'registado_por', f.nome, 'criado_em', k.criado_em) order by k.criado_em), '[]')
    into v_comp
    from comprovativos_pagamento k
    join pedidos x on x.id = k.pedido_id
    join clientes cl on cl.id = x.cliente_id
    left join funcionarios f on f.id = k.registado_por
   where k.caixa_id = c.id and k.deletado_em is null;
  return jsonb_build_object(
    'caixa_id', c.id, 'posto', c.posto, 'data', c.data, 'cozinha_id', c.cozinha_id,
    'aberta_por', c.funcionario_nome, 'troco_inicial', coalesce(c.troco_inicial, 0),
    'dinheiro_vendas', v_vendas, 'pedidos', v_pedidos, 'dinheiro_pacotes', v_pac, 'pacotes', v_npac,
    'sangrias', v_sang, 'lista_sangrias', c.sangrias,
    'esperado', coalesce(c.troco_inicial, 0) + v_vendas + v_pac - v_sang,
    'electronico', (select coalesce(sum((e ->> 'valor')::numeric), 0) from jsonb_array_elements(v_comp) e),
    'comprovativos', v_comp,
    'por_conferir', (select count(*) from jsonb_array_elements(v_comp) e where e ->> 'estado' = 'por_conferir'),
    'rejeitados', (select count(*) from jsonb_array_elements(v_comp) e where e ->> 'estado' = 'rejeitado'),
    'valor_rejeitado', (select coalesce(sum((e ->> 'valor')::numeric), 0) from jsonb_array_elements(v_comp) e
                         where e ->> 'estado' = 'rejeitado'),
    'fechamento', c.fechamento);
end $function$;

create or replace function fechar_caixa(p_caixa uuid, p_contado numeric, p_observacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_func uuid := exigir_permissao('vendas.registar');
  c      caixa;
  v_res  jsonb;
  v_fech jsonb;
begin
  perform caixa_para_gerir(p_caixa);
  select * into c from caixa where id = p_caixa for update;
  if c.fechamento is not null then raise exception 'caixa_fechada' using errcode = 'P0001'; end if;
  if p_contado is null or p_contado < 0 or p_contado > 100000000 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if p_observacao is not null and length(p_observacao) > 300 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  v_res := resumo_caixa(p_caixa);
  -- Todos os pagamentos electrónicos têm de ser conferidos (ou rejeitados) antes do fecho
  if (v_res ->> 'por_conferir')::int > 0 then
    raise exception 'comprovativos_por_conferir' using errcode = 'P0001', detail = v_res ->> 'por_conferir';
  end if;
  v_fech := (v_res - 'fechamento' - 'lista_sangrias' - 'comprovativos' - 'caixa_id' - 'cozinha_id') || jsonb_build_object(
    'contado', p_contado, 'diferenca', p_contado - (v_res ->> 'esperado')::numeric,
    'fechado_em', now(), 'funcionario_id', v_func,
    'funcionario_nome', (select nome from funcionarios where id = v_func),
    'observacao', nullif(trim(p_observacao), ''));
  update caixa set fechamento = v_fech, atualizado_em = now() where id = p_caixa;
  perform registar_auditoria('caixa_fechada', 'caixa', p_caixa, v_fech);
  return v_fech;
end $function$;
