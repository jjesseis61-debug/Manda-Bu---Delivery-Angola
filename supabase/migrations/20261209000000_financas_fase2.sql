-- =============================================================================
-- Finanças: fecho da Fase 1 (acertos) e Fase 2 do plano contabilístico (20/11/2026)
-- -----------------------------------------------------------------------------
-- Fase 1 (acertos com as cozinhas):
--  * o gerente da cozinha vê os acertos da SUA cozinha (só ver; fechar e pagar continua com finanças);
--  * aviso na segunda às 8h (N45) a quem trata das finanças: semanas por fechar e valores;
--  * foto do comprovativo nos pagamentos dos acertos (bucket privado comprovativos, acertos/<id>/…).
-- Fase 2:
--  * número da fatura de cada venda, emitida pela plataforma (software certificado) ou pela cozinha
--    (por defeito o que a cozinha tiver definido); lista das vendas sem fatura e contagem por semana;
--  * compensações das reclamações: a decisão com valor passa a ser uma compensação a pagar ao
--    cliente, a cargo da plataforma ou da cozinha (pela categoria; muda-se antes de pagar). Paga pela
--    plataforma; se for a cargo da cozinha entra no acerto dela (a cozinha deve-a à plataforma);
--  * contas a receber das empresas (B2B): fatura do mês com número e vencimento, pagamento, atraso.
-- =============================================================================

-- ============================================================ F1 · aviso, gerente, comprovativo
alter table acertos_pagamentos add column if not exists comprovativo text;

-- Foto do comprovativo de um acerto: acertos/<acerto_id>/<ficheiro> (envia quem trata das finanças)
create or replace function acerto_caminho_valido(p_nome text) returns boolean
language sql stable security definer set search_path = public as $$
  select split_part(p_nome, '/', 1) = 'acertos'
     and split_part(p_nome, '/', 4) = ''
     and split_part(p_nome, '/', 3) ~ '^[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$'
     and exists (select 1 from acertos_cozinha a where a.id::text = split_part(p_nome, '/', 2) and a.deletado_em is null);
$$;
revoke execute on function acerto_caminho_valido(text) from public, anon;
grant execute on function acerto_caminho_valido(text) to authenticated;

drop policy if exists comprovativos_acertos_enviar on storage.objects;
create policy comprovativos_acertos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'comprovativos' and (select tem_permissao('financas.conferir')) and acerto_caminho_valido(name));

-- ============================================================ F2 · faturas das vendas
alter table cozinhas add column if not exists faturacao text not null default 'plataforma'
  check (faturacao in ('plataforma', 'cozinha'));
comment on column cozinhas.faturacao is 'Quem emite, por defeito, a fatura ao cliente das vendas desta cozinha';

create table if not exists faturas_pedidos (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  pedido_id       uuid not null unique references pedidos(id),
  cozinha_id      uuid references cozinhas(id),
  emitida_por     text not null check (emitida_por in ('plataforma', 'cozinha')),
  numero          text not null check (length(numero) between 1 and 60),
  chave           text not null unique,   -- o mesmo número não se usa duas vezes no mesmo emissor
  registado_por   uuid references funcionarios(id)
);
create index if not exists faturas_pedidos_cozinha_idx on faturas_pedidos (cozinha_id);
create index if not exists faturas_pedidos_registado_idx on faturas_pedidos (registado_por);
alter table faturas_pedidos enable row level security;
revoke all on faturas_pedidos from anon, authenticated;

