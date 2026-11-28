-- Agente de stock e compras (Claude com ferramentas). Todos os dias (e quando o responsável do stock pede na app)
-- prepara, para cada cozinha, um plano de compras: o que comprar, quanto (na unidade de compra), com que urgência,
-- o custo estimado e o fornecedor mais em conta das últimas compras; e alertas (validades a chegar, saídas de
-- stock sem explicação nas distribuições, preços a subir, produtos sem dados). O Claude só lê: saldos (calculados
-- dos movimentos, sempre na unidade base), consumo, preços, compras do dia, reconciliação e procura. Não há dados
-- de clientes. Nada é escrito no stock: o responsável marca cada compra como feita ou ignorada; as entradas
-- continuam a ser registadas na app como hoje. Aviso N28 quando há compras para hoje ou alertas graves.
-- Interruptor: funcionalidade agente_compras (desligada até ser testada).

insert into funcionalidades (chave, activa, dispositivo_id) values ('agente_compras', false, 'servidor')
on conflict (chave) do nothing;

alter table parametros
  add column compras_pedidos_dia integer not null default 5 check (compras_pedidos_dia between 1 and 50);
comment on column parametros.compras_pedidos_dia is 'Planos de compras pedidos na app por cozinha e por dia (controla o custo)';

create table planos_compras (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cozinha_id       uuid not null references cozinhas(id),
  dia              date not null default (now() at time zone 'Africa/Luanda')::date,
  origem           text not null default 'automatico' check (origem in ('automatico', 'pedido')),
  pedido_por       uuid references funcionarios(id),
  estado           text not null default 'pendente'
                     check (estado in ('pendente', 'a_preparar', 'pronto', 'indisponivel')),
  ia_tentativas    integer not null default 0,
  ia_nota          text,
  resumo           text,
  compras          jsonb not null default '[]',
  alertas          jsonb not null default '[]',
  passos           jsonb not null default '[]',
  pronto_em        timestamptz
);
create unique index planos_compras_automatico_key on planos_compras (cozinha_id, dia) where origem = 'automatico' and deletado_em is null;
create index planos_compras_cozinha_idx on planos_compras (cozinha_id, criado_em);
create index planos_compras_pendente_idx on planos_compras (criado_em) where estado = 'pendente';
create index planos_compras_pedido_por_idx on planos_compras (pedido_por);
create trigger trg_0_so_servidor before insert or update or delete on planos_compras
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on planos_compras
for each row execute function sync_receber();
alter table planos_compras enable row level security;
revoke all on planos_compras from anon;
revoke insert, update, delete, truncate on planos_compras from authenticated;
grant select on planos_compras to authenticated;
create policy ler on planos_compras for select to authenticated
  using (deletado_em is null and pode_na_cozinha('stock.gerir', cozinha_id));
comment on table planos_compras is 'Sincronização: só servidor (planos de compras do agente). Telemóvel só lê.';

