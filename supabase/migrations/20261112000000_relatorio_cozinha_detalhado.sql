-- =============================================================================
-- Relatório da cozinha detalhado (docs/plano-relatorio-cozinha.md)
-- -----------------------------------------------------------------------------
-- Decisões do dono do produto (11/11/2026):
--  * a plataforma fica com uma COMISSÃO (%) por cozinha -> "a receber pela cozinha";
--  * quem paga o desconto de convite e o saldo Convida é uma OPÇÃO da plataforma
--    (parametros.convida_pago_por): 'plataforma' (por defeito, não reduz o que a cozinha
--    recebe) ou 'cozinha' (sai do valor a receber pela cozinha);
--  * sem IVA separado por agora;
--  * fecho do dia automático às 23h (Luanda): push aos gerentes da cozinha e ao admin.
-- Definições: venda = pedido "entregue_pago" com entregue_em no período; cancelado conta
-- à parte (pela data do pedido); datas sempre no dia de Luanda; máximo 366 dias.
-- A RPC antiga relatorio_cozinha mantém-se (APKs antigos).
-- =============================================================================

alter table cozinhas
  add column if not exists comissao_percent numeric(5,2) not null default 0
    check (comissao_percent between 0 and 50);
comment on column cozinhas.comissao_percent is
  'Comissão da plataforma sobre as vendas de comida (subtotal) desta cozinha, em %';

alter table parametros
  add column if not exists convida_pago_por text not null default 'plataforma'
    check (convida_pago_por in ('plataforma', 'cozinha'));
comment on column parametros.convida_pago_por is
  'Quem paga o desconto de convite e o saldo Convida usado: plataforma ou cozinha (relatório da cozinha)';

-- A comissão só a muda quem gere a plataforma (o gerente edita a cozinha mas não a comissão)
create or replace function cozinhas_proteger_comissao() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT' and new.comissao_percent <> 0)
     or (tg_op = 'UPDATE' and new.comissao_percent is distinct from old.comissao_percent) then
    if auth.uid() is not null and not tem_permissao('plataforma.parametros') then
      raise exception 'sem_permissao' using errcode = '42501', detail = 'plataforma.parametros';
    end if;
  end if;
  return new;
end $$;
revoke execute on function cozinhas_proteger_comissao() from public, anon, authenticated;
drop trigger if exists trg_proteger_comissao on cozinhas;
create trigger trg_proteger_comissao before insert or update on cozinhas
  for each row execute function cozinhas_proteger_comissao();