/** Regista (ou corrige) o número da fatura de uma venda. Quem: finanças ou a gestão da cozinha. */
create or replace function registar_fatura_pedido(p_pedido uuid, p_numero text, p_emitida_por text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  p pedidos;
  v_por text;
  v_num text := upper(regexp_replace(btrim(coalesce(p_numero, '')), '\s+', ' ', 'g'));
begin
  select * into p from pedidos where id = p_pedido and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not (tem_permissao('financas.conferir') or pode_na_cozinha('pedidos.gerir', p.cozinha_id)) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if p.estado not in ('entregue_pago', 'estornado') then raise exception 'pedido_nao_entregue' using errcode = 'P0001'; end if;
  if length(v_num) not between 1 and 60 then raise exception 'numero_invalido' using errcode = 'P0001'; end if;
  v_por := coalesce(p_emitida_por, (select faturacao from cozinhas where id = p.cozinha_id), 'plataforma');
  if v_por not in ('plataforma', 'cozinha') then raise exception 'emissor_invalido' using errcode = 'P0001'; end if;
  begin
    insert into faturas_pedidos (pedido_id, cozinha_id, emitida_por, numero, chave, registado_por)
    values (p.id, p.cozinha_id, v_por, v_num,
            v_por || ':' || case when v_por = 'cozinha' then coalesce(p.cozinha_id::text, '') else '' end || ':' || v_num,
            funcionario_actual())
    on conflict (pedido_id) do update
      set emitida_por = excluded.emitida_por, numero = excluded.numero, chave = excluded.chave,
          registado_por = excluded.registado_por, atualizado_em = now();
  exception when unique_violation then
    raise exception 'numero_repetido' using errcode = 'P0001';
  end;
  perform registar_auditoria('fatura_pedido', 'pedidos', p.id, jsonb_build_object('numero', v_num, 'emitida_por', v_por));
end $$;
revoke execute on function registar_fatura_pedido(uuid, text, text) from public, anon;
grant execute on function registar_fatura_pedido(uuid, text, text) to authenticated;

/** Vendas entregues nos últimos p_dias sem número de fatura (as das cozinhas que a pessoa pode ver) */
create or replace function vendas_sem_fatura(p_dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_fin boolean := tem_permissao('financas.conferir');
begin
  if not (v_fin or tem_permissao('pedidos.gerir')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'pedido_id', p.id, 'entregue_em', p.entregue_em, 'cozinha_id', p.cozinha_id,
             'cozinha_nome', btrim(k.nome), 'faturacao', k.faturacao, 'cliente_nome', c.nome,
             'cliente_nif', c.nif, 'valor', (p.subtotal + p.taxa_entrega - p.desconto_indicacao)::int)
           order by p.entregue_em)
      from pedidos p
      join cozinhas k on k.id = p.cozinha_id
      left join clientes c on c.id = p.cliente_id
     where p.deletado_em is null and p.estado = 'entregue_pago'
       and p.entregue_em >= now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 366))
       and not exists (select 1 from faturas_pedidos f where f.pedido_id = p.id)
       and (v_fin or pode_na_cozinha('pedidos.gerir', p.cozinha_id))), '[]'::jsonb);
end $$;
revoke execute on function vendas_sem_fatura(integer) from public, anon;
grant execute on function vendas_sem_fatura(integer) to authenticated;

