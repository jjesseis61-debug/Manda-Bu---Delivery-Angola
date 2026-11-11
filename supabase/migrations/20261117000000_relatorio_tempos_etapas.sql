-- =============================================================================
-- Relatório da cozinha: tempo de cada etapa do pedido
-- -----------------------------------------------------------------------------
-- Etapas (pedidos entregues, sem os agendados — esses esperam de propósito):
--   1. Confirmar      pedido feito      → confirmado
--   2. Começar        confirmado        → em preparação
--   3. Preparar       em preparação     → saiu para entrega (inclui esperar pelo estafeta)
--   4. Entregar       saiu              → entregue
--   Total             pedido feito      → entregue
-- Mostra a mediana (o "normal") e o p90 (os 10% piores), a etapa que mais pesa, a pontualidade
-- face à hora prometida (inclui agendados), por hora do dia, por estafeta e os pedidos mais lentos.
--
-- Horas de cada etapa: a partir de agora ficam no próprio pedido (confirmado_em, saiu_em; o
-- preparado_em e o entregue_em já existiam). Para os pedidos antigos usa-se a auditoria, que
-- regista cada mudança de estado — por isso o relatório tem histórico desde o início, sem
-- reescrever pedidos antigos.
-- =============================================================================

alter table pedidos
  add column if not exists confirmado_em timestamptz,
  add column if not exists saiu_em       timestamptz;
comment on column pedidos.confirmado_em is 'Quando o pedido foi confirmado pela cozinha. Só o servidor escreve.';
comment on column pedidos.saiu_em is 'Quando o pedido saiu para entrega. Só o servidor escreve.';

create or replace function pedidos_registar_etapas() returns trigger
language plpgsql set search_path = public as $$
begin
  -- Ninguém mexe nestas horas à mão: só mudam na própria transição de estado
  new.confirmado_em := old.confirmado_em;
  new.saiu_em := old.saiu_em;
  if new.estado is distinct from old.estado then
    if new.estado = 'confirmado' then
      new.confirmado_em := coalesce(old.confirmado_em, now());
    elsif new.estado = 'em_entrega' then
      new.saiu_em := coalesce(old.saiu_em, now());
    end if;
  end if;
  return new;
end $$;
revoke execute on function pedidos_registar_etapas() from public, anon, authenticated;

drop trigger if exists trg_pedidos_4_etapas on pedidos;
create trigger trg_pedidos_4_etapas before update on pedidos
for each row execute function pedidos_registar_etapas();

-- Primeira vez que o pedido entrou num estado, segundo a auditoria (pedidos antigos)
create or replace function hora_estado_auditoria(p_pedido uuid, p_estado text)
returns timestamptz language sql stable set search_path = public as $$
  select min(a.data) from auditoria a
   where a.ref_id = p_pedido and a.acao = 'pedido_estado'
     and (case when a.detalhe like '{%' then a.detalhe::jsonb ->> 'para' end) = p_estado;
$$;
revoke execute on function hora_estado_auditoria(uuid, text) from public, anon, authenticated;

