-- =============================================================================
-- Pedidos agendados — Fase 2
-- -----------------------------------------------------------------------------
--  1. Alertas por pedido agendado (para a cozinha agir antes da hora):
--     * fora_de_horario  — um prato não está disponível à hora agendada (horários do cardápio);
--     * doses            — o que está agendado para o dia passa as doses do prato (doses_dia);
--     * hora_cheia       — a cozinha tem muitos agendados na mesma hora
--                          (parametros.agendados_por_hora_max, por defeito 8).
--  2. Reagendar a pedido do cliente: nova hora (20 min a 14 dias), aviso ao cliente e auditoria.
--  3. Indicadores dos agendados para o relatório da cozinha: nº, valor, cancelados, a tempo,
--     antecedência e horas mais pedidas.
-- (A lista exporta-se para CSV na app; não precisa de servidor.)
-- =============================================================================

alter table parametros
  add column if not exists agendados_por_hora_max int not null default 8
    check (agendados_por_hora_max between 1 and 200);
comment on column parametros.agendados_por_hora_max is
  'Agendados da mesma cozinha na mesma hora a partir dos quais se avisa (capacidade da faixa horária)';

-- Um prato está disponível a uma hora concreta? (o mesmo critério de cardapio_aberto_agora)
create or replace function cardapio_aberto_em(p_id uuid, p_quando timestamptz)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_de timestamptz; v_ate timestamptz;
  v_ts timestamp := p_quando at time zone 'Africa/Luanda';
begin
  select disponivel_de, disponivel_ate into v_de, v_ate from cardapio where id = p_id;
  if v_de is null and v_ate is null
     and not exists (select 1 from cardapio_horarios where cardapio_id = p_id) then
    return true;
  end if;
  if (v_de is not null or v_ate is not null)
     and (v_de is null or p_quando >= v_de) and (v_ate is null or p_quando < v_ate) then
    return true;
  end if;
  return exists (
    select 1 from cardapio_horarios h
     where h.cardapio_id = p_id
       and ( (h.dia_semana is not null and h.dia_semana = extract(isodow from v_ts)::int)
             or (h.data is not null and h.data = v_ts::date) )
       and janela_hora(v_ts::time, h.hora_inicio, h.hora_fim) );
