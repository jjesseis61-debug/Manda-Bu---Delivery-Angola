-- =============================================================================
-- 1) Prato montável padrão em cada cozinha
-- -----------------------------------------------------------------------------
-- Ao criar uma cozinha, o servidor clona o prato montável modelo ("Serve o teu
-- próprio prato") com os grupos e as opções. O clone nasce DESACTIVADO (rascunho):
-- a cozinha revê opções e preços e activa. O administrador escolhe o modelo
-- (parametros.cardapio_modelo_montavel); sem escolha, usa-se o "Serve o teu..."
-- mais antigo (o da Viana). Não duplica: se a cozinha já tiver um prato com o
-- mesmo nome, não cria outro. Criar a cozinha nunca falha por causa do clone.
--
-- 2) Pedidos agendados (ecrã próprio no operador)
-- -----------------------------------------------------------------------------
-- agendados_operador(p_inicio, p_fim, p_cozinha): todos os agendados de um período
-- (dias de Luanda), com telefone, morada, itens com opções, observações, a receber,
-- estado, "já na fila" e a hora do alerta. Mesmas permissões de pedidos_operador.
--
-- 3) Alerta de agendado por confirmar (aviso N41 aos gerentes da cozinha)
-- -----------------------------------------------------------------------------
--  * parametros.alerta_agendado_horas (3) antes da hora agendada, se ainda pendente;
--  * fora do turno (parametros.turno_hora_inicio/fim) o aviso sai no início do turno
--    (entrega às 10h -> aviso às 9h); se cair depois do fim do turno, sai 1 h antes do fim;
--  * agendado com menos antecedência do que isso -> aviso logo;
--  * URGENTE quando entra na fila (90 min antes) e continua pendente.
-- =============================================================================

alter table parametros
  add column if not exists cardapio_modelo_montavel uuid references cardapio(id) on delete set null,
  add column if not exists alerta_agendado_horas int not null default 3
    check (alerta_agendado_horas between 1 and 48);
create index if not exists parametros_cardapio_modelo_montavel_idx on parametros (cardapio_modelo_montavel);
comment on column parametros.cardapio_modelo_montavel is
  'Prato montável copiado para as cozinhas novas (null = o "Serve o teu próprio prato" mais antigo)';
comment on column parametros.alerta_agendado_horas is
  'Horas antes da entrega em que se avisa a cozinha de um agendado ainda por confirmar (N41)';

-- -----------------------------------------------------------------------------
-- 1. Clonar o prato montável
-- -----------------------------------------------------------------------------
create or replace function e_montavel(p_cardapio uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from cardapio c
                  where c.id = p_cardapio and c.deletado_em is null
                    and exists (select 1 from opcoes_grupos g
                                 where g.cardapio_id = c.id and g.deletado_em is null));
$$;
revoke execute on function e_montavel(uuid) from public, anon, authenticated;

-- O modelo em uso: o escolhido pelo admin, se ainda for um montável; senão o
-- "Serve o teu próprio prato" mais antigo.
create or replace function modelo_montavel() returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.cardapio_modelo_montavel from parametros p
      where p.unico and e_montavel(p.cardapio_modelo_montavel)),
    (select c.id from cardapio c
      where c.deletado_em is null and c.nome ilike 'serve o teu%' and e_montavel(c.id)
      order by c.criado_em, c.id limit 1));
$$;
revoke execute on function modelo_montavel() from public, anon, authenticated;