create or replace function tempos_etapas_cozinha(p_cozinha uuid, p_inicio date, p_fim date)
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

  with base as (
    select p.id, p.criado_em, p.entregue_em, p.hora_prometida, p.agendado_para, p.entregador_id,
           coalesce(p.confirmado_em, hora_estado_auditoria(p.id, 'confirmado'))    as conf,
           coalesce(p.preparado_em,  hora_estado_auditoria(p.id, 'em_preparacao')) as prep,
           coalesce(p.saiu_em,       hora_estado_auditoria(p.id, 'em_entrega'))    as saiu
      from pedidos p
     where p.cozinha_id = p_cozinha and p.deletado_em is null
       and p.estado = 'entregue_pago' and p.entregue_em is not null
       and p.criado_em >= v_ini and p.criado_em < v_fim
  ),
  -- Durações em minutos; uma etapa só conta se as duas horas existirem e estiverem por ordem
  d as (
    select b.*,
           case when b.conf >= b.criado_em then extract(epoch from b.conf - b.criado_em) / 60 end as m_confirmar,
           case when b.prep >= b.conf      then extract(epoch from b.prep - b.conf) / 60      end as m_comecar,
           case when b.saiu >= b.prep      then extract(epoch from b.saiu - b.prep) / 60      end as m_preparar,
           case when b.entregue_em >= b.saiu then extract(epoch from b.entregue_em - b.saiu) / 60 end as m_entregar,
           case when b.entregue_em >= b.criado_em then extract(epoch from b.entregue_em - b.criado_em) / 60 end as m_total
      from base b
  ),
  imed as (select * from d where agendado_para is null),
  etapas as (
    select e.ordem, e.chave, e.nome,
           count(e.m)::int as n,
           round(percentile_cont(0.5) within group (order by e.m)::numeric, 1) as mediana,
           round(percentile_cont(0.9) within group (order by e.m)::numeric, 1) as p90
      from imed i
      cross join lateral (values
        (1, 'confirmar', 'Confirmar o pedido', i.m_confirmar),
        (2, 'comecar',   'Começar a preparar', i.m_comecar),
        (3, 'preparar',  'Preparar e esperar estafeta', i.m_preparar),
        (4, 'entregar',  'Entrega (caminho)', i.m_entregar),
        (5, 'total',     'Total: pedido → entregue', i.m_total)) as e(ordem, chave, nome, m)
     group by e.ordem, e.chave, e.nome
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
    'pedidos', (select count(*) from imed),
    'agendados_fora', (select count(*) from d where agendado_para is not null),
    'etapas', coalesce((select jsonb_agg(jsonb_build_object('chave', chave, 'nome', nome, 'n', n,
                                                            'mediana', mediana, 'p90', p90) order by ordem)
                          from etapas), '[]'),
    -- Etapa que mais pesa (maior mediana, sem contar o total)
    'gargalo', (select chave from etapas where chave <> 'total' and mediana is not null
                 order by mediana desc limit 1),
    'pontualidade', (select jsonb_build_object(
                       'com_hora', count(*),
                       'a_tempo', count(*) filter (where entregue_em <= hora_prometida),
                       'atrasados', count(*) filter (where entregue_em > hora_prometida),
                       'atraso_mediano', round((percentile_cont(0.5) within group (
                          order by extract(epoch from entregue_em - hora_prometida) / 60)
                          filter (where entregue_em > hora_prometida))::numeric, 1))
                       from d where hora_prometida is not null),
    'por_hora', coalesce((select jsonb_agg(x order by x ->> 'hora') from (
                   select jsonb_build_object(
                            'hora', to_char(criado_em at time zone 'Africa/Luanda', 'HH24'),
                            'pedidos', count(*),
                            'total_mediana', round(percentile_cont(0.5) within group (order by m_total)::numeric, 1),
                            'atrasados', count(*) filter (where entregue_em > hora_prometida)) as x
                     from imed group by to_char(criado_em at time zone 'Africa/Luanda', 'HH24')) h), '[]'),
    'estafetas', coalesce((select jsonb_agg(x order by (x ->> 'entregas')::int desc) from (
                   select jsonb_build_object(
                            'nome', coalesce(f.nome, 'Sem registo'),
                            'entregas', count(*),
                            'entrega_mediana', round(percentile_cont(0.5) within group (order by i.m_entregar)::numeric, 1),
                            'atrasados', count(*) filter (where i.entregue_em > i.hora_prometida)) as x
                     from imed i left join funcionarios f on f.id = i.entregador_id
                    group by f.nome) e), '[]'),
    'mais_lentos', coalesce((select jsonb_agg(x) from (
                   select jsonb_build_object(
                            'pedido_id', i.id,
                            'criado_em', i.criado_em,
                            'total', round(i.m_total::numeric, 1),
                            'etapa', (select v.k from (values ('confirmar', i.m_confirmar), ('comecar', i.m_comecar),
                                                               ('preparar', i.m_preparar), ('entregar', i.m_entregar)) v(k, m)
                                       where v.m is not null order by v.m desc limit 1)) as x
                     from imed i where i.m_total is not null order by i.m_total desc limit 5) l), '[]')
  ) into r;
  return r;
end $$;
revoke execute on function tempos_etapas_cozinha(uuid, date, date) from public, anon;
grant  execute on function tempos_etapas_cozinha(uuid, date, date) to authenticated;
