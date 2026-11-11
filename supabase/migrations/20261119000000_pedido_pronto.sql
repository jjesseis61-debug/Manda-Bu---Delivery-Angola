-- =============================================================================
-- Pedido "Pronto": a cozinha marca quando acabou de preparar
-- -----------------------------------------------------------------------------
-- Não é um estado novo (o circuito pendente → confirmado → em preparação → em entrega →
-- entregue fica igual em todas as apps): é uma HORA no pedido (pronto_em) que a cozinha marca
-- com um botão enquanto o pedido está em preparação.
--  * O estafeta reservado recebe logo um aviso (N32, "Pedido pronto ✅") para ir buscar.
--  * O relatório separa "Preparar" (em preparação → pronto) de "Esperar o estafeta"
--    (pronto → saiu). Pedidos sem "Pronto" marcado ficam como até aqui (preparar inclui a espera).
--  * pedidos_operador passa a devolver pronto_em (as apps mostram "✅ Pronto").
-- =============================================================================

alter table pedidos add column if not exists pronto_em timestamptz;
comment on column pedidos.pronto_em is 'Quando a cozinha marcou o pedido como pronto. Só o servidor escreve (marcar_pedido_pronto).';

-- As horas das etapas só mudam pelo servidor: pronto_em só pela função marcar_pedido_pronto
create or replace function pedidos_registar_etapas() returns trigger
language plpgsql set search_path = public as $$
begin
  new.confirmado_em := old.confirmado_em;
  new.saiu_em := old.saiu_em;
  if coalesce(current_setting('mb.marcar_pronto', true), '') <> '1' then
    new.pronto_em := old.pronto_em;
  end if;
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