-- Quem trata do stock de uma cozinha (para o N28)
create or replace function responsaveis_stock(p_cozinha uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select f from funcionarios_com_permissao('stock.gerir') f
   where (select administrador_principal from funcionarios where id = f)
      or tem_permissao_de(f, 'cozinhas.gerir')
      or exists (select 1 from turnos t where t.funcionario_id = f and t.cozinha_id = p_cozinha and t.deletado_em is null);
$$;
revoke execute on function responsaveis_stock(uuid) from public, anon, authenticated;

-- Unidade base e factor da unidade de compra de um produto
create or replace function unidade_base_de(p_categoria text) returns text
language sql immutable set search_path = public as $$
  select case p_categoria when 'Peso' then 'g' when 'Volume' then 'ml' when 'Unidade' then 'un' end;
$$;

-- ---------------------------------------------------------------- ferramentas (só leitura, só o serviço)
-- Saldos dos produtos de longo prazo da cozinha, consumo, cobertura, última compra e validades ainda em stock
create or replace function stk_saldos(p_cozinha uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with mov as (
    select e.produto_id, e.tipo, coalesce(e.quantidade, 0) q, e.data, e.custo_total, e.fornecedor, e.validade
      from estoque_longo_prazo e
     where e.cozinha_id = p_cozinha and e.deletado_em is null and e.produto_id is not null),
  por_produto as (
    select p.id, p.nome, p.categoria, p.categoria_medida, p.unidade_compra, p.custo,
           coalesce(nullif(quantidade_unidade_base(1, p.unidade_compra, p.categoria_medida), 0), 1) fator,
           coalesce(sum(case when m.tipo = 'Entrada' then m.q else -m.q end), 0) saldo,
           coalesce(sum(m.q) filter (where m.tipo = 'Consumo' and m.data > now() - interval '28 days'), 0) consumo_28d,
           coalesce(sum(m.q) filter (where m.tipo = 'Consumo' and m.data > now() - interval '7 days'), 0) consumo_7d,
           greatest(1, least(28, extract(day from now() - min(m.data))::int + 1)) dias_base
      from produtos p join mov m on m.produto_id = p.id
     where p.deletado_em is null
     group by p.id),
  entradas as (   -- FIFO aproximado: as entradas mais recentes são as que ainda estão em stock
    select m.produto_id, m.data, m.q, m.validade,
           sum(m.q) over (partition by m.produto_id order by m.data desc, m.validade desc nulls last
                          rows between unbounded preceding and current row) acumulado
      from mov m where m.tipo = 'Entrada')
  select coalesce(jsonb_agg(jsonb_build_object(
           'produto_id', pp.id, 'nome', pp.nome, 'categoria', pp.categoria,
           'unidade_base', unidade_base_de(pp.categoria_medida),
           'unidade_compra', pp.unidade_compra, 'unidade_compra_em_base', pp.fator,
           'custo_tabela_por_unidade_compra', pp.custo,
           'saldo', round(pp.saldo, 1),
           'consumo_7d', round(pp.consumo_7d, 1), 'consumo_28d', round(pp.consumo_28d, 1),
           'consumo_medio_dia', round(pp.consumo_28d / pp.dias_base, 1),
           'dias_de_cobertura', case when pp.consumo_28d > 0 then round(pp.saldo / (pp.consumo_28d / pp.dias_base), 1) end,
           'ultima_compra', (select jsonb_build_object('data', (m.data at time zone 'Africa/Luanda')::date, 'quantidade', m.q,
                                                       'custo_total', m.custo_total, 'fornecedor', m.fornecedor)
                               from mov m where m.produto_id = pp.id and m.tipo = 'Entrada' order by m.data desc limit 1),
           'validades_em_stock', (select coalesce(jsonb_agg(jsonb_build_object(
                                     'validade', e.validade,
                                     'quantidade_ainda_em_stock', round(least(e.q, pp.saldo - (e.acumulado - e.q)), 1))
                                     order by e.validade), '[]')
                                    from entradas e
                                   where e.produto_id = pp.id and e.validade is not null
                                     and e.acumulado - e.q < pp.saldo
                                     and e.validade <= (now() at time zone 'Africa/Luanda')::date + 14))
           order by case when pp.consumo_28d > 0 then pp.saldo / (pp.consumo_28d / pp.dias_base) end nulls last), '[]')
    from por_produto pp;
$$;

-- Consumo dia a dia de um produto na cozinha (para ver tendência e dias da semana)
create or replace function stk_consumo_diario(p_cozinha uuid, p_produto uuid, p_dias int default 28) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'produto', (select nome from produtos where id = p_produto),
    'unidade_base', (select unidade_base_de(categoria_medida) from produtos where id = p_produto),
    'dias', coalesce((select jsonb_agg(jsonb_build_object('dia', d.dia, 'dia_semana', trim(to_char(d.dia, 'TMDay')),
                                                          'consumo', coalesce(c.q, 0), 'entradas', coalesce(c.e, 0)) order by d.dia)
                        from generate_series((now() at time zone 'Africa/Luanda')::date - least(greatest(coalesce(p_dias, 28), 1), 90) + 1,
                                             (now() at time zone 'Africa/Luanda')::date, interval '1 day') d(dia)
                        left join (select (data at time zone 'Africa/Luanda')::date dia,
                                          sum(quantidade) filter (where tipo = 'Consumo') q,
                                          sum(quantidade) filter (where tipo = 'Entrada') e
                                     from estoque_longo_prazo
                                    where cozinha_id = p_cozinha and produto_id = p_produto and deletado_em is null
                                    group by 1) c on c.dia = d.dia::date), '[]'));
$$;

-- Histórico de preços de compra de um produto (todas as cozinhas, para comparar fornecedores)
create or replace function stk_precos(p_produto uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (select *, coalesce(nullif(quantidade_unidade_base(1, unidade_compra, categoria_medida), 0), 1) fator
               from produtos where id = p_produto)
  select jsonb_build_object(
    'produto', p.nome, 'unidade_compra', p.unidade_compra, 'custo_tabela', p.custo,
    'compras', coalesce((select jsonb_agg(jsonb_build_object(
                  'data', (e.data at time zone 'Africa/Luanda')::date, 'cozinha', trim(c.nome),
                  'fornecedor', coalesce(nullif(trim(e.fornecedor), ''), 'sem fornecedor'),
                  'quantidade_unidade_compra', round(e.quantidade / p.fator, 2), 'custo_total', e.custo_total,
                  'preco_por_unidade_compra', case when e.quantidade > 0 and e.custo_total is not null
                                                   then round(e.custo_total / (e.quantidade / p.fator), 2) end)
                  order by e.data desc)
                  from estoque_longo_prazo e join cozinhas c on c.id = e.cozinha_id
                 where e.produto_id = p.id and e.tipo = 'Entrada' and e.deletado_em is null
                   and e.data > now() - interval '120 days'), '[]'))
    from p;
$$;

-- Compras do dia (produtos Diário) e pratos vendidos em cada dia
create or replace function stk_compras_diarias(p_cozinha uuid, p_dias int default 14) returns jsonb
language sql stable security definer set search_path = public as $$
  with d as (select (now() at time zone 'Africa/Luanda')::date - least(greatest(coalesce(p_dias, 14), 1), 60) + 1 ini)
  select jsonb_build_object(
    'compras', coalesce((select jsonb_agg(jsonb_build_object('dia', e.data, 'produto', trim(e.produto),
                                                            'quantidade', e.qtd_comprada, 'custo_total', e.custo_total)
                                          order by e.data, e.produto)
                           from estoque_diario e, d
                          where e.cozinha_id = p_cozinha and e.deletado_em is null and e.data >= d.ini), '[]'),
    'pratos_vendidos_por_dia', coalesce((select jsonb_agg(jsonb_build_object('dia', x.dia, 'pratos', x.n) order by x.dia)
                                           from (select (v.data at time zone 'Africa/Luanda')::date dia, sum(coalesce(v.qtd, 0)) n
                                                   from vendas v, d
                                                  where v.cozinha_id = p_cozinha and v.deletado_em is null and v.movimenta_stock
                                                    and (v.data at time zone 'Africa/Luanda')::date >= d.ini
                                                  group by 1) x), '[]'));
$$;

-- Reconciliação das distribuições: enviado − devolvido − quebra − consumido = diferença não explicada
create or replace function stk_reconciliacao(p_cozinha uuid, p_dias int default 14) returns jsonb
language sql stable security definer set search_path = public as $$
  with env as (
    select d.produto_id, (d.criado_em at time zone 'Africa/Luanda')::date dia,
           sum(coalesce(quantidade_unidade_base(d.quantidade, d.unidade, p.categoria_medida), d.quantidade)) enviado,
           sum(coalesce(quantidade_unidade_base(d.quantidade_devolvida, d.unidade, p.categoria_medida), d.quantidade_devolvida)) devolvido,
           sum(coalesce(quantidade_unidade_base(d.quantidade_quebra, d.unidade, p.categoria_medida), d.quantidade_quebra)) quebra
      from distribuicoes d join produtos p on p.id = d.produto_id
     where d.cozinha_id = p_cozinha and d.deletado_em is null
       and d.criado_em > now() - make_interval(days => least(greatest(coalesce(p_dias, 14), 1), 60))
     group by 1, 2),
  cons as (
    select produto_id, (data at time zone 'Africa/Luanda')::date dia, sum(quantidade) consumido
      from estoque_longo_prazo
     where cozinha_id = p_cozinha and tipo = 'Consumo' and deletado_em is null
       and data > now() - make_interval(days => least(greatest(coalesce(p_dias, 14), 1), 60) + 1)
     group by 1, 2)
  select coalesce(jsonb_agg(jsonb_build_object(
           'dia', env.dia, 'produto_id', env.produto_id, 'produto', p.nome, 'unidade_base', unidade_base_de(p.categoria_medida),
           'enviado', round(env.enviado, 1), 'devolvido', round(env.devolvido, 1), 'quebra', round(env.quebra, 1),
           'consumido_nas_vendas', round(coalesce(cons.consumido, 0), 1),
           'diferenca_nao_explicada', round(env.enviado - env.devolvido - env.quebra - coalesce(cons.consumido, 0), 1))
           order by env.dia desc, p.nome), '[]')
    from env join produtos p on p.id = env.produto_id
    left join cons on cons.produto_id = env.produto_id and cons.dia = env.dia;
$$;

-- Procura: pratos vendidos por dia da semana (4 semanas), encomendas marcadas e receitas dos pratos disponíveis
create or replace function stk_procura(p_cozinha uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pratos_por_dia_da_semana', coalesce((select jsonb_agg(jsonb_build_object('dia_semana', x.ds, 'media_pratos', x.m) order by x.n)
        from (select extract(isodow from dia)::int n, trim(to_char(dia, 'TMDay')) ds, round(avg(t), 1) m
                from (select (v.data at time zone 'Africa/Luanda')::date dia, sum(coalesce(v.qtd, 0)) t
                        from vendas v
                       where v.cozinha_id = p_cozinha and v.deletado_em is null and v.movimenta_stock
                         and v.data > now() - interval '28 days'
                       group by 1) y
               group by 1, 2) x), '[]'),
    'encomendas_marcadas', coalesce((select jsonb_agg(jsonb_build_object('quando', to_char(e.hora_prevista at time zone 'Africa/Luanda', 'YYYY-MM-DD HH24:MI'),
                                                                        'produto', e.produto, 'qtd', e.qtd) order by e.hora_prevista)
        from pre_encomendas e
       where e.cozinha_id = p_cozinha and e.deletado_em is null
         and e.hora_prevista between now() and now() + interval '7 days'
         and coalesce(e.status, '') !~* '^(cancel|entreg)'), '[]'),
    'receitas_dos_pratos_disponiveis', coalesce((select jsonb_agg(jsonb_build_object(
          'prato', c.nome, 'do_dia', c.do_dia,
          'vendidos_28d', (select coalesce(sum(v.qtd), 0) from vendas v where v.prato_base_id = c.prato_base_id and v.cozinha_id = p_cozinha
                             and v.deletado_em is null and v.movimenta_stock and v.data > now() - interval '28 days'),
          'por_porcao', (select coalesce(jsonb_agg(jsonb_build_object('produto_id', pr.id, 'produto', pr.nome,
                                    'quantidade_base', quantidade_unidade_base((k ->> 'quantidade')::numeric, k ->> 'unidade', pr.categoria_medida),
                                    'tipo_estoque', pr.tipo_estoque)), '[]')
                           from pratos_base pb, jsonb_array_elements(pb.componentes) k
                           join produtos pr on pr.id::text = k ->> 'produto_id'
                          where pb.id = c.prato_base_id))
          order by c.ordem)
        from cardapio c where c.cozinha_id = p_cozinha and c.disponivel and c.deletado_em is null and c.prato_base_id is not null), '[]'));