/** Quem emite a fatura das vendas de uma cozinha, por defeito */
create or replace function definir_faturacao_cozinha(p_cozinha uuid, p_faturacao text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if p_faturacao not in ('plataforma', 'cozinha') then raise exception 'emissor_invalido' using errcode = 'P0001'; end if;
  update cozinhas set faturacao = p_faturacao, atualizado_em = now() where id = p_cozinha and deletado_em is null;
  if not found then raise exception 'cozinha_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('cozinha_faturacao', 'cozinhas', p_cozinha, jsonb_build_object('faturacao', p_faturacao));
end $$;
revoke execute on function definir_faturacao_cozinha(uuid, text) from public, anon;
grant execute on function definir_faturacao_cozinha(uuid, text) to authenticated;

-- ============================================================ F2 · compensações das reclamações
create table if not exists compensacoes (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  reclamacao_id   uuid not null unique references reclamacoes(id),
  pedido_id       uuid not null references pedidos(id),
  cliente_id      uuid not null references clientes(id),
  cozinha_id      uuid references cozinhas(id),
  tipo            text not null check (tipo in ('desconto', 'reembolso_parcial', 'reembolso_total')),
  valor           integer not null check (valor > 0),
  a_cargo         text not null check (a_cargo in ('plataforma', 'cozinha')),
  estado          text not null default 'por_pagar' check (estado in ('por_pagar', 'paga', 'anulada')),
  metodo          text check (metodo is null or metodo in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money')),
  referencia      text check (referencia is null or length(referencia) between 1 and 60),
  pago_em         timestamptz,
  pago_por        uuid references funcionarios(id)
);
create index if not exists compensacoes_pedido_idx on compensacoes (pedido_id);
create index if not exists compensacoes_cliente_idx on compensacoes (cliente_id);
create index if not exists compensacoes_cozinha_idx on compensacoes (cozinha_id);
create index if not exists compensacoes_pago_por_idx on compensacoes (pago_por);
alter table compensacoes enable row level security;
revoke all on compensacoes from anon, authenticated;

-- A decisão procedente com valor cria a compensação (a cargo da cozinha se a falha foi da comida)
create or replace function reclamacoes_criar_compensacao() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.estado = 'resolvida' and coalesce(new.procedente, false)
     and new.compensacao in ('desconto', 'reembolso_parcial', 'reembolso_total')
     and coalesce(new.compensacao_valor, 0) > 0
     and not exists (select 1 from compensacoes c where c.reclamacao_id = new.id) then
    insert into compensacoes (reclamacao_id, pedido_id, cliente_id, cozinha_id, tipo, valor, a_cargo)
    select new.id, new.pedido_id, new.cliente_id, p.cozinha_id, new.compensacao, new.compensacao_valor,
           case when new.categoria in ('qualidade', 'quantidade', 'pedido_errado') then 'cozinha' else 'plataforma' end
      from pedidos p where p.id = new.pedido_id;
  end if;
  return new;
end $$;
revoke execute on function reclamacoes_criar_compensacao() from public, anon, authenticated;
drop trigger if exists trg_compensacao on reclamacoes;
create trigger trg_compensacao after update on reclamacoes
  for each row execute function reclamacoes_criar_compensacao();

create or replace function compensacoes_lista(p_estado text default 'por_pagar') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'criado_em', c.criado_em, 'pedido_id', c.pedido_id, 'cliente_nome', cl.nome,
             'cliente_telefone', cl.telefone, 'cozinha_nome', btrim(k.nome), 'tipo', c.tipo, 'valor', c.valor,
             'a_cargo', c.a_cargo, 'estado', c.estado, 'metodo', c.metodo, 'referencia', c.referencia,
             'pago_em', c.pago_em, 'categoria', r.categoria, 'reclamacao', r.texto)
           order by c.criado_em desc)
      from compensacoes c
      join reclamacoes r on r.id = c.reclamacao_id
      join clientes cl on cl.id = c.cliente_id
      left join cozinhas k on k.id = c.cozinha_id
     where p_estado is null or c.estado = p_estado), '[]'::jsonb);
end $$;
revoke execute on function compensacoes_lista(text) from public, anon;
grant execute on function compensacoes_lista(text) to authenticated;