-- Marcar (ou desmarcar, se foi engano) o pedido como pronto
create or replace function marcar_pedido_pronto(p_pedido uuid, p_pronto boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ped     pedidos;
  v_reserva int := (select entrega_reserva_min from parametros where unico);
begin
  select * into v_ped from pedidos where id = p_pedido and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not pode_na_cozinha('pedidos.gerir', v_ped.cozinha_id) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir';
  end if;
  if v_ped.estado <> 'em_preparacao' then
    raise exception 'pedido_nao_em_preparacao' using errcode = 'P0001';
  end if;
  if coalesce(p_pronto, true) = (v_ped.pronto_em is not null) then
    return; -- já está como pedido
  end if;
  perform set_config('mb.marcar_pronto', '1', true);
  update pedidos set pronto_em = case when coalesce(p_pronto, true) then now() end, atualizado_em = now()
   where id = p_pedido;
  perform set_config('mb.marcar_pronto', '', true);
  perform registar_auditoria(case when coalesce(p_pronto, true) then 'pedido_pronto' else 'pedido_pronto_anulado' end,
                             'pedidos', p_pedido, '{}'::jsonb);
  -- Avisa o estafeta reservado (enquanto a reserva está activa) para vir buscar
  if coalesce(p_pronto, true) and v_ped.atribuido_a is not null
     and v_ped.atribuido_em > now() - make_interval(mins => v_reserva) then
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    values (v_ped.atribuido_a, 'N32', jsonb_build_object(
              'titulo', 'Pedido pronto ✅',
              'corpo', 'O pedido #' || upper(left(p_pedido::text, 6)) || ' está pronto. Podes vir buscar.',
              'pedido_id', p_pedido));
  end if;
end $$;
revoke execute on function marcar_pedido_pronto(uuid, boolean) from public, anon;
grant  execute on function marcar_pedido_pronto(uuid, boolean) to authenticated;

-- pedidos_operador: acrescenta pronto_em no fim (acrescentado à definição actual, sem a copiar)
do $$
declare
  v_def  text := pg_get_functiondef('pedidos_operador()'::regprocedure);
  v_novo text;
begin
  if position('pronto_em' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := replace(v_def, 'minha boolean)', 'minha boolean, pronto_em timestamp with time zone)');
  v_novo := regexp_replace(v_novo, '(x\.entregador_id\s*=\s*v_me\)\s*,\s*false\))(\s+from\s+pedidos\s+x)', E'\\1,\n         x.pronto_em\\2');
  if v_novo = v_def or position('x.pronto_em' in v_novo) = 0 or position('pronto_em timestamp' in v_novo) = 0 then
    raise exception 'pedidos_operador não tem o formato esperado';
  end if;
  drop function pedidos_operador();
  execute v_novo;
  revoke execute on function pedidos_operador() from public, anon;
  grant  execute on function pedidos_operador() to authenticated, service_role;
end $$;

-- -----------------------------------------------------------------------------
-- Relatório: "Preparar" e "Esperar o estafeta" separados quando há "Pronto"
-- -----------------------------------------------------------------------------
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
    select p.id, p.criado_em, p.entregue_em, p.hora_prometida, p.agendado_para, p.entregador_id, p.pronto_em,
           coalesce(p.confirmado_em, hora_estado_auditoria(p.id, 'confirmado'))    as conf,
           coalesce(p.preparado_em,  hora_estado_auditoria(p.id, 'em_preparacao')) as prep,
           coalesce(p.saiu_em,       hora_estado_auditoria(p.id, 'em_entrega'))    as saiu
      from pedidos p
     where p.cozinha_id = p_cozinha and p.deletado_em is null
       and p.estado = 'entregue_pago' and p.entregue_em is not null
       and p.criado_em >= v_ini and p.criado_em < v_fim
  ),
  -- Durações em minutos; uma etapa só conta se as duas horas existirem e estiverem por ordem.
  -- Com "Pronto": preparar = em preparação → pronto; esperar = pronto → saiu.
  -- Sem "Pronto": preparar = em preparação → saiu (inclui a espera); esperar fica vazio.
  d as (
    select b.*,
           case when b.conf >= b.criado_em then extract(epoch from b.conf - b.criado_em) / 60 end as m_confirmar,
           case when b.prep >= b.conf      then extract(epoch from b.prep - b.conf) / 60      end as m_comecar,
           case when coalesce(b.pronto_em, b.saiu) >= b.prep
                then extract(epoch from coalesce(b.pronto_em, b.saiu) - b.prep) / 60 end as m_preparar,
           case when b.pronto_em is not null and b.saiu >= b.pronto_em
                then extract(epoch from b.saiu - b.pronto_em) / 60 end as m_esperar,
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
        (3, 'preparar',  'Preparar', i.m_preparar),
        (4, 'esperar',   'Esperar o estafeta', i.m_esperar),
        (5, 'entregar',  'Entrega (caminho)', i.m_entregar),
        (6, 'total',     'Total: pedido → entregue', i.m_total)) as e(ordem, chave, nome, m)
     group by e.ordem, e.chave, e.nome
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
    'pedidos', (select count(*) from imed),
    'agendados_fora', (select count(*) from d where agendado_para is not null),
    'com_pronto', (select count(*) from imed where pronto_em is not null),
    'etapas', coalesce((select jsonb_agg(jsonb_build_object('chave', chave, 'nome', nome, 'n', n,
                                                            'mediana', mediana, 'p90', p90) order by ordem)
                          from etapas where n > 0 or chave <> 'esperar'), '[]'),
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
                                                               ('preparar', i.m_preparar), ('esperar', i.m_esperar),
                                                               ('entregar', i.m_entregar)) v(k, m)
                                       where v.m is not null order by v.m desc limit 1)) as x
                     from imed i where i.m_total is not null order by i.m_total desc limit 5) l), '[]')
  ) into r;
  return r;
end $$;
revoke execute on function tempos_etapas_cozinha(uuid, date, date) from public, anon;
grant  execute on function tempos_etapas_cozinha(uuid, date, date) to authenticated;
