-- =============================================================================
-- O que se compra em cada zona
-- -----------------------------------------------------------------------------
-- "Zona" = a zona onde o cliente RECEBE o pedido (do ponto de entrega), não onde fica a cozinha.
--  1. Relatório de cada cozinha: para cada zona, os pratos que mais saem (quantidade, valor e
--     variação face ao período anterior) e, nos montáveis, as opções mais escolhidas.
--  2. Visão do administrador: o que se compra em cada zona somando todas as cozinhas, com a
--     cozinha que mais vende cada prato, e os pratos a crescer.
--  3. App do cliente: "o mais pedido na tua zona" (últimos 30 dias), só com contagens agregadas
--     e só a partir de parametros.limiar_pediram pedidos (não revela pedidos de ninguém).
-- =============================================================================

-- Linhas de pratos vendidos (entregues e pagos) num intervalo, com a zona de entrega.
-- Interna: só a usam as funções abaixo, que fazem as verificações de permissão.
create or replace function linhas_vendidas_zona(p_cozinha uuid, p_ini timestamptz, p_fim timestamptz)
returns table (pedido_id uuid, cozinha_id uuid, zona_id uuid, zona text, cardapio_id text, prato text,
               qtd int, receita int, opcoes jsonb)
language sql stable security definer set search_path = public as $$
  select v.id, v.cozinha_id, z.id, coalesce(z.nome, 'Sem zona'),
         i ->> 'cardapio_id',
         coalesce((select trim(cd.nome) from cardapio cd where cd.id::text = i ->> 'cardapio_id'),
                  regexp_replace(i ->> 'nome', ' \([^()]*\)$', '')),
         coalesce((i ->> 'qtd')::int, 1),
         coalesce((i ->> 'qtd')::int, 1) * coalesce((i ->> 'preco_unitario')::int, 0),
         i -> 'opcoes'
    from pedidos v
    left join pontos_entrega pe on pe.id = v.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, v.zona_id)
    cross join lateral jsonb_array_elements(coalesce(v.itens, '[]')) i
   where v.deletado_em is null and v.estado = 'entregue_pago'
     and v.entregue_em >= p_ini and v.entregue_em < p_fim
     and (p_cozinha is null or v.cozinha_id = p_cozinha);
$$;
revoke execute on function linhas_vendidas_zona(uuid, timestamptz, timestamptz) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 1. Por zona, no relatório de UMA cozinha
-- -----------------------------------------------------------------------------
create or replace function pratos_por_zona_cozinha(p_cozinha uuid, p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ini  timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim  timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  v_dias int := p_fim - p_inicio + 1;
  r      jsonb;
begin
  if not pode_ver_relatorio(p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'relatorios.exportar (desta cozinha)';
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio or v_dias > 366 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  with l as (select * from linhas_vendidas_zona(p_cozinha, v_ini, v_fim)),
  ant as (select * from linhas_vendidas_zona(p_cozinha, v_ini - make_interval(days => v_dias), v_ini)),
  zonas_v as (
    select zona, count(distinct pedido_id)::int as pedidos, sum(receita)::int as vendas from l group by zona
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'zona', zv.zona,
    'pedidos', zv.pedidos,
    'vendas', zv.vendas,
    'pratos', coalesce((
      select jsonb_agg(jsonb_build_object('nome', p.prato, 'qtd', p.q, 'receita', p.rc, 'qtd_anterior', p.qa) order by p.q desc, p.rc desc)
        from (select l2.prato, sum(l2.qtd)::int as q, sum(l2.receita)::int as rc,
                     coalesce((select sum(a.qtd)::int from ant a where a.zona = zv.zona and a.prato = l2.prato), 0) as qa
                from l l2 where l2.zona = zv.zona group by l2.prato
               order by sum(l2.qtd) desc, sum(l2.receita) desc limit 5) p), '[]'),
    'opcoes', coalesce((
      select jsonb_agg(jsonb_build_object('nome', o.nome, 'qtd', o.q) order by o.q desc, o.nome)
        from (select op ->> 'nome' as nome, sum(l3.qtd)::int as q
                from l l3, jsonb_array_elements(coalesce(l3.opcoes, '[]')) op
               where l3.zona = zv.zona group by 1 order by 2 desc, 1 limit 5) o), '[]')
  ) order by zv.vendas desc), '[]')
  into r
  from zonas_v zv;
  return r;
