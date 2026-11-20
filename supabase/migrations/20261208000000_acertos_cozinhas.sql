-- =============================================================================
-- Acerto semanal com as cozinhas (plano contabilístico, Fase 1 — decisões do dono, 20/11/2026)
-- -----------------------------------------------------------------------------
--  * O dinheiro das entregas fica com a COZINHA. A taxa de entrega é da plataforma (estafetas
--    próprios ou serviço contratado) e a plataforma fica com a comissão da cozinha.
--  * Acerto SEMANAL (segunda a domingo, dia de Luanda), por cozinha:
--      a cozinha deve à plataforma:  taxa de entrega + comissão
--      a plataforma deve à cozinha:  o que a cozinha não recebeu em dinheiro e é a cargo da
--                                    plataforma — desconto do convite e saldo Convida (na parte
--                                    da plataforma), refeições pagas por pacote e a parte da empresa
--      saldo = (deve à plataforma) − (deve à cozinha):  > 0 a cozinha paga; < 0 a plataforma paga
--  * Fechar a semana guarda cada pedido numa linha (não muda mais). Um pedido estornado depois do
--    fecho entra como linha de estorno (valores ao contrário) no acerto seguinte dessa cozinha.
--  * Cada acerto regista os pagamentos (quem pagou, quanto, meio, referência) e o número da fatura
--    emitida no software certificado. Fica «pago» quando os pagamentos cobrem o saldo.
-- Permissão: financas.conferir (o administrador principal tem todas).
-- =============================================================================

create table if not exists acertos_cozinha (
  id              uuid primary key default gen_random_uuid(),
  dispositivo_id  text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  sincronizado_em timestamptz,
  deletado_em     timestamptz,
  cozinha_id      uuid not null references cozinhas(id),
  semana_inicio   date not null check (extract(isodow from semana_inicio) = 1),
  semana_fim      date not null,
  pedidos         integer not null default 0,
  vendas          integer not null default 0,   -- subtotal (comida)
  taxas_entrega   integer not null default 0,
  comissao_percent numeric(5,2) not null default 0,
  comissao        integer not null default 0,
  convida_plataforma integer not null default 0, -- desconto + saldo Convida a cargo da plataforma
  pago_pacote     integer not null default 0,
  valor_empresa   integer not null default 0,
  deve_cozinha    integer not null default 0,   -- a cozinha deve à plataforma
  deve_plataforma integer not null default 0,   -- a plataforma deve à cozinha
  saldo           integer not null default 0,   -- > 0 cozinha paga; < 0 plataforma paga
  estado          text not null default 'fechado' check (estado in ('fechado', 'pago')),
  fechado_por     uuid references funcionarios(id),
  numero_fatura   text check (numero_fatura is null or length(numero_fatura) between 1 and 60),
  nota            text check (nota is null or length(nota) <= 500),
  unique (cozinha_id, semana_inicio)
);
create index if not exists acertos_cozinha_cozinha_idx on acertos_cozinha (cozinha_id, semana_inicio desc);

create table if not exists acertos_linhas (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  acerto_id       uuid not null references acertos_cozinha(id),
  pedido_id       uuid not null references pedidos(id),
  tipo            text not null check (tipo in ('venda', 'estorno')),
  vendas          integer not null,
  taxas_entrega   integer not null,
  comissao        integer not null,
  convida_plataforma integer not null,
  pago_pacote     integer not null,
  valor_empresa   integer not null,
  saldo           integer not null,
  unique (pedido_id, tipo)
);
create index if not exists acertos_linhas_acerto_idx on acertos_linhas (acerto_id);

