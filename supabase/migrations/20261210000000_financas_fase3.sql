-- =============================================================================
-- Finanças, Fase 3 do plano contabilístico (21/11/2026): custos das entregas e resultados
-- -----------------------------------------------------------------------------
-- Decisões do dono: os estafetas recebem salário e/ou por dia; há também um serviço de entregas
-- contratado. Os valores ainda não estão fechados: ficam TODOS configuráveis no operador
-- (salário mensal, valor por dia, valor por entrega; serviço: por entrega e/ou mensal).
--  * Estafetas: remuneração de cada um; por mês, dias trabalhados (sugeridos pelos dias com
--    entregas, ajustáveis), entregas, valor a pagar e pagamento com referência.
--  * Serviço contratado: fornecedores com o valor por entrega e/ou mensal e as zonas que servem;
--    as entregas dessas zonas contam para eles (e não para os estafetas próprios); pagamento do mês.
--  * Resultados do mês da plataforma: receitas (comissões, taxas de entrega, saldos Convida
--    expirados) − custos (estafetas, serviço contratado, Convida a cargo da plataforma,
--    compensações a cargo da plataforma, despesas gerais sem cozinha).
--  * Obrigações e tesouraria: o que a plataforma deve e tem a receber, num só sítio.
-- Permissão: financas.conferir.
-- =============================================================================

-- ============================================================ Estafetas próprios
create table if not exists estafetas_remuneracao (
  funcionario_id  uuid primary key references funcionarios(id),
  atualizado_em   timestamptz not null default now(),
  salario_mensal  integer not null default 0 check (salario_mensal between 0 and 100000000),
  valor_dia       integer not null default 0 check (valor_dia between 0 and 10000000),
  valor_entrega   integer not null default 0 check (valor_entrega between 0 and 10000000),
  definido_por    uuid references funcionarios(id)
);
create index if not exists estafetas_remuneracao_definido_idx on estafetas_remuneracao (definido_por);