create or replace function definir_cargo_compensacao(p_id uuid, p_a_cargo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if p_a_cargo not in ('plataforma', 'cozinha') then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  update compensacoes set a_cargo = p_a_cargo, atualizado_em = now() where id = p_id and estado = 'por_pagar';
  if not found then raise exception 'compensacao_ja_paga' using errcode = 'P0001'; end if;
  perform registar_auditoria('compensacao_cargo', 'compensacoes', p_id, jsonb_build_object('a_cargo', p_a_cargo));
end $$;
revoke execute on function definir_cargo_compensacao(uuid, text) from public, anon;
grant execute on function definir_cargo_compensacao(uuid, text) to authenticated;

/** A plataforma paga a compensação ao cliente (ou anula-a, com p_metodo = 'anular') */
create or replace function pagar_compensacao(p_id uuid, p_metodo text, p_referencia text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if p_metodo = 'anular' then
    update compensacoes set estado = 'anulada', atualizado_em = now() where id = p_id and estado = 'por_pagar';
    if not found then raise exception 'compensacao_ja_paga' using errcode = 'P0001'; end if;
    perform registar_auditoria('compensacao_anulada', 'compensacoes', p_id, '{}'::jsonb);
    return;
  end if;
  if p_metodo is null or p_metodo not in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if p_metodo <> 'Dinheiro' and length(coalesce(btrim(p_referencia), '')) < 4 then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  update compensacoes set estado = 'paga', metodo = p_metodo, referencia = nullif(btrim(p_referencia), ''),
                          pago_em = now(), pago_por = funcionario_actual(), atualizado_em = now()
   where id = p_id and estado = 'por_pagar';
  if not found then raise exception 'compensacao_ja_paga' using errcode = 'P0001'; end if;
  perform registar_auditoria('compensacao_paga', 'compensacoes', p_id,
                             jsonb_build_object('metodo', p_metodo, 'referencia', p_referencia));
end $$;
revoke execute on function pagar_compensacao(uuid, text, text) from public, anon;
grant execute on function pagar_compensacao(uuid, text, text) to authenticated;

-- ============================================================ Acertos com compensações
alter table acertos_cozinha add column if not exists compensacoes integer not null default 0;
alter table acertos_linhas add column if not exists compensacao integer not null default 0;
alter table acertos_linhas drop constraint if exists acertos_linhas_tipo_check;
alter table acertos_linhas add constraint acertos_linhas_tipo_check check (tipo in ('venda', 'estorno', 'compensacao'));

create or replace function acerto_movimentos(p_cozinha uuid, p_semana date)
returns table(pedido_id uuid, tipo text, valores jsonb)
language sql stable security definer set search_path = public as $$
  select p.id, 'venda', acerto_valores_pedido(p, 1) || '{"compensacao": 0}'
    from pedidos p
   where p.cozinha_id = p_cozinha and p.deletado_em is null and p.estado = 'entregue_pago'
     and (p.entregue_em at time zone 'Africa/Luanda')::date between p_semana and p_semana + 6
     and not exists (select 1 from acertos_linhas l where l.pedido_id = p.id and l.tipo = 'venda')
  union all
  select p.id, 'estorno', acerto_valores_pedido(p, -1) || '{"compensacao": 0}'
    from pedidos p
   where p.cozinha_id = p_cozinha and p.deletado_em is null and p.estado = 'estornado'
     and exists (select 1 from acertos_linhas l where l.pedido_id = p.id and l.tipo = 'venda')
     and not exists (select 1 from acertos_linhas l where l.pedido_id = p.id and l.tipo = 'estorno')
  union all
  -- Compensação paga pela plataforma a cargo da cozinha (até ao fim da semana): a cozinha deve-a
  select c.pedido_id, 'compensacao', jsonb_build_object(
           'vendas', 0, 'taxas_entrega', 0, 'comissao', 0, 'convida_plataforma', 0, 'pago_pacote', 0,
           'valor_empresa', 0, 'compensacao', c.valor, 'saldo', c.valor)
    from compensacoes c
   where c.cozinha_id = p_cozinha and c.estado = 'paga' and c.a_cargo = 'cozinha'
     and (c.pago_em at time zone 'Africa/Luanda')::date <= p_semana + 6
     and not exists (select 1 from acertos_linhas l where l.pedido_id = c.pedido_id and l.tipo = 'compensacao');
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
    'compensacoes', coalesce(sum((m -> 'valores' ->> 'compensacao')::int), 0),
    'saldo', coalesce(sum((m -> 'valores' ->> 'saldo')::int), 0))
  from jsonb_array_elements(coalesce(p_mov, '[]')) m;
$$;

/**
 * Acertos de uma semana. Quem trata das finanças vê todas as cozinhas e pode fechar e pagar; o
 * gerente de uma cozinha vê só a(s) sua(s), sem poder mexer.
 */
create or replace function acertos_semana(p_semana date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_sem date := semana_de(coalesce(p_semana, (now() at time zone 'Africa/Luanda')::date));
  v_fin boolean := tem_permissao('financas.conferir');
begin
  if not v_fin and not exists (select 1 from cozinhas k where k.deletado_em is null and pode_ver_relatorio(k.id)) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return jsonb_build_object(
    'semana_inicio', v_sem, 'semana_fim', v_sem + 6,
    'pode_fechar', v_sem + 6 < (now() at time zone 'Africa/Luanda')::date,
    'pode_gerir', v_fin,
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
                                 'pago_pacote', a.pago_pacote, 'valor_empresa', a.valor_empresa,
                                 'compensacoes', a.compensacoes, 'saldo', a.saldo)
                             else acerto_totais((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'valores', m.valores))
                                                   from acerto_movimentos(k.id, v_sem) m)) end,
                   'comissao_percent', coalesce(a.comissao_percent, k.comissao_percent),
                   'pago', coalesce(pg.pago, 0),
                   'por_pagar', case when a.id is null then 0 else greatest(abs(a.saldo) - coalesce(pg.pago, 0), 0) end,
                   'sem_fatura', (select count(*)::int from pedidos p
                                   where p.cozinha_id = k.id and p.deletado_em is null and p.estado = 'entregue_pago'
                                     and (p.entregue_em at time zone 'Africa/Luanda')::date between v_sem and v_sem + 6
                                     and not exists (select 1 from faturas_pedidos f where f.pedido_id = p.id))) as x
            from cozinhas k
            left join acertos_cozinha a on a.cozinha_id = k.id and a.semana_inicio = v_sem and a.deletado_em is null
            left join lateral (select sum(valor)::int as pago from acertos_pagamentos ap
                                where ap.acerto_id = a.id and ap.deletado_em is null) pg on true
           where k.deletado_em is null
             and (v_fin or pode_ver_relatorio(k.id))
             and (a.id is not null or exists (select 1 from acerto_movimentos(k.id, v_sem)))) s), '[]'::jsonb));