create table if not exists acertos_pagamentos (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  deletado_em     timestamptz,
  acerto_id       uuid not null references acertos_cozinha(id),
  quem_paga       text not null check (quem_paga in ('cozinha', 'plataforma')),
  valor           integer not null check (valor > 0),
  metodo          text not null check (metodo in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money')),
  referencia      text check (referencia is null or length(referencia) between 1 and 60),
  data            date not null,
  registado_por   uuid references funcionarios(id)
);
create index if not exists acertos_pagamentos_acerto_idx on acertos_pagamentos (acerto_id);
create index if not exists acertos_pagamentos_registado_idx on acertos_pagamentos (registado_por);
create index if not exists acertos_cozinha_fechado_por_idx on acertos_cozinha (fechado_por);

-- Só o servidor escreve; leitura também só pelas funções
alter table acertos_cozinha enable row level security;
alter table acertos_linhas enable row level security;
alter table acertos_pagamentos enable row level security;
revoke all on acertos_cozinha, acertos_linhas, acertos_pagamentos from anon, authenticated;

insert into permissoes (dispositivo_id, chave, grupo, descricao)
select 'servidor', 'financas.conferir', 'Finanças', 'Fecho do dia e do mês, extratos, comprovativos e acertos com as cozinhas'
 where not exists (select 1 from permissoes where chave = 'financas.conferir');
update permissoes set descricao = 'Fecho do dia e do mês, extratos, comprovativos e acertos com as cozinhas'
 where chave = 'financas.conferir';

-- Valores de um pedido para o acerto (sinal +1 venda, −1 estorno)
create or replace function acerto_valores_pedido(p pedidos, p_sinal int) returns jsonb
language sql stable security definer set search_path = public as $$
  with k as (select coalesce(comissao_percent, 0) as pct, coalesce(convida_cozinha_percent, 0) as cv
               from cozinhas where id = p.cozinha_id),
  v as (
    select p.subtotal::int as vendas, p.taxa_entrega::int as taxas,
           round(p.subtotal * k.pct / 100)::int as comissao,
           round((p.desconto_indicacao + p.credito_indicacao_usado) * (100 - k.cv) / 100)::int as convida,
           coalesce(p.pago_pacote, 0)::int as pacote,
           coalesce(p.valor_empresa, 0)::int as empresa
      from k)
  select jsonb_build_object(
    'vendas', p_sinal * vendas, 'taxas_entrega', p_sinal * taxas, 'comissao', p_sinal * comissao,
    'convida_plataforma', p_sinal * convida, 'pago_pacote', p_sinal * pacote, 'valor_empresa', p_sinal * empresa,
    'saldo', p_sinal * ((taxas + comissao) - (convida + pacote + empresa)))
  from v;
$$;
revoke execute on function acerto_valores_pedido(pedidos, int) from public, anon, authenticated;

-- O que entra no acerto de uma cozinha e semana (ainda por fechar): vendas da semana e estornos
-- de pedidos já acertados noutra semana e ainda não devolvidos
create or replace function acerto_movimentos(p_cozinha uuid, p_semana date)
returns table(pedido_id uuid, tipo text, valores jsonb)
language sql stable security definer set search_path = public as $$
  select p.id, 'venda', acerto_valores_pedido(p, 1)
    from pedidos p
   where p.cozinha_id = p_cozinha and p.deletado_em is null and p.estado = 'entregue_pago'
     and (p.entregue_em at time zone 'Africa/Luanda')::date between p_semana and p_semana + 6
     and not exists (select 1 from acertos_linhas l where l.pedido_id = p.id and l.tipo = 'venda')
  union all
  select p.id, 'estorno', acerto_valores_pedido(p, -1)
    from pedidos p
   where p.cozinha_id = p_cozinha and p.deletado_em is null and p.estado = 'estornado'
     and exists (select 1 from acertos_linhas l where l.pedido_id = p.id and l.tipo = 'venda')
     and not exists (select 1 from acertos_linhas l where l.pedido_id = p.id and l.tipo = 'estorno');
$$;
revoke execute on function acerto_movimentos(uuid, date) from public, anon, authenticated;

create or replace function acerto_totais(p_mov jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'pedidos', count(*) filter (where m ->> 'tipo' = 'venda'),
    'vendas', coalesce(sum((m -> 'valores' ->> 'vendas')::int), 0),
    'taxas_entrega', coalesce(sum((m -> 'valores' ->> 'taxas_entrega')::int), 0),
    'comissao', coalesce(sum((m -> 'valores' ->> 'comissao')::int), 0),
    'convida_plataforma', coalesce(sum((m -> 'valores' ->> 'convida_plataforma')::int), 0),
    'pago_pacote', coalesce(sum((m -> 'valores' ->> 'pago_pacote')::int), 0),
    'valor_empresa', coalesce(sum((m -> 'valores' ->> 'valor_empresa')::int), 0),
    'saldo', coalesce(sum((m -> 'valores' ->> 'saldo')::int), 0))
  from jsonb_array_elements(coalesce(p_mov, '[]')) m;
$$;

create or replace function semana_de(p_dia date) returns date
language sql immutable set search_path = public as $$ select p_dia - (extract(isodow from p_dia)::int - 1) $$;

/**
 * Acertos de uma semana: uma linha por cozinha activa com o fechado (se já foi) ou a pré-visualização
 * do que ainda está por fechar, os pagamentos e o que falta pagar.
 */
create or replace function acertos_semana(p_semana date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_sem date := semana_de(coalesce(p_semana, (now() at time zone 'Africa/Luanda')::date));
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return jsonb_build_object(
    'semana_inicio', v_sem, 'semana_fim', v_sem + 6,
    'pode_fechar', v_sem + 6 < (now() at time zone 'Africa/Luanda')::date,
    'cozinhas', coalesce((
      select jsonb_agg(x order by (x ->> 'por_pagar')::int desc, x ->> 'cozinha_nome')
        from (
          select jsonb_build_object(
                   'cozinha_id', k.id, 'cozinha_nome', btrim(k.nome),
                   'acerto_id', a.id, 'estado', coalesce(a.estado, 'aberto'),
                   'numero_fatura', a.numero_fatura,
                   'totais', case when a.id is not null then jsonb_build_object(
                                 'pedidos', a.pedidos, 'vendas', a.vendas, 'taxas_entrega', a.taxas_entrega,
                                 'comissao', a.comissao, 'convida_plataforma', a.convida_plataforma,
                                 'pago_pacote', a.pago_pacote, 'valor_empresa', a.valor_empresa, 'saldo', a.saldo)
                             else acerto_totais((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'valores', m.valores))
                                                   from acerto_movimentos(k.id, v_sem) m)) end,
                   'comissao_percent', coalesce(a.comissao_percent, k.comissao_percent),
                   'pago', coalesce(pg.pago, 0),
                   'por_pagar', case when a.id is null then 0 else greatest(abs(a.saldo) - coalesce(pg.pago, 0), 0) end) as x
            from cozinhas k
            left join acertos_cozinha a on a.cozinha_id = k.id and a.semana_inicio = v_sem and a.deletado_em is null
            left join lateral (select sum(valor)::int as pago from acertos_pagamentos ap
                                where ap.acerto_id = a.id and ap.deletado_em is null) pg on true
           where k.deletado_em is null
             and (a.id is not null or exists (select 1 from acerto_movimentos(k.id, v_sem)))) s), '[]'::jsonb));