-- Quem pode ver o relatório de uma cozinha: relatorios.exportar E (admin, cozinhas.gerir,
-- ou da equipa dessa cozinha). Um gerente só vê a(s) sua(s) cozinha(s).
create or replace function pode_ver_relatorio(p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select tem_permissao('relatorios.exportar')
     and (coalesce((select administrador_principal from funcionarios where id = funcionario_actual()), false)
          or tem_permissao('cozinhas.gerir')
          or pertence_a_cozinha(funcionario_actual(), p_cozinha));
$$;
revoke execute on function pode_ver_relatorio(uuid) from public, anon, authenticated;

-- Resumo (secção A) de um intervalo [p_ini, p_fim) — usado para o período e o anterior
create or replace function resumo_cozinha(p_cozinha uuid, p_ini timestamptz, p_fim timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  with v as (
    select * from pedidos
     where cozinha_id = p_cozinha and deletado_em is null and estado = 'entregue_pago'
       and entregue_em >= p_ini and entregue_em < p_fim),
  c as (
    select * from pedidos
     where cozinha_id = p_cozinha and deletado_em is null and estado = 'cancelado'
       and criado_em >= p_ini and criado_em < p_fim),
  k as (select coalesce(comissao_percent, 0) as pct from cozinhas where id = p_cozinha),
  tol as (select tolerancia_entrega_min as m from parametros where unico),
  quem as (select convida_pago_por as q from parametros where unico),
  t as (
    select count(*)::int as pedidos,
           coalesce(sum(subtotal), 0)::int as brutas,
           coalesce(sum(desconto_indicacao), 0)::int as desconto_convite,
           coalesce(sum(credito_indicacao_usado), 0)::int as saldo_convida,
           coalesce(sum(pago_pacote), 0)::int as pago_pacote,
           coalesce(sum(valor_empresa), 0)::int as valor_empresa,
           coalesce(sum(taxa_entrega), 0)::int as taxas_entrega,
           count(distinct cliente_id)::int as clientes,
           count(*) filter (where hora_prometida is not null)::int as com_hora,
           count(*) filter (where hora_prometida is not null
                              and entregue_em <= hora_prometida + make_interval(mins => (select m from tol)))::int as a_horas
      from v)
  select jsonb_build_object(
    'pedidos', t.pedidos,
    'vendas_brutas', t.brutas,
    'desconto_convite', t.desconto_convite,
    'saldo_convida', t.saldo_convida,
    'descontos', t.desconto_convite + t.saldo_convida,
    'vendas_liquidas', t.brutas - t.desconto_convite - t.saldo_convida,
    'pago_pacote', t.pago_pacote,
    'valor_empresa', t.valor_empresa,
    'taxas_entrega', t.taxas_entrega,
    'ticket_medio', case when t.pedidos > 0 then round(t.brutas::numeric / t.pedidos)::int end,
    'cancelados', (select count(*)::int from c),
    'cancelados_valor', (select coalesce(sum(subtotal), 0)::int from c),
    'cancelados_cliente', (select count(*)::int from c where cancelado_por = 'cliente'),
    'cancelados_cozinha', (select count(*)::int from c where cancelado_por is distinct from 'cliente'),
    'clientes', t.clientes,
    'clientes_novos', (select count(*)::int from (
        select x.cliente_id from v x
         where not exists (select 1 from pedidos y
                            where y.cliente_id = x.cliente_id and y.cozinha_id = p_cozinha
                              and y.estado = 'entregue_pago' and y.deletado_em is null
                              and y.entregue_em < p_ini)
         group by x.cliente_id) s),
    'avaliacao_media', (select round(avg(estrelas)::numeric, 1) from avaliacoes
                         where cozinha_id = p_cozinha and not oculta and deletado_em is null
                           and criado_em >= p_ini and criado_em < p_fim),
    'avaliacoes', (select count(*)::int from avaliacoes
                    where cozinha_id = p_cozinha and not oculta and deletado_em is null
                      and criado_em >= p_ini and criado_em < p_fim),
    'a_horas_pct', case when t.com_hora > 0 then round(100.0 * t.a_horas / t.com_hora, 1) end,
    'comissao_percent', k.pct,
    'comissao', round(t.brutas * k.pct / 100)::int,
    'convida_pago_por', (select q from quem),
    -- Convida a cargo da cozinha: o desconto e o saldo usado saem do que ela recebe
    'convida_a_cargo_cozinha', case when (select q from quem) = 'cozinha'
                                    then t.desconto_convite + t.saldo_convida else 0 end,
    'a_receber_cozinha', (t.brutas - round(t.brutas * k.pct / 100)
                          - case when (select q from quem) = 'cozinha'
                                 then t.desconto_convite + t.saldo_convida else 0 end)::int)
  from t cross join k;
$$;
revoke execute on function resumo_cozinha(uuid, timestamptz, timestamptz) from public, anon, authenticated;

create or replace function relatorio_cozinha_detalhado(p_cozinha uuid, p_inicio date, p_fim date)
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

  with v as (
    select * from pedidos
     where cozinha_id = p_cozinha and deletado_em is null and estado = 'entregue_pago'
       and entregue_em >= v_ini and entregue_em < v_fim),
  c as (
    select * from pedidos
     where cozinha_id = p_cozinha and deletado_em is null and estado = 'cancelado'
       and criado_em >= v_ini and criado_em < v_fim),
  tol as (select tolerancia_entrega_min as m from parametros where unico),
  -- Uma linha por prato vendido. O nome do montado tira o "(opções)" que o servidor junta.
  linhas as (
    select i ->> 'cardapio_id' as cardapio_id,
           coalesce((select trim(cd.nome) from cardapio cd where cd.id::text = i ->> 'cardapio_id'),
                    regexp_replace(i ->> 'nome', ' \([^()]*\)$', '')) as nome,
           coalesce((i ->> 'qtd')::int, 1) as qtd,
           coalesce((i ->> 'qtd')::int, 1) * coalesce((i ->> 'preco_unitario')::int, 0) as receita,
           i -> 'opcoes' as opcoes
      from v, jsonb_array_elements(v.itens) i),
  pratos as (
    select cardapio_id, max(nome) as nome, sum(qtd)::int as qtd, sum(receita)::int as receita
      from linhas group by cardapio_id)
  select jsonb_build_object(
    'cozinha', (select nome from cozinhas where id = p_cozinha),
    'inicio', p_inicio, 'fim', p_fim,
    -- A. Resumo, e o mesmo resumo do período anterior com a mesma duração (para as variações)
    'resumo', resumo_cozinha(p_cozinha, v_ini, v_fim),
    'anterior', resumo_cozinha(p_cozinha, v_ini - make_interval(days => v_dias), v_ini),
    -- B. Vendas no tempo
    'por_dia', coalesce((
       select jsonb_agg(jsonb_build_object('dia', dia, 'pedidos', n, 'vendas', s) order by dia)
         from (select (entregue_em at time zone 'Africa/Luanda')::date as dia, count(*)::int as n,
                      sum(subtotal)::int as s from v group by 1) x), '[]'),
    'por_hora', coalesce((
       select jsonb_agg(jsonb_build_object('hora', h, 'pedidos', n, 'vendas', s) order by h)
         from (select extract(hour from coalesce(agendado_para, criado_em) at time zone 'Africa/Luanda')::int as h,
                      count(*)::int as n, sum(subtotal)::int as s from v group by 1) x), '[]'),
    'por_dia_semana', case when v_dias >= 14 then coalesce((
       select jsonb_agg(jsonb_build_object('dow', d, 'pedidos', n, 'vendas', s) order by d)
         from (select extract(isodow from entregue_em at time zone 'Africa/Luanda')::int as d,
                      count(*)::int as n, sum(subtotal)::int as s from v group by 1) x), '[]') end,
    -- C. Cardápio
    'pratos', coalesce((
       select jsonb_agg(jsonb_build_object('cardapio_id', cardapio_id, 'nome', nome, 'qtd', qtd, 'receita', receita,
                                           'pct', round(100.0 * receita / nullif((select sum(receita) from pratos), 0), 1))
                        order by receita desc, qtd desc)
         from pratos), '[]'),
    'opcoes_montados', coalesce((
       select jsonb_agg(jsonb_build_object('nome', nome, 'qtd', q) order by q desc, nome)
         from (select o ->> 'nome' as nome, sum(l.qtd)::int as q
                 from linhas l, jsonb_array_elements(coalesce(l.opcoes, '[]')) o group by 1) x), '[]'),
    'montado_valor_medio', (select round(sum(receita)::numeric / nullif(sum(qtd), 0))::int
                              from linhas where jsonb_array_length(coalesce(opcoes, '[]')) > 0),
    'sem_vendas', coalesce((
       select jsonb_agg(trim(cd.nome) order by cd.nome)
         from cardapio cd
        where cd.cozinha_id = p_cozinha and cd.deletado_em is null and cd.disponivel
          and not exists (select 1 from pratos p where p.cardapio_id = cd.id::text)), '[]'),
    -- D. Pagamentos (o que foi recebido na entrega, mais pacote / empresa / Convida)
    'pagamentos', coalesce((
       select jsonb_agg(jsonb_build_object('metodo', m, 'pedidos', n, 'valor', s) order by s desc)
         from (select p ->> 'metodo' as m, count(distinct v.id)::int as n, sum((p ->> 'valor')::numeric)::int as s
                 from v, jsonb_array_elements(coalesce(v.parcelas, '[]')) p group by 1
               union all
               select 'Pacote pré-pago', count(*) filter (where pago_pacote > 0)::int, sum(pago_pacote)::int from v
                having sum(pago_pacote) > 0
               union all
               select 'Conta de empresa', count(*) filter (where valor_empresa > 0)::int, sum(valor_empresa)::int from v
                having sum(valor_empresa) > 0
               union all
               select 'Saldo Convida', count(*) filter (where credito_indicacao_usado > 0)::int,
                      sum(credito_indicacao_usado)::int from v
                having sum(credito_indicacao_usado) > 0) x), '[]'),
    -- F. Operação
    'tempo_medio_min', (select round(avg(extract(epoch from entregue_em - coalesce(agendado_para, criado_em)) / 60))::int
                          from v where entregue_em > coalesce(agendado_para, criado_em)),
    'agendados', (select count(*)::int from v where agendado_para is not null),
    'grupo_empresa', (select count(*)::int from v where grupo_id is not null or empresa_id is not null),
    'cancelamentos_motivos', coalesce((
       select jsonb_agg(jsonb_build_object('motivo', mo, 'n', n) order by n desc)
         from (select coalesce(nullif(trim(motivo_cancelamento), ''), 'Sem motivo') as mo, count(*)::int as n
                 from c group by 1 order by 2 desc limit 5) x), '[]'),
    'estafetas', coalesce((
       select jsonb_agg(jsonb_build_object('nome', nome, 'entregas', n, 'a_horas_pct', pct) order by n desc)
         from (select coalesce(f.nome, '—') as nome, count(*)::int as n,
                      round(100.0 * count(*) filter (where v.hora_prometida is not null
                              and v.entregue_em <= v.hora_prometida + make_interval(mins => (select m from tol)))
                            / nullif(count(*) filter (where v.hora_prometida is not null), 0), 1) as pct
                 from v left join funcionarios f on f.id = v.entregador_id
                where v.entregador_id is not null group by 1) x), '[]'),
    'preparadores', coalesce((
       select jsonb_agg(jsonb_build_object('nome', nome, 'pedidos', n) order by n desc)
         from (select f.nome, count(*)::int as n from v join funcionarios f on f.id = v.preparado_por group by 1) x), '[]'),
    -- G. Zonas
    'zonas', coalesce((
       select jsonb_agg(jsonb_build_object('zona', zona, 'pedidos', n, 'vendas', s) order by s desc)
         from (select coalesce(z.nome, 'Sem zona') as zona, count(*)::int as n, sum(v.subtotal)::int as s
                 from v left join pontos_entrega pe on pe.id = v.ponto_entrega_id
                 left join zonas z on z.id = coalesce(pe.zona_id, v.zona_id) group by 1) x), '[]'),
    -- H. Qualidade
    'estrelas', coalesce((
       select jsonb_object_agg(e, n)
         from (select estrelas::text as e, count(*)::int as n from avaliacoes
                where cozinha_id = p_cozinha and not oculta and deletado_em is null
                  and criado_em >= v_ini and criado_em < v_fim group by 1) x), '{}'),
    'reclamacoes', (select count(*)::int from reclamacoes
                     where cozinha_id = p_cozinha and deletado_em is null
                       and criado_em >= v_ini and criado_em < v_fim),
    'reclamacoes_abertas', (select count(*)::int from reclamacoes
                             where cozinha_id = p_cozinha and deletado_em is null and estado = 'aberta'
                               and criado_em >= v_ini and criado_em < v_fim),
    -- I. Convida e Ganha (custo suportado pela plataforma)
    'convida', jsonb_build_object(
       'pedidos_com_desconto', (select count(*)::int from v where desconto_indicacao > 0),
       'comissoes_geradas', (select coalesce(sum(g.valor), 0)::int from ganhos_indicacao g
                              where g.deletado_em is null and g.estado <> 'anulado'
                                and g.pedido_id in (select id from v)))
  ) into r;
  return r;
end $$;
revoke execute on function relatorio_cozinha_detalhado(uuid, date, date) from public, anon;
grant  execute on function relatorio_cozinha_detalhado(uuid, date, date) to authenticated;

-- Comissão: só o administrador principal (ou plataforma.parametros) a altera
create or replace function definir_comissao_cozinha(p_cozinha uuid, p_percent numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('plataforma.parametros');
  if p_percent is null or p_percent < 0 or p_percent > 50 then
    raise exception 'parametro_invalido' using errcode = 'P0001';
  end if;
  update cozinhas set comissao_percent = round(p_percent, 2) where id = p_cozinha and deletado_em is null;
  if not found then raise exception 'cozinha_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('comissao_cozinha', 'cozinhas', p_cozinha, jsonb_build_object('percent', p_percent));
end $$;
revoke execute on function definir_comissao_cozinha(uuid, numeric) from public, anon;
grant  execute on function definir_comissao_cozinha(uuid, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- Fecho do dia automático (aviso N42), às 23h de Luanda, a cada cozinha com movimento:
-- aos gerentes da cozinha e ao administrador principal.
-- -----------------------------------------------------------------------------
create or replace function job_fecho_dia() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_dia date := (now() at time zone 'Africa/Luanda')::date;
  v_ini timestamptz := v_dia::timestamp at time zone 'Africa/Luanda';
  v_fim timestamptz := (v_dia + 1)::timestamp at time zone 'Africa/Luanda';
  k     record;
  r     jsonb;
  n     int := 0;
begin
  for k in
    select z.id, z.nome from cozinhas z
     where z.deletado_em is null
       and exists (select 1 from pedidos p where p.cozinha_id = z.id and p.deletado_em is null
                      and ((p.estado = 'entregue_pago' and p.entregue_em >= v_ini and p.entregue_em < v_fim)
                           or (p.estado = 'cancelado' and p.criado_em >= v_ini and p.criado_em < v_fim)))
  loop
    r := resumo_cozinha(k.id, v_ini, v_fim);
    insert into notificacoes_fila (funcionario_id, codigo, dados)
    select f, 'N42', jsonb_build_object(
             'cozinha_id', k.id, 'cozinha_nome', trim(k.nome), 'dia', v_dia,
             'pedidos', r -> 'pedidos', 'vendas', r -> 'vendas_brutas', 'ticket', r -> 'ticket_medio',
             'cancelados', r -> 'cancelados', 'a_receber', r -> 'a_receber_cozinha',
             'avaliacao', r -> 'avaliacao_media')
      from (select g as f from gerentes_do_pedido(k.id) g
            union
            select id from funcionarios where administrador_principal and deletado_em is null) d;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function job_fecho_dia() from public, anon, authenticated;

-- 23h em Luanda = 22h UTC
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_fecho_dia', '0 22 * * *', 'select public.job_fecho_dia()');
  end if;
end $$;

-- Texto, validade e envio do N42 (acrescentado às definições actuais, como o N41)
do $$
declare
  v_def text;
  v_novo text;
begin
  -- Já aplicado (migração corrida duas vezes): não faz nada
  if position($s$'N42'$s$ in pg_get_functiondef('notificacoes_por_enviar(integer)'::regprocedure)) > 0 then
    return;
  end if;
  v_def := pg_get_functiondef('texto_notificacao(text, jsonb)'::regprocedure);
  v_novo := replace(v_def,
    $s$when p_codigo = 'N40' then 'Novo código de login'$s$,
    $s$when p_codigo = 'N40' then 'Novo código de login' when p_codigo = 'N42' then 'Fecho do dia · ' || coalesce(p_dados ->> 'cozinha_nome', 'cozinha')$s$);
  v_novo := replace(v_novo,
    $s$when 'N31' then p_dados ->> 'corpo'$s$,
    $s$when 'N42' then format('%s pedidos · %s Kz vendidos · ticket %s Kz · %s cancelado(s)%s. A receber pela cozinha: %s Kz.',
                                  coalesce(p_dados ->> 'pedidos', '0'),
                                  replace(to_char(coalesce((p_dados ->> 'vendas')::numeric, 0), 'FM999,999,990'), ',', '.'),
                                  replace(to_char(coalesce((p_dados ->> 'ticket')::numeric, 0), 'FM999,999,990'), ',', '.'),
                                  coalesce(p_dados ->> 'cancelados', '0'),
                                  case when p_dados ->> 'avaliacao' is not null
                                       then ' · ★ ' || replace(p_dados ->> 'avaliacao', '.', ',') else '' end,
                                  replace(to_char(coalesce((p_dados ->> 'a_receber')::numeric, 0), 'FM999,999,990'), ',', '.'))
           when 'N31' then p_dados ->> 'corpo'$s$);
  if v_novo = v_def or (length(v_novo) - length(v_def)) < 300 then
    raise exception 'N42: texto_notificacao não tem o formato esperado';
  end if;
  execute v_novo;

  v_def := pg_get_functiondef('notificacoes_por_enviar(integer)'::regprocedure);
  v_novo := replace(v_def, $s$'N40', 'N41')$s$, $s$'N40', 'N41', 'N42')$s$);
  if v_novo = v_def then
    raise exception 'N42: notificacoes_por_enviar não tem o formato esperado';
  end if;
  execute v_novo;

  v_def := pg_get_functiondef('notificacao_valida(text, timestamptz)'::regprocedure);
  v_novo := replace(v_def, $s$when 'N41' then$s$, $s$when 'N42' then interval '12 hours' when 'N41' then$s$);
  if v_novo = v_def then
    raise exception 'N42: notificacao_valida não tem o formato esperado';
  end if;
  execute v_novo;
end $$;