$$;

-- ---------------------------------------------------------------- pedidos e jobs
-- Cria o plano de uma cozinha (pendente) se ainda não houver um por preparar
create or replace function criar_plano_compras(p_cozinha uuid, p_origem text, p_por uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  select id into v_id from planos_compras
   where cozinha_id = p_cozinha and estado in ('pendente', 'a_preparar') and deletado_em is null limit 1;
  if v_id is not null then return v_id; end if;
  insert into planos_compras (dispositivo_id, sincronizado_em, cozinha_id, origem, pedido_por)
  values ('servidor', now(), p_cozinha, p_origem, p_por)
  on conflict do nothing
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function criar_plano_compras(uuid, text, uuid) from public, anon, authenticated;

-- Pela app: o responsável do stock pede um plano agora
create or replace function pedir_plano_compras(p_cozinha uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cozinha uuid := coalesce(p_cozinha, cozinha_padrao());
begin
  if not coalesce(pode_na_cozinha('stock.gerir', v_cozinha), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if not funcionalidade_activa('agente_compras') then
    raise exception 'funcionalidade_inactiva' using errcode = 'P0001';
  end if;
  if (select count(*) from planos_compras where cozinha_id = v_cozinha and origem = 'pedido' and deletado_em is null
        and dia = (now() at time zone 'Africa/Luanda')::date)
     >= (select compras_pedidos_dia from parametros where unico) then
    raise exception 'limite_diario' using errcode = 'P0001';
  end if;
  return criar_plano_compras(v_cozinha, 'pedido', funcionario_actual());
end $$;
revoke execute on function pedir_plano_compras(uuid) from public, anon;
grant execute on function pedir_plano_compras(uuid) to authenticated;

-- Todos os dias: um plano por cozinha com movimentos de stock nas últimas 4 semanas
create or replace function job_planos_compras() returns int
language plpgsql security definer set search_path = public as $$
declare
  n int := 0;
  c uuid;
begin
  if not funcionalidade_activa('agente_compras') then return 0; end if;
  for c in select z.id from cozinhas z where z.deletado_em is null
             and (exists (select 1 from estoque_longo_prazo e where e.cozinha_id = z.id and e.deletado_em is null
                           and e.data > now() - interval '28 days')
                  or exists (select 1 from estoque_diario e where e.cozinha_id = z.id and e.deletado_em is null
                              and e.data > (now() at time zone 'Africa/Luanda')::date - 28)) loop
    if criar_plano_compras(c, 'automatico') is not null then n := n + 1; end if;
  end loop;
  return n;
end $$;
revoke execute on function job_planos_compras() from public, anon, authenticated;

create or replace function planos_compras_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('stock.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'cozinha_id', p.cozinha_id, 'cozinha', trim(c.nome), 'dia', p.dia, 'origem', p.origem,
             'pedido_por', f.nome, 'estado', p.estado, 'resumo', p.resumo, 'compras', p.compras, 'alertas', p.alertas,
             'criado_em', p.criado_em, 'pronto_em', p.pronto_em)
           order by p.criado_em desc)
      from planos_compras p join cozinhas c on c.id = p.cozinha_id
      left join funcionarios f on f.id = p.pedido_por
     where p.deletado_em is null and pode_na_cozinha('stock.gerir', p.cozinha_id)
       and p.criado_em > now() - interval '14 days'), '[]');