end $$;
revoke execute on function acertos_semana(date) from public, anon;
grant execute on function acertos_semana(date) to authenticated;

/** Fecha a semana de uma cozinha (só depois de domingo acabar): guarda as linhas e os totais */
create or replace function fechar_acerto(p_cozinha uuid, p_semana date) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_sem  date := semana_de(p_semana);
  v_id   uuid;
  v_mov  jsonb;
  t      jsonb;
  v_pct  numeric;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if v_sem + 6 >= (now() at time zone 'Africa/Luanda')::date then
    raise exception 'semana_em_curso' using errcode = 'P0001';
  end if;
  select id into v_id from acertos_cozinha where cozinha_id = p_cozinha and semana_inicio = v_sem and deletado_em is null;
  if found then return v_id; end if;  -- já fechada
  perform pg_advisory_xact_lock(hashtext('acerto:' || p_cozinha::text));
  select jsonb_agg(jsonb_build_object('pedido_id', m.pedido_id, 'tipo', m.tipo, 'valores', m.valores))
    into v_mov from acerto_movimentos(p_cozinha, v_sem) m;
  t := acerto_totais(v_mov);
  select comissao_percent into v_pct from cozinhas where id = p_cozinha;
  insert into acertos_cozinha (dispositivo_id, sincronizado_em, cozinha_id, semana_inicio, semana_fim, pedidos, vendas,
                               taxas_entrega, comissao_percent, comissao, convida_plataforma, pago_pacote, valor_empresa,
                               deve_cozinha, deve_plataforma, saldo, estado, fechado_por)
  values ('servidor', now(), p_cozinha, v_sem, v_sem + 6, (t ->> 'pedidos')::int, (t ->> 'vendas')::int,
          (t ->> 'taxas_entrega')::int, coalesce(v_pct, 0), (t ->> 'comissao')::int, (t ->> 'convida_plataforma')::int,
          (t ->> 'pago_pacote')::int, (t ->> 'valor_empresa')::int,
          (t ->> 'taxas_entrega')::int + (t ->> 'comissao')::int,
          (t ->> 'convida_plataforma')::int + (t ->> 'pago_pacote')::int + (t ->> 'valor_empresa')::int,
          (t ->> 'saldo')::int, case when (t ->> 'saldo')::int = 0 then 'pago' else 'fechado' end, funcionario_actual())
  returning id into v_id;
  insert into acertos_linhas (acerto_id, pedido_id, tipo, vendas, taxas_entrega, comissao, convida_plataforma,
                              pago_pacote, valor_empresa, saldo)
  select v_id, (m ->> 'pedido_id')::uuid, m ->> 'tipo', (m -> 'valores' ->> 'vendas')::int,
         (m -> 'valores' ->> 'taxas_entrega')::int, (m -> 'valores' ->> 'comissao')::int,
         (m -> 'valores' ->> 'convida_plataforma')::int, (m -> 'valores' ->> 'pago_pacote')::int,
         (m -> 'valores' ->> 'valor_empresa')::int, (m -> 'valores' ->> 'saldo')::int
    from jsonb_array_elements(coalesce(v_mov, '[]')) m;
  perform registar_auditoria('acerto_fechado', 'acertos_cozinha', v_id, t);
  return v_id;
