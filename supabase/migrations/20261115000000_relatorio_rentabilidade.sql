-- =============================================================================
-- Relatório da cozinha — Fase 3: rentabilidade (custo dos pratos, margem, despesas)
-- e doses (esgotados e sobras). Ver docs/plano-relatorio-cozinha.md.
-- -----------------------------------------------------------------------------
-- Ainda não há fichas técnicas nem preços de ingredientes na produção, por isso o custo
-- é SIMPLES: "quanto custa fazer uma dose" de cada prato e de cada opção dos montáveis,
-- escrito pela cozinha. Fica numa tabela à parte (custos_cardapio) que os clientes nunca
-- lêem (o cardápio é público). O relatório usa os custos actuais (estimativa).
-- Despesas (gás, renda, salários...) passam a poder ser de uma cozinha (custos.cozinha_id).
-- Doses: o sistema só sabia as de HOJE; passa a guardar o dia de cada prato com doses
-- (lançadas, vendidas, sobras e a hora a que esgotou) às 23:55 de Luanda.
-- =============================================================================

-- ---------------------------------------------------------------- 1. Custo dos pratos
create table if not exists custos_cardapio (
  item_id       uuid primary key,              -- cardapio.id (prato) ou opcoes.id (opção)
  tipo          text not null check (tipo in ('prato', 'opcao')),
  cozinha_id    uuid not null references cozinhas(id),
  custo         int not null check (custo between 0 and 1000000),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references funcionarios(id)
);
create index if not exists custos_cardapio_cozinha_idx on custos_cardapio (cozinha_id);
create index if not exists custos_cardapio_func_idx on custos_cardapio (atualizado_por);
alter table custos_cardapio enable row level security;
-- Sem políticas: só pelas funções abaixo (nunca chega à app do cliente)
comment on table custos_cardapio is 'Custo estimado de uma dose de cada prato/opção (só equipa; nunca para clientes)';