end $$;
revoke execute on function planos_compras_lista() from public, anon;
grant execute on function planos_compras_lista() to authenticated;

-- Pela app: marca uma compra do plano como feita ou ignorada (ou volta a pendente)
create or replace function marcar_compra(p_plano uuid, p_indice int, p_estado text) returns text
language plpgsql security definer set search_path = public as $$
declare
  p planos_compras;
begin
  select * into p from planos_compras where id = p_plano and deletado_em is null for update;
  if not found then raise exception 'plano_inexistente' using errcode = 'P0001'; end if;
  if not coalesce(pode_na_cozinha('stock.gerir', p.cozinha_id), false) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_estado not in ('pendente', 'comprado', 'ignorado') or p_indice is null or p_indice < 0
     or p_indice >= jsonb_array_length(p.compras) then
    raise exception 'dados_invalidos' using errcode = 'P0001';
  end if;
  update planos_compras
     set compras = jsonb_set(compras, array[p_indice::text],
                             (compras -> p_indice) || jsonb_build_object(
                               'estado', p_estado,
                               'decidido_por', case when p_estado = 'pendente' then null else (select nome from funcionarios where id = funcionario_actual()) end,
                               'decidido_em', case when p_estado = 'pendente' then null else now() end)),
         atualizado_em = now()
   where id = p.id;
  perform registar_auditoria('compra_' || p_estado, 'planos_compras', p.id,
                             jsonb_build_object('indice', p_indice, 'produto', p.compras -> p_indice ->> 'produto'));
  return p_estado;