end $$;
revoke execute on function acertos_semana(date) from public, anon;
grant execute on function acertos_semana(date) to authenticated;

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
  if found then return v_id; end if;
  perform pg_advisory_xact_lock(hashtext('acerto:' || p_cozinha::text));
  select jsonb_agg(jsonb_build_object('pedido_id', m.pedido_id, 'tipo', m.tipo, 'valores', m.valores))
    into v_mov from acerto_movimentos(p_cozinha, v_sem) m;
  t := acerto_totais(v_mov);
  select comissao_percent into v_pct from cozinhas where id = p_cozinha;
  insert into acertos_cozinha (dispositivo_id, sincronizado_em, cozinha_id, semana_inicio, semana_fim, pedidos, vendas,
                               taxas_entrega, comissao_percent, comissao, convida_plataforma, pago_pacote, valor_empresa,
                               compensacoes, deve_cozinha, deve_plataforma, saldo, estado, fechado_por)
  values ('servidor', now(), p_cozinha, v_sem, v_sem + 6, (t ->> 'pedidos')::int, (t ->> 'vendas')::int,
          (t ->> 'taxas_entrega')::int, coalesce(v_pct, 0), (t ->> 'comissao')::int, (t ->> 'convida_plataforma')::int,
          (t ->> 'pago_pacote')::int, (t ->> 'valor_empresa')::int, (t ->> 'compensacoes')::int,
          (t ->> 'taxas_entrega')::int + (t ->> 'comissao')::int + (t ->> 'compensacoes')::int,
          (t ->> 'convida_plataforma')::int + (t ->> 'pago_pacote')::int + (t ->> 'valor_empresa')::int,
          (t ->> 'saldo')::int, case when (t ->> 'saldo')::int = 0 then 'pago' else 'fechado' end, funcionario_actual())
  returning id into v_id;
  insert into acertos_linhas (acerto_id, pedido_id, tipo, vendas, taxas_entrega, comissao, convida_plataforma,
                              pago_pacote, valor_empresa, compensacao, saldo)
  select v_id, (m ->> 'pedido_id')::uuid, m ->> 'tipo', (m -> 'valores' ->> 'vendas')::int,
         (m -> 'valores' ->> 'taxas_entrega')::int, (m -> 'valores' ->> 'comissao')::int,
         (m -> 'valores' ->> 'convida_plataforma')::int, (m -> 'valores' ->> 'pago_pacote')::int,
         (m -> 'valores' ->> 'valor_empresa')::int, coalesce((m -> 'valores' ->> 'compensacao')::int, 0),
         (m -> 'valores' ->> 'saldo')::int
    from jsonb_array_elements(coalesce(v_mov, '[]')) m;
  perform registar_auditoria('acerto_fechado', 'acertos_cozinha', v_id, t);
  return v_id;