end $$;
revoke execute on function pratos_por_zona_cozinha(uuid, date, date) from public, anon;
grant  execute on function pratos_por_zona_cozinha(uuid, date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Visão do administrador: o que se compra em cada zona (todas as cozinhas)
-- -----------------------------------------------------------------------------
create or replace function vendas_por_zona(p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ini  timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim  timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  v_dias int := p_fim - p_inicio + 1;
  r      jsonb;
begin
  if not (tem_permissao('relatorios.exportar')
          and (coalesce((select administrador_principal from funcionarios where id = funcionario_actual()), false)
               or tem_permissao('cozinhas.gerir'))) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'relatorios.exportar + cozinhas.gerir';
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio or v_dias > 366 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  with l as (select l.*, k.nome as cozinha from linhas_vendidas_zona(null, v_ini, v_fim) l join cozinhas k on k.id = l.cozinha_id),
  ant as (select * from linhas_vendidas_zona(null, v_ini - make_interval(days => v_dias), v_ini)),
  zonas_v as (
    select zona, count(distinct pedido_id)::int as pedidos, sum(receita)::int as vendas,
           count(distinct cozinha_id)::int as cozinhas from l group by zona
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
    'zonas', coalesce(jsonb_agg(jsonb_build_object(
      'zona', zv.zona, 'pedidos', zv.pedidos, 'vendas', zv.vendas, 'cozinhas', zv.cozinhas,
      'pratos', coalesce((
        select jsonb_agg(jsonb_build_object('nome', p.prato, 'qtd', p.q, 'receita', p.rc, 'qtd_anterior', p.qa,
                                            'cozinha_top', p.ctop) order by p.q desc, p.rc desc)
          from (select l2.prato, sum(l2.qtd)::int as q, sum(l2.receita)::int as rc,
                       coalesce((select sum(a.qtd)::int from ant a where a.zona = zv.zona and a.prato = l2.prato), 0) as qa,
                       (select l4.cozinha from l l4 where l4.zona = zv.zona and l4.prato = l2.prato
                         group by l4.cozinha order by sum(l4.qtd) desc limit 1) as ctop
                  from l l2 where l2.zona = zv.zona group by l2.prato
                 order by sum(l2.qtd) desc, sum(l2.receita) desc limit 10) p), '[]'),
      'opcoes', coalesce((
        select jsonb_agg(jsonb_build_object('nome', o.nome, 'qtd', o.q) order by o.q desc, o.nome)
          from (select op ->> 'nome' as nome, sum(l3.qtd)::int as q
                  from l l3, jsonb_array_elements(coalesce(l3.opcoes, '[]')) op
                 where l3.zona = zv.zona group by 1 order by 2 desc, 1 limit 5) o), '[]'),
      -- A crescer: mais vendidos que no período anterior (pelo menos 3 e +50%)
      'a_crescer', coalesce((
        select jsonb_agg(jsonb_build_object('nome', g.prato, 'qtd', g.q, 'qtd_anterior', g.qa) order by g.q - g.qa desc)
          from (select l5.prato, sum(l5.qtd)::int as q,
                       coalesce((select sum(a.qtd)::int from ant a where a.zona = zv.zona and a.prato = l5.prato), 0) as qa
                  from l l5 where l5.zona = zv.zona group by l5.prato) g
         where g.q >= 3 and g.q >= 1.5 * g.qa and g.q > g.qa), '[]')
    ) order by zv.vendas desc), '[]')
  ) into r
  from zonas_v zv;
  return r;
end $$;
revoke execute on function vendas_por_zona(date, date) from public, anon;
grant  execute on function vendas_por_zona(date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. App do cliente: o mais pedido na zona da morada (últimos 30 dias)
-- -----------------------------------------------------------------------------
-- Só pratos que estão no cardápio e disponíveis; só contagens (nunca quem pediu); e só a partir
-- do mesmo limiar da prova social ("X pessoas pediram este mês").
create or replace function mais_pedidos_na_zona(p_ponto uuid)
returns table (cardapio_id uuid, nome text, cozinha_id uuid, cozinha text, pedidos int)
language plpgsql stable security definer set search_path = public as $$
declare
  v_zona uuid;
  v_min  int := (select limiar_pediram from parametros where unico);
begin
  if cliente_actual() is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  select pe.zona_id into v_zona
    from pontos_entrega pe
    join enderecos_cliente ec on ec.ponto_entrega_id = pe.id and ec.cliente_id = cliente_actual() and ec.deletado_em is null
   where pe.id = p_ponto;
  if v_zona is null then
    return;
  end if;
  return query
  select cd.id, trim(cd.nome), cd.cozinha_id, k.nome, count(distinct l.pedido_id)::int
    from linhas_vendidas_zona(null, now() - interval '30 days', now() + interval '1 minute') l
    join cardapio cd on cd.id::text = l.cardapio_id and cd.disponivel and cd.deletado_em is null
    join cozinhas k on k.id = cd.cozinha_id
   where l.zona_id = v_zona and cozinha_aceita_pedidos(cd.cozinha_id)
   group by cd.id, cd.nome, cd.cozinha_id, k.nome
  having count(distinct l.pedido_id) >= greatest(coalesce(v_min, 1), 1)
   order by count(distinct l.pedido_id) desc, cd.nome
   limit 3;
end $$;
revoke execute on function mais_pedidos_na_zona(uuid) from public, anon;
grant  execute on function mais_pedidos_na_zona(uuid) to authenticated;