end $$;
revoke execute on function marcar_compra(uuid, int, text) from public, anon;
grant execute on function marcar_compra(uuid, int, text) to authenticated;

-- ---------------------------------------------------------------- Edge Function compras
create or replace function reservar_plano_compras(p_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  q planos_compras;
begin
  if not funcionalidade_activa('agente_compras') then return null; end if;
  select * into q from planos_compras
   where deletado_em is null and (p_id is null or id = p_id)
     and (estado = 'pendente' or (estado = 'a_preparar' and atualizado_em < now() - interval '5 minutes'))
   order by criado_em limit 1 for update skip locked;
  if not found then return null; end if;
  update planos_compras set estado = 'a_preparar', atualizado_em = now() where id = q.id;
  return jsonb_build_object('id', q.id, 'cozinha_id', q.cozinha_id,
                            'cozinha', (select trim(nome) from cozinhas where id = q.cozinha_id),
                            'hoje', (now() at time zone 'Africa/Luanda')::date,
                            'dia_da_semana', trim(to_char(now() at time zone 'Africa/Luanda', 'TMDay')),
                            'saldos', stk_saldos(q.cozinha_id), 'procura', stk_procura(q.cozinha_id));
end $$;

-- Guarda o plano (valida cada compra e alerta) e avisa (N28) quando há compras para hoje ou alertas graves
create or replace function registar_plano_compras(p_id uuid, p_resultado text, p_plano jsonb default null,
                                                  p_passos jsonb default '[]', p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  q planos_compras;
  v_estado text;
  v_compras jsonb;
  v_alertas jsonb;
  v_hoje int;
  v_graves int;
begin
  select * into q from planos_compras where id = p_id for update;
  if not found then raise exception 'plano_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    update planos_compras
       set ia_tentativas = ia_tentativas + 1,
           estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'pendente' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = q.id returning estado into v_estado;
    return v_estado;
  end if;
  if p_resultado = 'indisponivel' then
    update planos_compras set estado = 'indisponivel', ia_nota = left(p_nota, 300), atualizado_em = now() where id = q.id;
    return 'indisponivel';
  end if;
  if p_resultado <> 'pronto' or nullif(trim(p_plano ->> 'resumo'), '') is null then
    raise exception 'resultado_invalido' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'produto_id', pr.id, 'produto', coalesce(pr.nome, left(trim(x ->> 'produto_nome'), 80)),
           'quantidade', round((x ->> 'quantidade')::numeric, 2),
           'unidade', coalesce(nullif(trim(x ->> 'unidade'), ''), pr.unidade_compra, unidade_base_de(pr.categoria_medida)),
           'urgencia', x ->> 'urgencia',
           'custo_estimado', case when (x ->> 'custo_estimado') ~ '^\d+(\.\d+)?$' then round((x ->> 'custo_estimado')::numeric) end,
           'fornecedor', left(nullif(trim(x ->> 'fornecedor'), ''), 80),
           'motivo', left(trim(x ->> 'motivo'), 300),
           'estado', 'pendente')
           order by case x ->> 'urgencia' when 'hoje' then 0 when 'esta_semana' then 1 else 2 end), '[]')
    into v_compras
    from (select x from jsonb_array_elements(coalesce(p_plano -> 'compras', '[]')) x limit 40) s
    left join produtos pr on pr.id::text = x ->> 'produto_id' and pr.deletado_em is null
   where (x ->> 'quantidade') ~ '^\d+(\.\d+)?$' and (x ->> 'quantidade')::numeric > 0
     and x ->> 'urgencia' in ('hoje', 'esta_semana', 'proxima_semana')
     and nullif(trim(x ->> 'motivo'), '') is not null
     and (pr.id is not null or (x ->> 'produto_id' is null and nullif(trim(x ->> 'produto_nome'), '') is not null));

  select coalesce(jsonb_agg(jsonb_build_object(
           'tipo', x ->> 'tipo', 'gravidade', x ->> 'gravidade', 'produto_id', pr.id, 'produto', pr.nome,
           'texto', left(trim(x ->> 'texto'), 400))
           order by case x ->> 'gravidade' when 'alta' then 0 when 'media' then 1 else 2 end), '[]')
    into v_alertas
    from (select x from jsonb_array_elements(coalesce(p_plano -> 'alertas', '[]')) x limit 15) s
    left join produtos pr on pr.id::text = x ->> 'produto_id' and pr.deletado_em is null
   where x ->> 'tipo' in ('validade', 'desvio', 'preco', 'ruptura', 'dados', 'outro')
     and x ->> 'gravidade' in ('alta', 'media', 'baixa')
     and nullif(trim(x ->> 'texto'), '') is not null;

  update planos_compras
     set estado = 'pronto', resumo = left(p_plano ->> 'resumo', 2000), compras = v_compras, alertas = v_alertas,
         passos = coalesce(p_passos, '[]'), ia_nota = left(p_nota, 300), pronto_em = now(), atualizado_em = now()
   where id = q.id;

  v_hoje := (select count(*) from jsonb_array_elements(v_compras) c where c ->> 'urgencia' = 'hoje');
  v_graves := (select count(*) from jsonb_array_elements(v_alertas) a where a ->> 'gravidade' = 'alta');
  if v_hoje > 0 or v_graves > 0 then
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N28', jsonb_build_object('plano_id', q.id, 'cozinha', (select trim(nome) from cozinhas where id = q.cozinha_id),
                                        'compras_hoje', v_hoje, 'alertas_graves', v_graves)
      from responsaveis_stock(q.cozinha_id) f;
  end if;
  return 'pronto';
end $$;

create or replace function agendar_compras(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('compras', '*/5 * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 150000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

do $$
declare f text;
begin
  foreach f in array array['stk_saldos(uuid)', 'stk_consumo_diario(uuid, uuid, int)', 'stk_precos(uuid)',
                           'stk_compras_diarias(uuid, int)', 'stk_reconciliacao(uuid, int)', 'stk_procura(uuid)',
                           'reservar_plano_compras(uuid)', 'registar_plano_compras(uuid, text, jsonb, jsonb, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
revoke execute on function agendar_compras(text) from public, anon, authenticated;