create table if not exists estafetas_mes (
  id               uuid primary key default gen_random_uuid(),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  funcionario_id   uuid not null references funcionarios(id),
  mes              date not null check (extract(day from mes) = 1),
  dias_trabalhados integer check (dias_trabalhados between 0 and 31),  -- null = os sugeridos
  valor_pago       integer check (valor_pago >= 0),
  metodo           text check (metodo is null or metodo in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money')),
  referencia       text check (referencia is null or length(referencia) between 1 and 60),
  pago_em          timestamptz,
  pago_por         uuid references funcionarios(id),
  unique (funcionario_id, mes)
);
create index if not exists estafetas_mes_pago_por_idx on estafetas_mes (pago_por);

-- ============================================================ Serviço de entregas contratado
create table if not exists fornecedores_entrega (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  deletado_em     timestamptz,
  nome            text not null check (length(nome) between 1 and 120),
  valor_entrega   integer not null default 0 check (valor_entrega between 0 and 10000000),
  valor_mensal    integer not null default 0 check (valor_mensal between 0 and 100000000),
  telefone        text check (telefone is null or length(telefone) <= 30),
  nif             text check (nif is null or length(nif) <= 30),
  activo          boolean not null default true
);

alter table zonas add column if not exists fornecedor_entrega_id uuid references fornecedores_entrega(id);
create index if not exists zonas_fornecedor_entrega_idx on zonas (fornecedor_entrega_id);
comment on column zonas.fornecedor_entrega_id is 'Serviço de entregas contratado que serve esta zona (null = estafetas próprios)';

create table if not exists fornecedores_entrega_mes (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  fornecedor_id   uuid not null references fornecedores_entrega(id),
  mes             date not null check (extract(day from mes) = 1),
  entregas        integer not null,
  valor           integer not null check (valor >= 0),
  metodo          text not null check (metodo in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money')),
  referencia      text check (referencia is null or length(referencia) between 1 and 60),
  numero_fatura   text check (numero_fatura is null or length(numero_fatura) between 1 and 60),
  pago_em         timestamptz not null default now(),
  pago_por        uuid references funcionarios(id),
  unique (fornecedor_id, mes)
);
create index if not exists fornecedores_entrega_mes_pago_por_idx on fornecedores_entrega_mes (pago_por);

alter table estafetas_remuneracao enable row level security;
alter table estafetas_mes enable row level security;
alter table fornecedores_entrega enable row level security;
alter table fornecedores_entrega_mes enable row level security;
revoke all on estafetas_remuneracao, estafetas_mes, fornecedores_entrega, fornecedores_entrega_mes from anon, authenticated;

-- Intervalo [início, fim) de um mês no dia de Luanda
create or replace function mes_inicio(p_mes date) returns date
language sql immutable set search_path = public as $$ select date_trunc('month', p_mes)::date $$;

-- Pedido entregue por um serviço contratado (pela zona da morada)
create or replace function fornecedor_do_pedido(p_pedido uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select z.fornecedor_entrega_id
    from pedidos p
    left join pontos_entrega pe on pe.id = p.ponto_entrega_id
    left join zonas z on z.id = coalesce(pe.zona_id, p.zona_id)
   where p.id = p_pedido;
$$;
revoke execute on function fornecedor_do_pedido(uuid) from public, anon, authenticated;

-- Folha dos estafetas próprios de um mês (sem verificação de permissão: uso interno)
create or replace function folha_estafetas(p_mes date)
returns table(funcionario_id uuid, nome text, salario_mensal integer, valor_dia integer, valor_entrega integer,
              dias_sugeridos integer, dias_trabalhados integer, dias_ajustados boolean, entregas integer,
              a_pagar integer, valor_pago integer, metodo text, referencia text, pago_em timestamptz)
language sql stable security definer set search_path = public as $$
  with m as (select mes_inicio(p_mes) as ini, (mes_inicio(p_mes) + interval '1 month')::date as fim),
  ent as (
    select p.entregador_id as f, (p.entregue_em at time zone 'Africa/Luanda')::date as dia
      from pedidos p, m
     where p.deletado_em is null and p.estado = 'entregue_pago' and p.entregador_id is not null
       and (p.entregue_em at time zone 'Africa/Luanda')::date >= m.ini
       and (p.entregue_em at time zone 'Africa/Luanda')::date < m.fim
       and fornecedor_do_pedido(p.id) is null),
  est as (
    select f.id, f.nome, f.criado_em from funcionarios f
      left join direcoes d on d.id = f.direcao_id and d.deletado_em is null
     where f.deletado_em is null and tem_permissao_de(f.id, 'entregas.registar')
       and (not coalesce(f.administrador_principal, false)
            or coalesce((f.permissoes_extra ->> 'entregas.registar')::boolean, false)
            or coalesce((d.permissoes ->> 'entregas.registar')::boolean, false))
    union
    select distinct f.id, f.nome, f.criado_em from funcionarios f join ent on ent.f = f.id),
  -- O salário só conta a partir do mês em que o estafeta entrou na equipa
  est_sal as (
    select e.*, case when (e.criado_em at time zone 'Africa/Luanda')::date < (select fim from m)
                     then coalesce(r.salario_mensal, 0) else 0 end as salario
      from est e left join estafetas_remuneracao r on r.funcionario_id = e.id)
  select e.id, e.nome,
         e.salario, coalesce(r.valor_dia, 0), coalesce(r.valor_entrega, 0),
         (select count(distinct dia)::int from ent where ent.f = e.id),
         coalesce(em.dias_trabalhados, (select count(distinct dia)::int from ent where ent.f = e.id)),
         em.dias_trabalhados is not null,
         (select count(*)::int from ent where ent.f = e.id),
         coalesce(em.valor_pago,
                  e.salario
                  + coalesce(r.valor_dia, 0) * coalesce(em.dias_trabalhados, (select count(distinct dia)::int from ent where ent.f = e.id))
                  + coalesce(r.valor_entrega, 0) * (select count(*)::int from ent where ent.f = e.id)),
         em.valor_pago, em.metodo, em.referencia, em.pago_em
    from est_sal e
    left join estafetas_remuneracao r on r.funcionario_id = e.id
    left join estafetas_mes em on em.funcionario_id = e.id and em.mes = mes_inicio(p_mes);
$$;
revoke execute on function folha_estafetas(date) from public, anon, authenticated;

create or replace function estafetas_pagamentos(p_mes date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(coalesce(p_mes, (now() at time zone 'Africa/Luanda')::date));
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return jsonb_build_object(
    'mes', v_mes,
    'pode_pagar', (v_mes + interval '1 month')::date <= (now() at time zone 'Africa/Luanda')::date + 5,
    'estafetas', coalesce((select jsonb_agg(to_jsonb(f) order by f.nome) from folha_estafetas(v_mes) f), '[]'::jsonb));
end $$;
revoke execute on function estafetas_pagamentos(date) from public, anon;
grant execute on function estafetas_pagamentos(date) to authenticated;

create or replace function definir_remuneracao_estafeta(p_funcionario uuid, p_salario_mensal integer,
                                                        p_valor_dia integer, p_valor_entrega integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if not exists (select 1 from funcionarios where id = p_funcionario and deletado_em is null) then
    raise exception 'funcionario_inexistente' using errcode = 'P0001';
  end if;
  if coalesce(p_salario_mensal, 0) < 0 or coalesce(p_valor_dia, 0) < 0 or coalesce(p_valor_entrega, 0) < 0 then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  insert into estafetas_remuneracao (funcionario_id, salario_mensal, valor_dia, valor_entrega, definido_por)
  values (p_funcionario, coalesce(p_salario_mensal, 0), coalesce(p_valor_dia, 0), coalesce(p_valor_entrega, 0), funcionario_actual())
  on conflict (funcionario_id) do update
    set salario_mensal = excluded.salario_mensal, valor_dia = excluded.valor_dia, valor_entrega = excluded.valor_entrega,
        definido_por = excluded.definido_por, atualizado_em = now();
  perform registar_auditoria('estafeta_remuneracao', 'funcionarios', p_funcionario,
    jsonb_build_object('salario_mensal', p_salario_mensal, 'valor_dia', p_valor_dia, 'valor_entrega', p_valor_entrega));
end $$;
revoke execute on function definir_remuneracao_estafeta(uuid, integer, integer, integer) from public, anon;
grant execute on function definir_remuneracao_estafeta(uuid, integer, integer, integer) to authenticated;

/** Ajusta os dias trabalhados de um mês (null volta aos sugeridos). Só antes de pagar. */
create or replace function definir_dias_estafeta(p_funcionario uuid, p_mes date, p_dias integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(p_mes);
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if p_dias is not null and p_dias not between 0 and 31 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if exists (select 1 from estafetas_mes where funcionario_id = p_funcionario and mes = v_mes and pago_em is not null) then
    raise exception 'mes_ja_pago' using errcode = 'P0001';
  end if;
  insert into estafetas_mes (funcionario_id, mes, dias_trabalhados) values (p_funcionario, v_mes, p_dias)
  on conflict (funcionario_id, mes) do update set dias_trabalhados = excluded.dias_trabalhados, atualizado_em = now();
  perform registar_auditoria('estafeta_dias', 'funcionarios', p_funcionario, jsonb_build_object('mes', v_mes, 'dias', p_dias));
end $$;
revoke execute on function definir_dias_estafeta(uuid, date, integer) from public, anon;
grant execute on function definir_dias_estafeta(uuid, date, integer) to authenticated;

/** Paga o mês de um estafeta: o valor é o calculado no servidor (salário + dias + entregas) */
create or replace function pagar_estafeta_mes(p_funcionario uuid, p_mes date, p_metodo text, p_referencia text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(p_mes);
  v int;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if (v_mes + interval '1 month')::date > (now() at time zone 'Africa/Luanda')::date + 5 then
    raise exception 'mes_em_curso' using errcode = 'P0001';
  end if;
  if p_metodo is null or p_metodo not in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if p_metodo <> 'Dinheiro' and length(coalesce(btrim(p_referencia), '')) < 4 then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  if exists (select 1 from estafetas_mes where funcionario_id = p_funcionario and mes = v_mes and pago_em is not null) then
    raise exception 'mes_ja_pago' using errcode = 'P0001';
  end if;
  select a_pagar into v from folha_estafetas(v_mes) where funcionario_id = p_funcionario;
  if v is null or v <= 0 then raise exception 'sem_valor' using errcode = 'P0001'; end if;
  insert into estafetas_mes (funcionario_id, mes, valor_pago, metodo, referencia, pago_em, pago_por)
  values (p_funcionario, v_mes, v, p_metodo, nullif(btrim(p_referencia), ''), now(), funcionario_actual())
  on conflict (funcionario_id, mes) do update
    set valor_pago = excluded.valor_pago, metodo = excluded.metodo, referencia = excluded.referencia,
        pago_em = excluded.pago_em, pago_por = excluded.pago_por, atualizado_em = now();
  perform registar_auditoria('estafeta_pago', 'funcionarios', p_funcionario,
                             jsonb_build_object('mes', v_mes, 'valor', v, 'metodo', p_metodo, 'referencia', p_referencia));
  return v;
end $$;
revoke execute on function pagar_estafeta_mes(uuid, date, text, text) from public, anon;
grant execute on function pagar_estafeta_mes(uuid, date, text, text) to authenticated;

-- ============================================================ Serviço contratado: contas
create or replace function conta_fornecedores_entrega(p_mes date)
returns table(fornecedor_id uuid, nome text, valor_entrega integer, valor_mensal integer, activo boolean,
              zonas jsonb, entregas integer, a_pagar integer, pago boolean, valor_pago integer,
              metodo text, referencia text, numero_fatura text, pago_em timestamptz)
language sql stable security definer set search_path = public as $$
  with m as (select mes_inicio(p_mes) as ini, (mes_inicio(p_mes) + interval '1 month')::date as fim),
  ent as (
    select fornecedor_do_pedido(p.id) as forn
      from pedidos p, m
     where p.deletado_em is null and p.estado = 'entregue_pago'
       and (p.entregue_em at time zone 'Africa/Luanda')::date >= m.ini
       and (p.entregue_em at time zone 'Africa/Luanda')::date < m.fim)
  select f.id, f.nome, f.valor_entrega, f.valor_mensal, f.activo,
         coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'nome', btrim(z.nome)) order by z.nome)
                     from zonas z where z.fornecedor_entrega_id = f.id and z.deletado_em is null), '[]'::jsonb),
         coalesce(pm.entregas, (select count(*)::int from ent where ent.forn = f.id)),
         coalesce(pm.valor, f.valor_mensal + f.valor_entrega * (select count(*)::int from ent where ent.forn = f.id)),
         pm.id is not null, pm.valor, pm.metodo, pm.referencia, pm.numero_fatura, pm.pago_em
    from fornecedores_entrega f
    left join fornecedores_entrega_mes pm on pm.fornecedor_id = f.id and pm.mes = mes_inicio(p_mes)
   where f.deletado_em is null and (f.activo or pm.id is not null);
$$;
revoke execute on function conta_fornecedores_entrega(date) from public, anon, authenticated;

create or replace function fornecedores_entrega_lista(p_mes date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(coalesce(p_mes, (now() at time zone 'Africa/Luanda')::date));
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return jsonb_build_object(
    'mes', v_mes,
    'pode_pagar', (v_mes + interval '1 month')::date <= (now() at time zone 'Africa/Luanda')::date + 5,
    'fornecedores', coalesce((select jsonb_agg(to_jsonb(c) order by c.nome) from conta_fornecedores_entrega(v_mes) c), '[]'::jsonb),
    'zonas', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'nome', btrim(z.nome), 'fornecedor_id', z.fornecedor_entrega_id)
                                        order by z.nome)
                         from zonas z where z.deletado_em is null), '[]'::jsonb));