end $$;
revoke execute on function fechar_acerto(uuid, date) from public, anon;
grant execute on function fechar_acerto(uuid, date) to authenticated;

-- Pagamento com foto do comprovativo (opcional)
drop function if exists registar_pagamento_acerto(uuid, integer, text, text, date);
create or replace function registar_pagamento_acerto(p_acerto uuid, p_valor integer, p_metodo text,
                                                     p_referencia text default null, p_data date default null,
                                                     p_comprovativo text default null)
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
  if p_comprovativo is not null
     and (split_part(p_comprovativo, '/', 2) <> a.id::text
          or not exists (select 1 from storage.objects o where o.bucket_id = 'comprovativos' and o.name = p_comprovativo)) then
    raise exception 'comprovativo_invalido' using errcode = 'P0001';
  end if;
  insert into acertos_pagamentos (acerto_id, quem_paga, valor, metodo, referencia, data, registado_por, comprovativo)
  values (a.id, case when a.saldo > 0 then 'cozinha' else 'plataforma' end, p_valor, p_metodo,
          nullif(btrim(p_referencia), ''), coalesce(p_data, (now() at time zone 'Africa/Luanda')::date), funcionario_actual(),
          p_comprovativo);
  v_pago := v_pago + p_valor;
  if v_pago >= abs(a.saldo) then
    update acertos_cozinha set estado = 'pago', atualizado_em = now() where id = a.id;
  end if;
  perform registar_auditoria('acerto_pagamento', 'acertos_cozinha', a.id,
                             jsonb_build_object('valor', p_valor, 'metodo', p_metodo, 'referencia', p_referencia,
                                                'comprovativo', p_comprovativo));
  return jsonb_build_object('pago', v_pago, 'falta', greatest(abs(a.saldo) - v_pago, 0),
                            'estado', case when v_pago >= abs(a.saldo) then 'pago' else 'fechado' end);
end $$;
revoke execute on function registar_pagamento_acerto(uuid, integer, text, text, date, text) from public, anon;
grant execute on function registar_pagamento_acerto(uuid, integer, text, text, date, text) to authenticated;

-- Aviso de segunda-feira (N45): semanas por fechar, a receber e a pagar
create or replace function job_acertos_semana() returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_sem date := semana_de((now() at time zone 'Africa/Luanda')::date) - 7;
  v_n int := 0; v_receber int := 0; v_pagar int := 0;
  k record;
  t jsonb;
begin
  for k in select id from cozinhas where deletado_em is null loop
    continue when exists (select 1 from acertos_cozinha a where a.cozinha_id = k.id and a.semana_inicio = v_sem and a.deletado_em is null);
    t := acerto_totais((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'valores', m.valores))
                          from acerto_movimentos(k.id, v_sem) m));
    continue when (t ->> 'pedidos')::int = 0 and (t ->> 'saldo')::int = 0;
    v_n := v_n + 1;
    if (t ->> 'saldo')::int > 0 then v_receber := v_receber + (t ->> 'saldo')::int;
    else v_pagar := v_pagar - (t ->> 'saldo')::int; end if;
  end loop;
  if v_n = 0 then return 0; end if;
  insert into notificacoes_fila (funcionario_id, codigo, dados)
  select f.id, 'N45', jsonb_build_object('semana_inicio', v_sem, 'semana_fim', v_sem + 6, 'cozinhas', v_n,
                                         'a_receber', v_receber, 'a_pagar', v_pagar)
    from funcionarios f
   where f.deletado_em is null and tem_permissao_de(f.id, 'financas.conferir');
  return v_n;
end $$;
revoke execute on function job_acertos_semana() from public, anon, authenticated;

-- Segunda-feira 8h em Luanda = 7h UTC
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_acertos_semana', '0 7 * * 1', 'select public.job_acertos_semana()');
  end if;
end $$;

-- Texto, validade e envio do N45 (acrescentado às definições actuais, como o N42)
do $$
declare
  v_def text;
  v_novo text;