create or replace function pode_gerir_custos(p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select pode_na_cozinha('cardapio.gerir', p_cozinha) or pode_na_cozinha('cozinhas.gerir', p_cozinha)
      or tem_permissao('financas.gerir');
$$;
revoke execute on function pode_gerir_custos(uuid) from public, anon, authenticated;

-- Pratos e opções da cozinha com o preço e o custo (para o ecrã "Custos e margens")
create or replace function custos_da_cozinha(p_cozinha uuid)
returns table (item_id uuid, tipo text, prato_id uuid, nome text, grupo text, preco int, custo int, disponivel boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (pode_gerir_custos(p_cozinha) or pode_ver_relatorio(p_cozinha)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
  select c.id, 'prato'::text, c.id, trim(c.nome), null::text, c.preco::int, cc.custo, c.disponivel
    from cardapio c left join custos_cardapio cc on cc.item_id = c.id
   where c.cozinha_id = p_cozinha and c.deletado_em is null
  union all
  select o.id, 'opcao', c.id, trim(o.nome), g.nome, o.preco_extra::int, cc.custo, o.disponivel
    from opcoes o
    join opcoes_grupos g on g.id = o.grupo_id and g.deletado_em is null
    join cardapio c on c.id = g.cardapio_id and c.deletado_em is null
    left join custos_cardapio cc on cc.item_id = o.id
   where c.cozinha_id = p_cozinha and o.deletado_em is null
   order by 3, 2 desc, 5 nulls first, 4;
end $$;
revoke execute on function custos_da_cozinha(uuid) from public, anon;
grant  execute on function custos_da_cozinha(uuid) to authenticated;

-- Grava (ou apaga, com null) o custo de uma dose de um prato ou opção
create or replace function definir_custo_item(p_item uuid, p_custo int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tipo text;
  v_cozinha uuid;
begin
  select 'prato', c.cozinha_id into v_tipo, v_cozinha from cardapio c where c.id = p_item and c.deletado_em is null;
  if v_tipo is null then
    select 'opcao', c.cozinha_id into v_tipo, v_cozinha
      from opcoes o join opcoes_grupos g on g.id = o.grupo_id join cardapio c on c.id = g.cardapio_id
     where o.id = p_item and o.deletado_em is null;
  end if;
  if v_tipo is null then
    raise exception 'item_inexistente' using errcode = 'P0001';
  end if;
  if not pode_gerir_custos(v_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_custo is null then
    delete from custos_cardapio where item_id = p_item;
  else
    if p_custo < 0 or p_custo > 1000000 then
      raise exception 'parametro_invalido' using errcode = 'P0001';
    end if;
    insert into custos_cardapio (item_id, tipo, cozinha_id, custo, atualizado_por)
    values (p_item, v_tipo, v_cozinha, p_custo, funcionario_actual())
    on conflict (item_id) do update
      set custo = excluded.custo, atualizado_em = now(), atualizado_por = excluded.atualizado_por;
  end if;
  perform registar_auditoria('custo_prato', 'cardapio', p_item, jsonb_build_object('tipo', v_tipo, 'custo', p_custo));
end $$;
revoke execute on function definir_custo_item(uuid, int) from public, anon;
grant  execute on function definir_custo_item(uuid, int) to authenticated;

-- ---------------------------------------------------------------- 2. Despesas por cozinha
alter table custos add column if not exists cozinha_id uuid references cozinhas(id);
create index if not exists custos_cozinha_data_idx on custos (cozinha_id, data);

create or replace function despesas_cozinha(p_cozinha uuid, p_inicio date, p_fim date)
returns table (id uuid, data date, categoria text, descricao text, valor int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('financas.gerir') or pode_ver_relatorio(p_cozinha) or pode_gerir_custos(p_cozinha)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
  select d.id, d.data, d.categoria, d.descricao, round(d.valor)::int
    from custos d
   where d.cozinha_id = p_cozinha and d.deletado_em is null and d.data between p_inicio and p_fim
   order by d.data desc, d.criado_em desc;
end $$;
revoke execute on function despesas_cozinha(uuid, date, date) from public, anon;
grant  execute on function despesas_cozinha(uuid, date, date) to authenticated;

create or replace function lancar_despesa(p_cozinha uuid, p_data date, p_categoria text, p_descricao text, p_valor int)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not (tem_permissao('financas.gerir') or pode_gerir_custos(p_cozinha)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_valor is null or p_valor <= 0 or p_valor > 100000000 or p_data is null
     or p_data > (now() at time zone 'Africa/Luanda')::date + 1
     or coalesce(trim(p_categoria), '') = '' or length(p_categoria) > 40
     or length(coalesce(p_descricao, '')) > 200 then
    raise exception 'parametro_invalido' using errcode = 'P0001';
  end if;
  if not exists (select 1 from cozinhas where id = p_cozinha and deletado_em is null) then
    raise exception 'cozinha_inexistente' using errcode = 'P0001';
  end if;
  insert into custos (dispositivo_id, cozinha_id, data, categoria, descricao, valor)
  values ('servidor', p_cozinha, p_data, trim(p_categoria), nullif(trim(p_descricao), ''), p_valor)
  returning id into v;
  perform registar_auditoria('despesa_lancada', 'custos', v,
                             jsonb_build_object('cozinha', p_cozinha, 'valor', p_valor, 'categoria', p_categoria));
  return v;
end $$;
revoke execute on function lancar_despesa(uuid, date, text, text, int) from public, anon;
grant  execute on function lancar_despesa(uuid, date, text, text, int) to authenticated;

create or replace function apagar_despesa(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_cozinha uuid;
begin
  select cozinha_id into v_cozinha from custos where id = p_id and deletado_em is null;
  if not found then raise exception 'despesa_inexistente' using errcode = 'P0001'; end if;
  if not (tem_permissao('financas.gerir') or (v_cozinha is not null and pode_gerir_custos(v_cozinha))) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  update custos set deletado_em = now(), atualizado_em = now() where id = p_id;
  perform registar_auditoria('despesa_apagada', 'custos', p_id, '{}'::jsonb);
end $$;
revoke execute on function apagar_despesa(uuid) from public, anon;
grant  execute on function apagar_despesa(uuid) to authenticated;

-- ---------------------------------------------------------------- 3. Histórico das doses
create table if not exists doses_historico (
  id          uuid primary key default gen_random_uuid(),
  cozinha_id  uuid not null references cozinhas(id),
  cardapio_id uuid not null references cardapio(id),
  dia         date not null,
  lancadas    int not null,
  vendidas    int not null,
  sobras      int not null,
  esgotou_em  timestamptz,
  unique (cardapio_id, dia)
);
create index if not exists doses_historico_cozinha_dia_idx on doses_historico (cozinha_id, dia);
alter table doses_historico enable row level security;
comment on table doses_historico is 'Doses de cada prato por dia (lançadas, vendidas, sobras, hora a que esgotou)';

-- Guarda o dia de hoje (Luanda) de cada prato com doses. Corre às 23:55; pode repetir-se.
create or replace function registar_doses_dia() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_dia date := (now() at time zone 'Africa/Luanda')::date;
  n int := 0;
  c record;
  v_vendidas int;
  v_esgotou timestamptz;
begin
  for c in
    select id, cozinha_id, doses_dia, doses_definidas_em from cardapio
     where deletado_em is null and doses_dia is not null and doses_dia > 0 and doses_definidas_em is not null
       and (doses_definidas_em at time zone 'Africa/Luanda')::date = v_dia
  loop
    -- Pedidos desde que as doses foram lançadas, por ordem: a hora em que o acumulado chegou às doses
    with v as (
      select p.criado_em, coalesce((i ->> 'qtd')::int, 1) as q
        from pedidos p, jsonb_array_elements(p.itens) i
       where p.cozinha_id = c.cozinha_id and p.deletado_em is null and p.estado <> 'cancelado'
         and p.criado_em >= c.doses_definidas_em and i ->> 'cardapio_id' = c.id::text),
    acum as (select criado_em, sum(q) over (order by criado_em) as total from v)
    select coalesce((select sum(q) from v), 0)::int,
           (select min(criado_em) from acum where total >= c.doses_dia)
      into v_vendidas, v_esgotou;
    insert into doses_historico (cozinha_id, cardapio_id, dia, lancadas, vendidas, sobras, esgotou_em)
    values (c.cozinha_id, c.id, v_dia, c.doses_dia, least(v_vendidas, c.doses_dia),
            greatest(c.doses_dia - v_vendidas, 0), v_esgotou)
    on conflict (cardapio_id, dia) do update
      set lancadas = excluded.lancadas, vendidas = excluded.vendidas, sobras = excluded.sobras,
          esgotou_em = excluded.esgotou_em;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function registar_doses_dia() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_doses_dia', '55 22 * * *', 'select public.registar_doses_dia()');
  end if;
end $$;

-- ---------------------------------------------------------------- 4. Relatório: rentabilidade e doses
create or replace function rentabilidade_cozinha(p_cozinha uuid, p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ini  timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim  timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  r      jsonb;
  v_res  jsonb;
begin
  if not pode_ver_relatorio(p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'relatorios.exportar (desta cozinha)';
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 365 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  v_res := resumo_cozinha(p_cozinha, v_ini, v_fim);

  with v as (
    select * from pedidos
     where cozinha_id = p_cozinha and deletado_em is null and estado = 'entregue_pago'
       and entregue_em >= v_ini and entregue_em < v_fim),
  linhas as (
    select i ->> 'cardapio_id' as cardapio_id,
           coalesce((i ->> 'qtd')::int, 1) as qtd,
           coalesce((i ->> 'qtd')::int, 1) * coalesce((i ->> 'preco_unitario')::int, 0) as receita,
           cp.custo as custo_prato,
           (select coalesce(sum(co.custo), 0) from jsonb_array_elements(coalesce(i -> 'opcoes', '[]')) o
              join custos_cardapio co on co.item_id::text = o ->> 'id') as custo_opcoes,
           (select count(*) from jsonb_array_elements(coalesce(i -> 'opcoes', '[]')) o
             where not exists (select 1 from custos_cardapio co where co.item_id::text = o ->> 'id')) as opcoes_sem_custo
      from v, jsonb_array_elements(v.itens) i
      left join custos_cardapio cp on cp.item_id::text = i ->> 'cardapio_id'),
  -- Linha "com custo": o prato tem custo, ou é um montável com todas as opções com custo
  lc as (
    select *, (custo_prato is not null or (custo_opcoes > 0 and opcoes_sem_custo = 0)) as tem_custo,
           qtd * (coalesce(custo_prato, 0) + custo_opcoes) as custo
      from linhas),
  por_prato as (
    select l.cardapio_id, coalesce(trim(c.nome), '—') as nome, sum(l.qtd)::int as qtd, sum(l.receita)::int as receita,
           sum(l.custo) filter (where l.tem_custo)::int as custo, bool_and(l.tem_custo) as completo
      from lc l left join cardapio c on c.id::text = l.cardapio_id group by 1, 2),
  tot as (
    select coalesce(sum(receita), 0)::int as receita,
           coalesce(sum(custo) filter (where tem_custo), 0)::int as cmv,
           coalesce(sum(receita) filter (where tem_custo), 0)::int as receita_com_custo
      from lc),
  desp as (
    select coalesce(sum(valor), 0)::int as total,
           coalesce(jsonb_agg(jsonb_build_object('categoria', categoria, 'valor', s) order by s desc), '[]') as por_categoria
      from (select coalesce(categoria, 'Outros') as categoria, round(sum(valor))::int as s, sum(valor) as valor
              from custos where cozinha_id = p_cozinha and deletado_em is null and data between p_inicio and p_fim
             group by 1) x),
  doses as (
    select h.cardapio_id, coalesce(trim(c.nome), '—') as nome,
           count(*)::int as dias, sum(h.lancadas)::int as lancadas, sum(h.vendidas)::int as vendidas,
           sum(h.sobras)::int as sobras, count(h.esgotou_em)::int as dias_esgotou,
           to_char(make_interval(secs => avg(extract(epoch from (h.esgotou_em at time zone 'Africa/Luanda')::time))), 'HH24:MI') as hora_media_esgotou,
           (sum(h.sobras) * coalesce(max(cc.custo), 0))::int as desperdicio
      from doses_historico h
      left join cardapio c on c.id = h.cardapio_id
      left join custos_cardapio cc on cc.item_id = h.cardapio_id
     where h.cozinha_id = p_cozinha and h.dia between p_inicio and p_fim
     group by 1, 2)
  select jsonb_build_object(
    'vendas_comida', t.receita,
    'cmv', t.cmv,
    -- % das vendas que têm custo definido (o CMV só é fiável perto de 100%)
    'cobertura_pct', case when t.receita > 0 then round(100.0 * t.receita_com_custo / t.receita, 1) end,
    'cmv_pct', case when t.receita_com_custo > 0 then round(100.0 * t.cmv / t.receita_com_custo, 1) end,
    'margem_bruta', case when t.receita_com_custo > 0 then t.receita_com_custo - t.cmv end,
    'despesas', d.total,
    'despesas_por_categoria', d.por_categoria,
    'compras', (select coalesce(round(sum(custo_total)), 0)::int from estoque_diario
                 where cozinha_id = p_cozinha and deletado_em is null and data between p_inicio and p_fim),
    'a_receber_cozinha', (v_res ->> 'a_receber_cozinha')::int,
    -- Resultado aproximado da cozinha: o que recebe − custo dos pratos − despesas (só com custo completo)
    'resultado', case when t.receita > 0 and t.receita_com_custo = t.receita
                      then (v_res ->> 'a_receber_cozinha')::int - t.cmv - d.total end,
    'pratos', coalesce((select jsonb_agg(jsonb_build_object(
                 'nome', nome, 'qtd', qtd, 'receita', receita, 'custo', custo, 'completo', completo,
                 'margem', case when completo then receita - custo end,
                 'margem_pct', case when completo and receita > 0 then round(100.0 * (receita - custo) / receita, 1) end)
               order by receita desc) from por_prato), '[]'),
    'doses', coalesce((select jsonb_agg(jsonb_build_object(
                 'nome', nome, 'dias', dias, 'lancadas', lancadas, 'vendidas', vendidas, 'sobras', sobras,
                 'dias_esgotou', dias_esgotou, 'hora_media_esgotou', hora_media_esgotou, 'desperdicio', desperdicio)
               order by dias_esgotou desc, sobras desc) from doses), '[]')
  ) into r
  from tot t cross join desp d;
  return r;
end $$;
revoke execute on function rentabilidade_cozinha(uuid, date, date) from public, anon;
grant  execute on function rentabilidade_cozinha(uuid, date, date) to authenticated;