end $$;
revoke execute on function fornecedores_entrega_lista(date) from public, anon;
grant execute on function fornecedores_entrega_lista(date) to authenticated;

/** Cria (p_id null) ou altera um serviço de entregas contratado e as zonas que serve */
create or replace function guardar_fornecedor_entrega(p_id uuid, p_nome text, p_valor_entrega integer, p_valor_mensal integer,
                                                      p_zonas uuid[], p_activo boolean default true,
                                                      p_telefone text default null, p_nif text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := p_id;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if length(coalesce(btrim(p_nome), '')) not between 1 and 120 then raise exception 'nome_invalido' using errcode = 'P0001'; end if;
  if coalesce(p_valor_entrega, 0) < 0 or coalesce(p_valor_mensal, 0) < 0 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if v_id is null then
    insert into fornecedores_entrega (nome, valor_entrega, valor_mensal, activo, telefone, nif)
    values (btrim(p_nome), coalesce(p_valor_entrega, 0), coalesce(p_valor_mensal, 0), coalesce(p_activo, true),
            nullif(btrim(p_telefone), ''), nullif(btrim(p_nif), ''))
    returning id into v_id;
  else
    update fornecedores_entrega
       set nome = btrim(p_nome), valor_entrega = coalesce(p_valor_entrega, 0), valor_mensal = coalesce(p_valor_mensal, 0),
           activo = coalesce(p_activo, true), telefone = nullif(btrim(p_telefone), ''), nif = nullif(btrim(p_nif), ''),
           atualizado_em = now()
     where id = v_id and deletado_em is null;
    if not found then raise exception 'fornecedor_inexistente' using errcode = 'P0001'; end if;
  end if;
  -- Zonas: as indicadas passam a ser deste serviço; as que eram dele e já não estão, voltam aos estafetas próprios
  update zonas set fornecedor_entrega_id = null where fornecedor_entrega_id = v_id and not (id = any(coalesce(p_zonas, '{}')));
  update zonas set fornecedor_entrega_id = v_id where id = any(coalesce(p_zonas, '{}')) and deletado_em is null;
  perform registar_auditoria('fornecedor_entrega', 'fornecedores_entrega', v_id,
    jsonb_build_object('valor_entrega', p_valor_entrega, 'valor_mensal', p_valor_mensal, 'zonas', p_zonas));
  return v_id;
end $$;
revoke execute on function guardar_fornecedor_entrega(uuid, text, integer, integer, uuid[], boolean, text, text) from public, anon;
grant execute on function guardar_fornecedor_entrega(uuid, text, integer, integer, uuid[], boolean, text, text) to authenticated;

create or replace function pagar_fornecedor_entrega(p_fornecedor uuid, p_mes date, p_metodo text,
                                                    p_referencia text default null, p_numero_fatura text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(p_mes);
  c record;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if (v_mes + interval '1 month')::date > (now() at time zone 'Africa/Luanda')::date + 5 then
    raise exception 'mes_em_curso' using errcode = 'P0001';
  end if;
  if p_metodo is null or p_metodo not in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if p_metodo <> 'Dinheiro' and length(coalesce(btrim(p_referencia), '')) < 4 then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  select * into c from conta_fornecedores_entrega(v_mes) where fornecedor_id = p_fornecedor;
  if not found then raise exception 'fornecedor_inexistente' using errcode = 'P0001'; end if;
  if c.pago then raise exception 'mes_ja_pago' using errcode = 'P0001'; end if;
  if c.a_pagar <= 0 then raise exception 'sem_valor' using errcode = 'P0001'; end if;
  insert into fornecedores_entrega_mes (fornecedor_id, mes, entregas, valor, metodo, referencia, numero_fatura, pago_por)
  values (p_fornecedor, v_mes, c.entregas, c.a_pagar, p_metodo, nullif(btrim(p_referencia), ''),
          nullif(upper(btrim(p_numero_fatura)), ''), funcionario_actual());
  perform registar_auditoria('fornecedor_entrega_pago', 'fornecedores_entrega', p_fornecedor,
    jsonb_build_object('mes', v_mes, 'valor', c.a_pagar, 'entregas', c.entregas, 'metodo', p_metodo, 'referencia', p_referencia));
  return c.a_pagar;
end $$;
revoke execute on function pagar_fornecedor_entrega(uuid, date, text, text, text) from public, anon;
grant execute on function pagar_fornecedor_entrega(uuid, date, text, text, text) to authenticated;

-- ============================================================ Resultados do mês da plataforma
create or replace function resultados_mes(p_mes date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_mes date := mes_inicio(coalesce(p_mes, (now() at time zone 'Africa/Luanda')::date));
  v_fim date := (mes_inicio(coalesce(p_mes, (now() at time zone 'Africa/Luanda')::date)) + interval '1 month')::date;
  v_ini_ts timestamptz;
  v_fim_ts timestamptz;
  r jsonb; c jsonb;
  v_rec int; v_cus int;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  v_ini_ts := v_mes::timestamp at time zone 'Africa/Luanda';
  v_fim_ts := v_fim::timestamp at time zone 'Africa/Luanda';
  with v as (
    select acerto_valores_pedido(p, 1) as x from pedidos p
     where p.deletado_em is null and p.estado = 'entregue_pago' and p.entregue_em >= v_ini_ts and p.entregue_em < v_fim_ts)
  select jsonb_build_object(
           'pedidos', count(*),
           'vendas_cozinhas', coalesce(sum((x ->> 'vendas')::int), 0),
           'comissoes', coalesce(sum((x ->> 'comissao')::int), 0),
           'taxas_entrega', coalesce(sum((x ->> 'taxas_entrega')::int), 0),
           'convida_descontos', coalesce(sum((x ->> 'convida_plataforma')::int), 0))
    into r from v;
  r := r || jsonb_build_object(
    'saldos_expirados', (select coalesce(sum(valor), 0)::int from expiracoes_saldo
                          where deletado_em is null and criado_em >= v_ini_ts and criado_em < v_fim_ts));
  c := jsonb_build_object(
    'estafetas', (select coalesce(sum(a_pagar), 0)::int from folha_estafetas(v_mes)),
    'servico_entregas', (select coalesce(sum(a_pagar), 0)::int from conta_fornecedores_entrega(v_mes)),
    'convida_descontos', (r ->> 'convida_descontos')::int,
    'convida_ganhos', (select coalesce(sum(valor), 0)::int from ganhos_indicacao
                        where deletado_em is null and estado in ('confirmado', 'pago')
                          and confirmado_em >= v_ini_ts and confirmado_em < v_fim_ts),
    'compensacoes', (select coalesce(sum(valor), 0)::int from compensacoes
                      where estado = 'paga' and a_cargo = 'plataforma' and pago_em >= v_ini_ts and pago_em < v_fim_ts),
    'despesas_gerais', (select coalesce(sum(valor), 0)::int from custos
                         where deletado_em is null and cozinha_id is null and data >= v_mes and data < v_fim));
  v_rec := (r ->> 'comissoes')::int + (r ->> 'taxas_entrega')::int + (r ->> 'saldos_expirados')::int;
  v_cus := (c ->> 'estafetas')::int + (c ->> 'servico_entregas')::int + (c ->> 'convida_descontos')::int
           + (c ->> 'convida_ganhos')::int + (c ->> 'compensacoes')::int + (c ->> 'despesas_gerais')::int;
  return jsonb_build_object(
    'mes', v_mes, 'fechado', v_fim <= (now() at time zone 'Africa/Luanda')::date,
    'pedidos', (r ->> 'pedidos')::int, 'vendas_cozinhas', (r ->> 'vendas_cozinhas')::int,
    'receitas', jsonb_build_object('comissoes', (r ->> 'comissoes')::int, 'taxas_entrega', (r ->> 'taxas_entrega')::int,
                                   'saldos_expirados', (r ->> 'saldos_expirados')::int, 'total', v_rec),
    'custos', c || jsonb_build_object('total', v_cus),
    'resultado', v_rec - v_cus,
    'custo_por_entrega', case when (r ->> 'pedidos')::int > 0
                              then round(((c ->> 'estafetas')::int + (c ->> 'servico_entregas')::int)::numeric / (r ->> 'pedidos')::int)::int end);
end $$;
revoke execute on function resultados_mes(date) from public, anon;
grant execute on function resultados_mes(date) to authenticated;

-- ============================================================ Obrigações e tesouraria
create or replace function obrigacoes_resumo() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoje date := (now() at time zone 'Africa/Luanda')::date;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return jsonb_build_object(
    'a_pagar', jsonb_build_object(
      'saldos_convida', (select coalesce(sum(greatest(saldo_disponivel, 0)), 0)::int from saldo_indicacao),
      'levantamentos_pedidos', (select coalesce(sum(valor), 0)::int from pagamentos_indicacao
                                 where deletado_em is null and estado in ('pedido', 'aprovado')),
      'pacotes_por_consumir', (select coalesce(sum(greatest(refeicoes + refeicoes_oferta - refeicoes_usadas, 0) * valor_refeicao), 0)::int
                                 from adesoes_pacote where deletado_em is null and estado = 'activa'),
      'acertos_cozinhas', (select coalesce(sum(greatest(abs(a.saldo) - coalesce(pg.v, 0), 0)), 0)::int
                             from acertos_cozinha a
                             left join lateral (select sum(valor) as v from acertos_pagamentos p
                                                 where p.acerto_id = a.id and p.deletado_em is null) pg on true
                            where a.deletado_em is null and a.estado = 'fechado' and a.saldo < 0),
      'compensacoes', (select coalesce(sum(valor), 0)::int from compensacoes where estado = 'por_pagar'),
      'estafetas_meses_anteriores', (select coalesce(sum(f.a_pagar), 0)::int
                                       from generate_series(date_trunc('month', v_hoje) - interval '3 months',
                                                            date_trunc('month', v_hoje) - interval '1 month', interval '1 month') g(m),
                                            lateral folha_estafetas(g.m::date) f
                                      where f.pago_em is null),
      'servico_entregas_meses_anteriores', (select coalesce(sum(c.a_pagar), 0)::int
                                              from generate_series(date_trunc('month', v_hoje) - interval '3 months',
                                                                   date_trunc('month', v_hoje) - interval '1 month', interval '1 month') g(m),
                                                   lateral conta_fornecedores_entrega(g.m::date) c
                                             where not c.pago)),
    'a_receber', jsonb_build_object(
      'acertos_cozinhas', (select coalesce(sum(greatest(a.saldo - coalesce(pg.v, 0), 0)), 0)::int
                             from acertos_cozinha a
                             left join lateral (select sum(valor) as v from acertos_pagamentos p
                                                 where p.acerto_id = a.id and p.deletado_em is null) pg on true
                            where a.deletado_em is null and a.estado = 'fechado' and a.saldo > 0),
      'empresas', (select coalesce(sum(valor), 0)::int from faturas_empresa where estado = 'emitida'),
      'empresas_em_atraso', (select coalesce(sum(valor), 0)::int from faturas_empresa where estado = 'emitida' and vencimento < v_hoje)),
    'por_fechar', jsonb_build_object(
      'semanas_acertos', (select count(*)::int from cozinhas k
                           where k.deletado_em is null
                             and not exists (select 1 from acertos_cozinha a where a.cozinha_id = k.id
                                              and a.semana_inicio = semana_de(v_hoje) - 7 and a.deletado_em is null)
                             and exists (select 1 from acerto_movimentos(k.id, semana_de(v_hoje) - 7))),
      'vendas_sem_fatura', (select count(*)::int from pedidos p
                             where p.deletado_em is null and p.estado = 'entregue_pago'
                               and p.entregue_em >= now() - interval '30 days'
                               and not exists (select 1 from faturas_pedidos f where f.pedido_id = p.id))));
end $$;
revoke execute on function obrigacoes_resumo() from public, anon;
grant execute on function obrigacoes_resumo() to authenticated;