end $$;
revoke execute on function fechar_acerto(uuid, date) from public, anon;
grant execute on function fechar_acerto(uuid, date) to authenticated;

/** Pagamento de um acerto (quem paga resulta do sinal do saldo); fica «pago» quando cobre o saldo */
create or replace function registar_pagamento_acerto(p_acerto uuid, p_valor integer, p_metodo text,
                                                     p_referencia text default null, p_data date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a      acertos_cozinha;
  v_pago int;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  select * into a from acertos_cozinha where id = p_acerto and deletado_em is null for update;
  if not found then raise exception 'acerto_inexistente' using errcode = 'P0001'; end if;
  if a.estado = 'pago' then raise exception 'acerto_ja_pago' using errcode = 'P0001'; end if;
  select coalesce(sum(valor), 0) into v_pago from acertos_pagamentos where acerto_id = a.id and deletado_em is null;
  if p_valor is null or p_valor <= 0 or p_valor > abs(a.saldo) - v_pago then
    raise exception 'valor_invalido' using errcode = 'P0001', detail = 'falta pagar ' || (abs(a.saldo) - v_pago);
  end if;
  if p_metodo is null or p_metodo not in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if p_metodo <> 'Dinheiro' and length(coalesce(btrim(p_referencia), '')) < 4 then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  insert into acertos_pagamentos (acerto_id, quem_paga, valor, metodo, referencia, data, registado_por)
  values (a.id, case when a.saldo > 0 then 'cozinha' else 'plataforma' end, p_valor, p_metodo,
          nullif(btrim(p_referencia), ''), coalesce(p_data, (now() at time zone 'Africa/Luanda')::date), funcionario_actual());
  v_pago := v_pago + p_valor;
  if v_pago >= abs(a.saldo) then
    update acertos_cozinha set estado = 'pago', atualizado_em = now() where id = a.id;
  end if;
  perform registar_auditoria('acerto_pagamento', 'acertos_cozinha', a.id,
                             jsonb_build_object('valor', p_valor, 'metodo', p_metodo, 'referencia', p_referencia));
  return jsonb_build_object('pago', v_pago, 'falta', greatest(abs(a.saldo) - v_pago, 0),
                            'estado', case when v_pago >= abs(a.saldo) then 'pago' else 'fechado' end);
end $$;
revoke execute on function registar_pagamento_acerto(uuid, integer, text, text, date) from public, anon;
grant execute on function registar_pagamento_acerto(uuid, integer, text, text, date) to authenticated;

/** Número da fatura emitida no software certificado (comissão e entregas da semana) */
create or replace function definir_fatura_acerto(p_acerto uuid, p_numero text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if length(coalesce(btrim(p_numero), '')) not between 1 and 60 then
    raise exception 'numero_invalido' using errcode = 'P0001';
  end if;
  update acertos_cozinha set numero_fatura = btrim(p_numero), atualizado_em = now()
   where id = p_acerto and deletado_em is null;
  if not found then raise exception 'acerto_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('acerto_fatura', 'acertos_cozinha', p_acerto, jsonb_build_object('numero', btrim(p_numero)));
end $$;
revoke execute on function definir_fatura_acerto(uuid, text) from public, anon;
grant execute on function definir_fatura_acerto(uuid, text) to authenticated;

/** Conta-corrente de uma cozinha: acertos, pagamentos e o saldo em aberto (o que ainda falta pagar) */
create or replace function conta_corrente_cozinha(p_cozinha uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return (
    with a as (
      select a.*, coalesce((select sum(valor) from acertos_pagamentos p
                             where p.acerto_id = a.id and p.deletado_em is null), 0)::int as pago
        from acertos_cozinha a where a.cozinha_id = p_cozinha and a.deletado_em is null)
    select jsonb_build_object(
      'cozinha_id', p_cozinha,
      'cozinha_nome', (select btrim(nome) from cozinhas where id = p_cozinha),
      -- > 0 a cozinha ainda deve à plataforma; < 0 a plataforma ainda deve à cozinha
      'em_aberto', coalesce(sum(sign(a.saldo) * greatest(abs(a.saldo) - a.pago, 0)), 0)::int,
      'acertos', coalesce(jsonb_agg(jsonb_build_object(
                   'acerto_id', a.id, 'semana_inicio', a.semana_inicio, 'semana_fim', a.semana_fim,
                   'pedidos', a.pedidos, 'saldo', a.saldo, 'pago', a.pago, 'estado', a.estado,
                   'numero_fatura', a.numero_fatura,
                   'pagamentos', (select coalesce(jsonb_agg(jsonb_build_object(
                                     'quem_paga', p.quem_paga, 'valor', p.valor, 'metodo', p.metodo,
                                     'referencia', p.referencia, 'data', p.data) order by p.data, p.criado_em), '[]')
                                    from acertos_pagamentos p where p.acerto_id = a.id and p.deletado_em is null))
                 order by a.semana_inicio desc), '[]'::jsonb))
    from a);
end $$;
revoke execute on function conta_corrente_cozinha(uuid) from public, anon;
grant execute on function conta_corrente_cozinha(uuid) to authenticated;