begin
  if position($s$'N45'$s$ in pg_get_functiondef('texto_notificacao(text, jsonb)'::regprocedure)) > 0 then
    return;
  end if;
  v_def := pg_get_functiondef('texto_notificacao(text, jsonb)'::regprocedure);
  v_novo := replace(v_def,
    $s$when p_codigo = 'N42' then$s$,
    $s$when p_codigo = 'N45' then 'Acertos com as cozinhas por fechar' when p_codigo = 'N42' then$s$);
  v_novo := replace(v_novo,
    $s$when 'N42' then format($s$,
    $s$when 'N45' then format('Semana de %s a %s: %s cozinha(s) por fechar · a receber %s Kz · a pagar %s Kz.',
                                  to_char((p_dados ->> 'semana_inicio')::date, 'DD/MM'),
                                  to_char((p_dados ->> 'semana_fim')::date, 'DD/MM'),
                                  coalesce(p_dados ->> 'cozinhas', '0'),
                                  replace(to_char(coalesce((p_dados ->> 'a_receber')::numeric, 0), 'FM999,999,990'), ',', '.'),
                                  replace(to_char(coalesce((p_dados ->> 'a_pagar')::numeric, 0), 'FM999,999,990'), ',', '.'))
           when 'N42' then format($s$);
  if v_novo = v_def or (length(v_novo) - length(v_def)) < 300 then
    raise exception 'N45: texto_notificacao não tem o formato esperado';
  end if;
  execute v_novo;

  v_def := pg_get_functiondef('notificacoes_por_enviar(integer)'::regprocedure);
  v_novo := regexp_replace(v_def, $s$('N42'(, 'N4[34]')*)\)$s$, $s$\1, 'N45')$s$);
  if v_novo = v_def then
    raise exception 'N45: notificacoes_por_enviar não tem o formato esperado';
  end if;
  execute v_novo;

  v_def := pg_get_functiondef('notificacao_valida(text, timestamptz)'::regprocedure);
  v_novo := replace(v_def, $s$when 'N42' then$s$, $s$when 'N45' then interval '3 days' when 'N42' then$s$);
  if v_novo = v_def then
    raise exception 'N45: notificacao_valida não tem o formato esperado';
  end if;
  execute v_novo;
end $$;

-- ============================================================ F2 · contas a receber das empresas
create table if not exists faturas_empresa (
  id              uuid primary key default gen_random_uuid(),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  empresa_id      uuid not null references empresas(id),
  mes             date not null check (extract(day from mes) = 1),
  valor           integer not null check (valor >= 0),
  pedidos         integer not null default 0,
  numero          text not null check (length(numero) between 1 and 60),
  vencimento      date not null,
  estado          text not null default 'emitida' check (estado in ('emitida', 'paga', 'anulada')),
  metodo          text check (metodo is null or metodo in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money')),
  referencia      text check (referencia is null or length(referencia) between 1 and 60),
  pago_em         date,
  emitida_por     uuid references funcionarios(id),
  unique (empresa_id, mes)
);
create index if not exists faturas_empresa_emitida_idx on faturas_empresa (emitida_por);
alter table faturas_empresa enable row level security;
revoke all on faturas_empresa from anon, authenticated;

-- O que cada empresa deve num mês: a parte da empresa dos pedidos entregues
create or replace function valor_empresa_mes(p_empresa uuid, p_mes date) returns table(valor integer, pedidos integer)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(valor_empresa), 0)::int, count(*)::int
    from pedidos
   where empresa_id = p_empresa and deletado_em is null and estado = 'entregue_pago' and coalesce(valor_empresa, 0) > 0
     and (entregue_em at time zone 'Africa/Luanda')::date >= date_trunc('month', p_mes)::date
     and (entregue_em at time zone 'Africa/Luanda')::date < (date_trunc('month', p_mes) + interval '1 month')::date;
$$;
revoke execute on function valor_empresa_mes(uuid, date) from public, anon, authenticated;