end $$;
revoke execute on function cardapio_aberto_em(uuid, timestamptz) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 1. Alertas
-- -----------------------------------------------------------------------------
create or replace function alertas_agendados(p_inicio date, p_fim date, p_cozinha uuid default null)
returns table (pedido_id uuid, tipo text, detalhe text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini date := coalesce(p_inicio, (now() at time zone 'Africa/Luanda')::date);
  v_fim date := coalesce(p_fim, v_ini + 6);
  v_max int  := (select agendados_por_hora_max from parametros where unico);
begin
  if not (tem_permissao('pedidos.gerir') or tem_permissao('entregas.registar')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir / entregas.registar';
  end if;
  if v_fim < v_ini or v_fim - v_ini > 62 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  return query
  with ag as (
    select x.id, x.cozinha_id, x.agendado_para, x.itens,
           (x.agendado_para at time zone 'Africa/Luanda')::date as dia,
           date_trunc('hour', x.agendado_para at time zone 'Africa/Luanda') as hora
      from pedidos x
     where x.deletado_em is null and x.agendado_para is not null
       and x.estado in ('pendente', 'confirmado', 'em_preparacao')
       and (x.agendado_para at time zone 'Africa/Luanda')::date between v_ini and v_fim
       and (p_cozinha is null or x.cozinha_id = p_cozinha)
  ),
  linhas as (
    select ag.id, ag.cozinha_id, ag.dia, ag.agendado_para, (i ->> 'cardapio_id')::uuid as cardapio_id,
           coalesce((i ->> 'qtd')::int, 1) as qtd
      from ag cross join jsonb_array_elements(coalesce(ag.itens, '[]')) i
     where i ? 'cardapio_id'
  ),
  doses as (
    select l.dia, l.cardapio_id, sum(l.qtd)::int as total, c.doses_dia, c.nome
      from linhas l join cardapio c on c.id = l.cardapio_id
     where c.doses_dia is not null
     group by l.dia, l.cardapio_id, c.doses_dia, c.nome
    having sum(l.qtd) > c.doses_dia
  )
  -- Prato fora do horário à hora agendada
  select distinct l.id, 'fora_de_horario'::text, c.nome
    from linhas l join cardapio c on c.id = l.cardapio_id
   where not cardapio_aberto_em(l.cardapio_id, l.agendado_para)
  union all
  -- Doses do dia insuficientes para o que está agendado
  select distinct l.id, 'doses'::text, format('%s: %s agendados para %s doses', d.nome, d.total, d.doses_dia)
    from linhas l join doses d on d.dia = l.dia and d.cardapio_id = l.cardapio_id
  union all
  -- Muitos agendados na mesma hora, na mesma cozinha
  select ag.id, 'hora_cheia'::text, format('%s agendados das %sh às %sh', h.n, to_char(ag.hora, 'HH24'),
                                           to_char(ag.hora + interval '1 hour', 'HH24'))
    from ag join (select cozinha_id, hora, count(*)::int as n from ag group by cozinha_id, hora) h
      on h.cozinha_id is not distinct from ag.cozinha_id and h.hora = ag.hora
   where h.n >= v_max;
end $$;
revoke execute on function alertas_agendados(date, date, uuid) from public, anon;
grant  execute on function alertas_agendados(date, date, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Reagendar (a pedido do cliente)
-- -----------------------------------------------------------------------------
create or replace function reagendar_pedido(p_pedido uuid, p_nova timestamptz, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ped pedidos;
begin
  select * into v_ped from pedidos where id = p_pedido and deletado_em is null for update;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not pode_na_cozinha('pedidos.gerir', v_ped.cozinha_id) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir';
  end if;
  if v_ped.agendado_para is null or v_ped.grupo_id is not null or v_ped.estado not in ('pendente', 'confirmado') then
    raise exception 'pedido_nao_reagendavel' using errcode = 'P0001';
  end if;
  if p_nova is null or p_nova < now() + interval '20 minutes' or p_nova > now() + interval '14 days' then
    raise exception 'agendamento_invalido' using errcode = 'P0001', detail = 'entre 20 minutos e 14 dias';
  end if;
  update pedidos set agendado_para = p_nova, hora_prometida = p_nova, atualizado_em = now() where id = p_pedido;
  perform registar_auditoria('pedido_reagendado', 'pedidos', p_pedido,
    jsonb_build_object('de', v_ped.agendado_para, 'para', p_nova, 'motivo', nullif(trim(p_motivo), '')));
  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (v_ped.cliente_id, 'N31', jsonb_build_object(
    'titulo', 'Pedido reagendado',
    'corpo', 'O teu pedido passou para ' || to_char(p_nova at time zone 'Africa/Luanda', 'DD/MM "às" HH24:MI') || '.',
    'link', '/pedido/' || p_pedido));
end $$;
revoke execute on function reagendar_pedido(uuid, timestamptz, text) from public, anon;
grant  execute on function reagendar_pedido(uuid, timestamptz, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Indicadores dos agendados (relatório da cozinha)
-- -----------------------------------------------------------------------------
create or replace function indicadores_agendados(p_cozinha uuid, p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  r     jsonb;
begin
  if not pode_ver_relatorio(p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'relatorios.exportar (desta cozinha)';
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 365 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  with a as (
    select x.* from pedidos x
     where x.cozinha_id = p_cozinha and x.deletado_em is null and x.agendado_para is not null
       and x.agendado_para >= v_ini and x.agendado_para < v_fim
  )
  select jsonb_build_object(
    'pedidos', (select count(*) from a),
    'entregues', (select count(*) from a where estado = 'entregue_pago'),
    'valor', (select coalesce(sum(subtotal), 0) from a where estado = 'entregue_pago'),
    'cancelados', (select count(*) from a where estado in ('cancelado', 'estornado')),
    'a_tempo', (select count(*) from a where estado = 'entregue_pago' and entregue_em <= agendado_para + interval '10 minutes'),
    'antecedencia_horas', (select round((percentile_cont(0.5) within group (
                              order by extract(epoch from agendado_para - criado_em) / 3600))::numeric, 1) from a),
    'horas', coalesce((select jsonb_agg(jsonb_build_object('hora', h, 'pedidos', n) order by n desc, h)
                         from (select to_char(agendado_para at time zone 'Africa/Luanda', 'HH24') as h, count(*) as n
                                 from a group by 1 order by 2 desc limit 5) t), '[]')
  ) into r;
  return r;
end $$;
revoke execute on function indicadores_agendados(uuid, date, date) from public, anon;
grant  execute on function indicadores_agendados(uuid, date, date) to authenticated;