-- Copia o prato (desactivado), os grupos e as opções. Devolve o id do prato novo,
-- ou null se não houver modelo ou se a cozinha já tiver um prato com o mesmo nome.
-- Não chamável pelas apps: só pelo trigger e pelo wrapper com permissão.
create or replace function clonar_montavel(p_cozinha uuid, p_modelo uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_modelo uuid := coalesce(p_modelo, modelo_montavel());
  m        cardapio;
  v_novo   uuid;
  g        record;
  v_grupo  uuid;
begin
  if p_modelo is not null and not e_montavel(p_modelo) then
    raise exception 'modelo_invalido' using errcode = 'P0001';
  end if;
  if v_modelo is null
     or not exists (select 1 from cozinhas where id = p_cozinha and deletado_em is null) then
    return null;
  end if;
  select * into m from cardapio where id = v_modelo;
  if exists (select 1 from cardapio c
              where c.cozinha_id = p_cozinha and c.deletado_em is null
                and lower(trim(c.nome)) = lower(trim(m.nome))) then
    return null;
  end if;

  insert into cardapio (dispositivo_id, cozinha_id, prato_base_id, nome, descricao, categoria, preco,
                        foto_url, disponivel, do_dia, ordem, visivel_online, minimo_montavel)
  values ('servidor', p_cozinha, m.prato_base_id, m.nome, m.descricao, m.categoria, m.preco,
          m.foto_url, false, false, m.ordem, m.visivel_online, m.minimo_montavel)
  returning id into v_novo;

  for g in select * from opcoes_grupos
            where cardapio_id = v_modelo and deletado_em is null order by ordem, criado_em loop
    insert into opcoes_grupos (dispositivo_id, cardapio_id, nome, minimo, maximo, ordem)
    values ('servidor', v_novo, g.nome, g.minimo, g.maximo, g.ordem)
    returning id into v_grupo;
    insert into opcoes (dispositivo_id, grupo_id, nome, preco_extra, disponivel, ordem, componentes, foto_url)
    select 'servidor', v_grupo, o.nome, o.preco_extra, o.disponivel, o.ordem, o.componentes, o.foto_url
      from opcoes o
     where o.grupo_id = g.id and o.deletado_em is null
     order by o.ordem, o.criado_em;
  end loop;

  perform registar_auditoria('montavel_clonado', 'cardapio', v_novo,
                             jsonb_build_object('modelo', v_modelo, 'cozinha', p_cozinha));
  return v_novo;
end $$;
revoke execute on function clonar_montavel(uuid, uuid) from public, anon, authenticated;

-- Cozinha nova -> prato montável do modelo. Um erro no clone não impede criar a cozinha.
create or replace function cozinha_nova_montavel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform clonar_montavel(new.id);
  exception when others then
    raise warning 'clonar_montavel(%) falhou: %', new.id, sqlerrm;
  end;
  return new;
end $$;
revoke execute on function cozinha_nova_montavel() from public, anon, authenticated;

drop trigger if exists trg_montavel_padrao on cozinhas;
create trigger trg_montavel_padrao after insert on cozinhas
  for each row execute function cozinha_nova_montavel();

-- Para cozinhas que já existem (botão em Cardápio). Erro claro se não criar.
create or replace function criar_montavel_do_modelo(p_cozinha uuid, p_modelo uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v uuid;
begin
  perform exigir_permissao('cozinhas.gerir');
  if coalesce(p_modelo, modelo_montavel()) is null then
    raise exception 'sem_modelo' using errcode = 'P0001';
  end if;
  v := clonar_montavel(p_cozinha, p_modelo);
  if v is null then
    raise exception 'montavel_ja_existe' using errcode = 'P0001';
  end if;
  return v;
end $$;
revoke execute on function criar_montavel_do_modelo(uuid, uuid) from public, anon;
grant  execute on function criar_montavel_do_modelo(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Hora do alerta de um agendado (regra do turno)
-- -----------------------------------------------------------------------------
create or replace function momento_alerta_agendado(p_agendado timestamptz)
returns timestamptz language plpgsql stable security definer set search_path = public as $$
declare
  p     parametros;
  v_loc timestamp;
  v_h   int;
begin
  select * into p from parametros where unico;
  v_loc := (p_agendado - make_interval(hours => p.alerta_agendado_horas)) at time zone 'Africa/Luanda';
  v_h := extract(hour from v_loc);
  if v_h < p.turno_hora_inicio then
    v_loc := date_trunc('day', v_loc) + make_interval(hours => p.turno_hora_inicio);
  elsif v_h >= p.turno_hora_fim then
    v_loc := date_trunc('day', v_loc) + make_interval(hours => p.turno_hora_fim - 1);
  end if;
  return v_loc at time zone 'Africa/Luanda';
end $$;
revoke execute on function momento_alerta_agendado(timestamptz) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Lista de agendados para o ecrã do operador
-- -----------------------------------------------------------------------------
create or replace function agendados_operador(p_inicio date default null, p_fim date default null,
                                              p_cozinha uuid default null)
 returns table(pedido_id uuid, criado_em timestamptz, agendado_para timestamptz, estado text,
               cozinha_id uuid, cozinha_nome text, cliente_nome text, cliente_telefone text,
               itens jsonb, subtotal integer, taxa_entrega integer, desconto_indicacao integer,
               credito_indicacao_usado integer, pago_pacote integer, valor_empresa integer,
               a_pagar integer, observacoes text, ponto_tipo text, ponto_lat double precision,
               ponto_lng double precision, ponto_referencia text, zona_nome text,
               empresa boolean, grupo boolean, atribuido_a_nome text, na_fila boolean,
               alerta_em timestamptz)
 language plpgsql stable security definer set search_path = public as $$
declare
  v_ini date := coalesce(p_inicio, (now() at time zone 'Africa/Luanda')::date);
  v_fim date := coalesce(p_fim, v_ini + 6);
begin
  if not (tem_permissao('pedidos.gerir') or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  if v_fim < v_ini or v_fim - v_ini > 62 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  return query
  select x.id, x.criado_em, x.agendado_para, x.estado, x.cozinha_id, k.nome, c.nome, c.telefone, x.itens,
         x.subtotal::int, x.taxa_entrega::int, x.desconto_indicacao::int, x.credito_indicacao_usado::int,
         x.pago_pacote::int, x.valor_empresa::int,
         (x.subtotal + x.taxa_entrega - x.desconto_indicacao - x.credito_indicacao_usado - x.pago_pacote - x.valor_empresa)::int,
         x.observacoes, pe.tipo, pe.lat, pe.lng, pe.referencia, z.nome,
         x.empresa_id is not null, x.grupo_id is not null,
         (select f.nome from funcionarios f where f.id = x.atribuido_a),
         x.agendado_para <= now() + interval '90 minutes',
         momento_alerta_agendado(x.agendado_para)
    from pedidos x
    join clientes c on c.id = x.cliente_id
    left join cozinhas k on k.id = x.cozinha_id
    left join pontos_entrega pe on pe.id = x.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, x.zona_id)
   where x.deletado_em is null
     and x.agendado_para is not null
     and x.estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')
     and (x.agendado_para at time zone 'Africa/Luanda')::date between v_ini and v_fim
     and (p_cozinha is null or x.cozinha_id = p_cozinha)
   order by x.agendado_para, x.criado_em;
end $$;
revoke execute on function agendados_operador(date, date, uuid) from public, anon;
grant  execute on function agendados_operador(date, date, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Aviso N41 (agendado por confirmar / urgente)
-- -----------------------------------------------------------------------------
alter table alertas_pedido drop constraint if exists alertas_pedido_tipo_check;
alter table alertas_pedido add constraint alertas_pedido_tipo_check
  check (tipo in ('sem_confirmacao', 'atraso', 'agendado_por_confirmar', 'agendado_urgente'));

-- Corre de 5 em 5 minutos. Só avisa dentro do turno (fora dele, o aviso sai no início do turno).
create or replace function job_alertas_agendados() returns int
language plpgsql security definer set search_path = public as $$
declare
  p      parametros;
  x      record;
  n      int := 0;
  v_h    int := extract(hour from now() at time zone 'Africa/Luanda');
  v_tipo text;
  v_resumo text;
begin
  select * into p from parametros where unico;
  if v_h < p.turno_hora_inicio or v_h >= p.turno_hora_fim then
    return 0;
  end if;
  for x in
    select pe.*, c.nome as cliente_nome,
           ceil(extract(epoch from pe.agendado_para - now()) / 60)::int as minutos
      from pedidos pe join clientes c on c.id = pe.cliente_id
     where pe.deletado_em is null and pe.estado = 'pendente' and pe.grupo_id is null
       and pe.agendado_para > now()
       and momento_alerta_agendado(pe.agendado_para) <= now()
  loop
    v_tipo := case when x.agendado_para <= now() + interval '90 minutes'
                   then 'agendado_urgente' else 'agendado_por_confirmar' end;
    continue when exists (select 1 from alertas_pedido a where a.pedido_id = x.id and a.tipo = v_tipo);
    select string_agg(coalesce(i ->> 'qtd', '1') || '× ' || trim(coalesce(i ->> 'nome', 'Prato')), ', ')
      into v_resumo from jsonb_array_elements(x.itens) i;
    insert into alertas_pedido (dispositivo_id, sincronizado_em, pedido_id, cliente_id, cozinha_id, tipo, minutos)
    values ('servidor', now(), x.id, x.cliente_id, x.cozinha_id, v_tipo, x.minutos);
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select g, 'N41', jsonb_build_object(
             'pedido_id', x.id,
             'cliente_nome', split_part(trim(x.cliente_nome), ' ', 1),
             'resumo', left(coalesce(v_resumo, 'pedido'), 80),
             'quando', to_char(x.agendado_para at time zone 'Africa/Luanda', 'DD/MM "às" HH24:MI'),
             'urgente', v_tipo = 'agendado_urgente')
      from gerentes_do_pedido(x.cozinha_id) g;
    perform registar_auditoria('alerta_' || v_tipo, 'pedidos', x.id, jsonb_build_object('minutos', x.minutos));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function job_alertas_agendados() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_alertas_agendados', '*/5 * * * *', 'select public.job_alertas_agendados()');
  end if;
end $$;

-- Texto, validade e envio do N41: acrescenta-se o N41 às definições actuais (sem as copiar
-- inteiras), com verificação de que cada substituição aconteceu.
do $$
declare
  v_def text;
  v_novo text;
begin
  -- texto_notificacao: título e corpo
  v_def := pg_get_functiondef('texto_notificacao(text, jsonb)'::regprocedure);
  v_novo := replace(v_def,
    $s$when p_codigo = 'N40' then 'Novo código de login'$s$,
    $s$when p_codigo = 'N40' then 'Novo código de login' when p_codigo = 'N41' then case when (p_dados ->> 'urgente')::boolean then 'URGENTE: agendado por confirmar' else 'Agendado por confirmar' end$s$);
  v_novo := replace(v_novo,
    $s$when 'N31' then p_dados ->> 'corpo'$s$,
    $s$when 'N41' then format('O pedido agendado de %s para %s (%s) ainda não foi confirmado.%s',
                                  coalesce(nullif(p_dados ->> 'cliente_nome', ''), 'um cliente'),
                                  p_dados ->> 'quando', p_dados ->> 'resumo',
                                  case when (p_dados ->> 'urgente')::boolean
                                       then ' Já entrou na fila: confirma agora ou liga ao cliente.'
                                       else ' Confirma ou liga ao cliente.' end)
           when 'N31' then p_dados ->> 'corpo'$s$);
  if v_novo = v_def or (length(v_novo) - length(v_def)) < 300 then
    raise exception 'N41: texto_notificacao não tem o formato esperado';
  end if;
  execute v_novo;

  -- notificacoes_por_enviar: o N41 é empurrado como push
  v_def := pg_get_functiondef('notificacoes_por_enviar(integer)'::regprocedure);
  v_novo := replace(v_def, $s$'N32', 'N40')$s$, $s$'N32', 'N40', 'N41')$s$);
  if v_novo = v_def then
    raise exception 'N41: notificacoes_por_enviar não tem o formato esperado';
  end if;
  execute v_novo;

  -- notificacao_valida: 3 horas (depois disso já há o aviso urgente ou o de atraso)
  v_def := pg_get_functiondef('notificacao_valida(text, timestamptz)'::regprocedure);
  v_novo := replace(v_def, $s$when 'N40' then$s$, $s$when 'N41' then interval '3 hours' when 'N40' then$s$);
  if v_novo = v_def then
    raise exception 'N41: notificacao_valida não tem o formato esperado';
  end if;
  execute v_novo;
end $$;

-- -----------------------------------------------------------------------------
-- 5. Modelo por defeito: o "Serve o teu próprio prato" mais antigo (Viana), se existir
-- -----------------------------------------------------------------------------
update parametros set cardapio_modelo_montavel = modelo_montavel()
 where unico and cardapio_modelo_montavel is null;