create or replace function contas_empresas(p_mes date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_mes date := date_trunc('month', coalesce(p_mes, (now() at time zone 'Africa/Luanda')::date))::date;
  v_hoje date := (now() at time zone 'Africa/Luanda')::date;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  return jsonb_build_object(
    'mes', v_mes,
    'pode_faturar', (v_mes + interval '1 month')::date <= v_hoje,
    'empresas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'empresa_id', e.id, 'nome', e.nome,
               'valor', coalesce(f.valor, v.valor), 'pedidos', coalesce(f.pedidos, v.pedidos),
               'fatura_id', f.id, 'numero', f.numero, 'vencimento', f.vencimento,
               'estado', coalesce(f.estado, 'por_faturar'), 'pago_em', f.pago_em, 'referencia', f.referencia,
               'em_atraso', f.estado = 'emitida' and f.vencimento < v_hoje)
             order by e.nome)
        from empresas e
        left join faturas_empresa f on f.empresa_id = e.id and f.mes = v_mes
        cross join lateral valor_empresa_mes(e.id, v_mes) v
       where e.deletado_em is null and (f.id is not null or v.valor > 0)), '[]'::jsonb),
    'em_atraso_total', (select coalesce(sum(valor), 0)::int from faturas_empresa
                         where estado = 'emitida' and vencimento < v_hoje));
end $$;
revoke execute on function contas_empresas(date) from public, anon;
grant execute on function contas_empresas(date) to authenticated;

/** Regista a fatura do mês de uma empresa (emitida no software certificado); o valor vem dos pedidos */
create or replace function emitir_fatura_empresa(p_empresa uuid, p_mes date, p_numero text, p_vencimento date)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_id uuid;
  v record;
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if (v_mes + interval '1 month')::date > (now() at time zone 'Africa/Luanda')::date then
    raise exception 'mes_em_curso' using errcode = 'P0001';
  end if;
  if length(coalesce(btrim(p_numero), '')) not between 1 and 60 then raise exception 'numero_invalido' using errcode = 'P0001'; end if;
  if p_vencimento is null or p_vencimento < (v_mes + interval '1 month')::date then
    raise exception 'vencimento_invalido' using errcode = 'P0001';
  end if;
  select * into v from valor_empresa_mes(p_empresa, v_mes);
  if v.valor <= 0 then raise exception 'sem_valor' using errcode = 'P0001'; end if;
  insert into faturas_empresa (empresa_id, mes, valor, pedidos, numero, vencimento, emitida_por)
  values (p_empresa, v_mes, v.valor, v.pedidos, upper(btrim(p_numero)), p_vencimento, funcionario_actual())
  on conflict (empresa_id, mes) do nothing
  returning id into v_id;
  if v_id is null then raise exception 'fatura_ja_emitida' using errcode = 'P0001'; end if;
  perform registar_auditoria('fatura_empresa', 'faturas_empresa', v_id,
                             jsonb_build_object('numero', p_numero, 'valor', v.valor, 'mes', v_mes));
  return v_id;
end $$;
revoke execute on function emitir_fatura_empresa(uuid, date, text, date) from public, anon;
grant execute on function emitir_fatura_empresa(uuid, date, text, date) to authenticated;

create or replace function pagar_fatura_empresa(p_fatura uuid, p_metodo text, p_referencia text default null,
                                                p_data date default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tem_permissao('financas.conferir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.conferir';
  end if;
  if p_metodo is null or p_metodo not in ('Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if p_metodo <> 'Dinheiro' and length(coalesce(btrim(p_referencia), '')) < 4 then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  update faturas_empresa set estado = 'paga', metodo = p_metodo, referencia = nullif(btrim(p_referencia), ''),
                             pago_em = coalesce(p_data, (now() at time zone 'Africa/Luanda')::date), atualizado_em = now()
   where id = p_fatura and estado = 'emitida';
  if not found then raise exception 'fatura_ja_paga' using errcode = 'P0001'; end if;
  perform registar_auditoria('fatura_empresa_paga', 'faturas_empresa', p_fatura,
                             jsonb_build_object('metodo', p_metodo, 'referencia', p_referencia));
end $$;
revoke execute on function pagar_fatura_empresa(uuid, text, text, date) from public, anon;
grant execute on function pagar_fatura_empresa(uuid, text, text, date) to authenticated;
