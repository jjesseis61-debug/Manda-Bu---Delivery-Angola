-- Pedidos de grupo também em casa, na família, entre vizinhos e na igreja (não só no trabalho), e
-- duas formas de pagar quando não é a empresa a pagar:
--   * 'individual' (cada um paga a sua parte): por defeito ANTES, por Multicaixa Express ou Unitel Money;
--     o participante escreve a referência na app e as Finanças confirmam; o estafeta só cobra o que falta;
--   * 'quem_recebe': quem recebe paga tudo na entrega e acerta depois com os outros.
-- O pagamento pela empresa continua só para clientes Empresa num endereço de Trabalho.

-- ------------------------------------------------------------------ 1. grupos: tipo e modo
alter table pedidos_grupo add column if not exists tipo text not null default 'trabalho'
  check (tipo in ('trabalho', 'familia', 'vizinhos', 'igreja'));
alter table pedidos_grupo drop constraint if exists pedidos_grupo_modo_pagamento_check;
alter table pedidos_grupo add constraint pedidos_grupo_modo_pagamento_check
  check (modo_pagamento in ('individual', 'empresa', 'quem_recebe'));
grant insert (tipo) on pedidos_grupo to authenticated;

-- Qualquer endereço do organizador serve; o pagamento pela empresa exige um ponto de Trabalho
do $$
declare
  v_def  text := pg_get_functiondef('validar_novo_grupo(uuid,uuid,timestamptz,timestamptz,text)'::regprocedure);
  v_novo text;
begin
  if position('(p_modo = ''empresa'' and v_ponto.tipo <> ''empresa'')' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := replace(v_def, 'if not found or v_ponto.tipo <> ''empresa''',
                    'if not found or (p_modo = ''empresa'' and v_ponto.tipo <> ''empresa'')');
  if v_novo = v_def then raise exception 'validar_novo_grupo não tem o formato esperado'; end if;
  execute v_novo;
end $$;

-- ------------------------------------------------------------------ 2. pagar antes
alter table pedidos add column if not exists pago_antes integer not null default 0 check (pago_antes >= 0);
comment on column pedidos.pago_antes is
  'Parte paga antes da entrega (Multicaixa Express / Unitel Money) e confirmada pelas Finanças';

create table if not exists pagamentos_antecipados (
  id               uuid primary key default gen_random_uuid(),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  pedido_id        uuid not null references pedidos(id),
  cliente_id       uuid not null references clientes(id),
  metodo           text not null check (metodo in ('multicaixa_express', 'unitel_money')),
  valor            integer not null check (valor > 0),
  referencia       text not null,
  referencia_chave text not null,             -- sem espaços e em maiúsculas
  estado           text not null default 'pendente'
                   check (estado in ('pendente', 'confirmado', 'rejeitado', 'devolvido')),
  motivo           text,
  decidido_em      timestamptz,
  decidido_por     uuid references funcionarios(id),
  devolvido_ref    text
);
create index if not exists pagamentos_antecipados_pedido_idx on pagamentos_antecipados (pedido_id);
create index if not exists pagamentos_antecipados_cliente_idx on pagamentos_antecipados (cliente_id);
create index if not exists pagamentos_antecipados_decidido_por_idx on pagamentos_antecipados (decidido_por);
-- A mesma referência não serve duas vezes (a não ser que a primeira tenha sido rejeitada)
create unique index if not exists pagamentos_antecipados_ref_idx
  on pagamentos_antecipados (referencia_chave) where estado <> 'rejeitado';
alter table pagamentos_antecipados enable row level security;
revoke all on pagamentos_antecipados from public, anon, authenticated;

-- Quanto falta pagar no pedido (sem contar o que já foi pago antes)
create or replace function pedido_falta_pagar(p pedidos) returns integer
language sql stable set search_path = public as $$
  select greatest(0, p.subtotal + p.taxa_entrega - p.desconto_indicacao - p.credito_indicacao_usado
                     - p.pago_pacote - p.valor_empresa - p.pago_antes)::int
$$;
revoke execute on function pedido_falta_pagar(pedidos) from public, anon, authenticated;

-- O que a app do cliente mostra no pedido: se pode pagar antes, quanto, e o estado do último envio
create or replace function meu_pagamento_antes(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  p         pedidos;
  g         pedidos_grupo;
  u         pagamentos_antecipados;
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  select * into p from pedidos where id = p_pedido and cliente_id = v_cliente and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  select * into g from pedidos_grupo where id = p.grupo_id;
  select * into u from pagamentos_antecipados where pedido_id = p.id order by criado_em desc limit 1;
  return jsonb_build_object(
    'modo', g.modo_pagamento,
    'pode', coalesce(g.modo_pagamento = 'individual', false)
            and p.estado in ('pendente', 'confirmado', 'em_preparacao')
            and pedido_falta_pagar(p) > 0
            and not exists (select 1 from pagamentos_antecipados x where x.pedido_id = p.id and x.estado = 'pendente'),
    'falta', pedido_falta_pagar(p),
    'pago_antes', p.pago_antes,
    'ultimo', case when u.id is null then null else jsonb_build_object(
                'estado', u.estado, 'valor', u.valor, 'metodo', u.metodo, 'referencia', u.referencia,
                'motivo', u.motivo, 'criado_em', u.criado_em) end);
end $$;
revoke execute on function meu_pagamento_antes(uuid) from public, anon;
grant execute on function meu_pagamento_antes(uuid) to authenticated;

-- O participante diz que pagou: fica pendente até as Finanças confirmarem
create or replace function pagar_antes(p_pedido uuid, p_metodo text, p_referencia text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  p         pedidos;
  g         pedidos_grupo;
  v_chave   text := upper(regexp_replace(coalesce(p_referencia, ''), '\s', '', 'g'));
  v_id      uuid;
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if p_metodo is null or p_metodo not in ('multicaixa_express', 'unitel_money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if length(v_chave) < 4 then raise exception 'referencia_invalida' using errcode = 'P0001'; end if;
  select * into p from pedidos where id = p_pedido and cliente_id = v_cliente and deletado_em is null for update;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  select * into g from pedidos_grupo where id = p.grupo_id;
  if g.id is null or g.modo_pagamento <> 'individual' then
    raise exception 'pagar_antes_indisponivel' using errcode = 'P0001';
  end if;
  if p.estado not in ('pendente', 'confirmado', 'em_preparacao') then
    raise exception 'pedido_ja_nao_aceita_pagamento' using errcode = 'P0001';
  end if;
  if pedido_falta_pagar(p) <= 0 then raise exception 'pedido_ja_pago' using errcode = 'P0001'; end if;
  if exists (select 1 from pagamentos_antecipados where pedido_id = p.id and estado = 'pendente') then
    raise exception 'pagamento_ja_enviado' using errcode = 'P0001';
  end if;
  if exists (select 1 from pagamentos_antecipados where referencia_chave = v_chave and estado <> 'rejeitado')
     or exists (select 1 from comprovativos_pagamento where referencia_chave = v_chave and deletado_em is null) then
    raise exception 'referencia_ja_usada' using errcode = 'P0001';
  end if;
  insert into pagamentos_antecipados (pedido_id, cliente_id, metodo, valor, referencia, referencia_chave)
  values (p.id, v_cliente, p_metodo, pedido_falta_pagar(p), trim(p_referencia), v_chave)
  returning id into v_id;
  perform registar_auditoria('pagamento_antes_enviado', 'pedidos', p.id,
    jsonb_build_object('pagamento_id', v_id, 'metodo', p_metodo, 'valor', pedido_falta_pagar(p)));
  return v_id;
end $$;
revoke execute on function pagar_antes(uuid, text, text) from public, anon;
grant execute on function pagar_antes(uuid, text, text) to authenticated;

-- Finanças: pagamentos por confirmar, confirmados e os que é preciso devolver
create or replace function pagamentos_antes_lista() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('financas.acertos') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.acertos';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', a.id, 'pedido_id', a.pedido_id, 'cliente_nome', c.nome, 'cliente_telefone', c.telefone,
             'metodo', a.metodo, 'valor', a.valor, 'referencia', a.referencia, 'estado', a.estado,
             'motivo', a.motivo, 'criado_em', a.criado_em, 'decidido_em', a.decidido_em,
             'pedido_estado', p.estado, 'grupo_hora', g.hora_entrega, 'cozinha_nome', cz.nome,
             -- Dinheiro recebido num pedido que não vai ser pago na entrega por esta via: devolver
             'a_devolver', (a.estado = 'confirmado' and p.estado = 'cancelado')
                           or (a.estado = 'pendente' and p.estado in ('cancelado', 'entregue_pago', 'estornado')))
           order by (a.estado = 'pendente') desc, a.criado_em desc)
      from pagamentos_antecipados a
      join pedidos p on p.id = a.pedido_id
      join clientes c on c.id = a.cliente_id
      left join pedidos_grupo g on g.id = p.grupo_id
      left join cozinhas cz on cz.id = p.cozinha_id
     where a.estado = 'pendente' or a.criado_em > now() - interval '30 days'), '[]'::jsonb);
end $$;
revoke execute on function pagamentos_antes_lista() from public, anon;
grant execute on function pagamentos_antes_lista() to authenticated;

-- Confirmar (o dinheiro está na conta) ou rejeitar (com o motivo, que o cliente vê)
create or replace function decidir_pagamento_antes(p_id uuid, p_confirmar boolean, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  a pagamentos_antecipados;
  p pedidos;
  v integer;
begin
  if not tem_permissao('financas.acertos') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.acertos';
  end if;
  select * into a from pagamentos_antecipados where id = p_id for update;
  if not found or a.estado <> 'pendente' then raise exception 'pagamento_ja_decidido' using errcode = 'P0001'; end if;
  if not p_confirmar then
    if coalesce(trim(p_motivo), '') = '' then raise exception 'motivo_obrigatorio' using errcode = 'P0001'; end if;
    update pagamentos_antecipados
       set estado = 'rejeitado', motivo = trim(p_motivo), decidido_em = now(), decidido_por = funcionario_actual(),
           atualizado_em = now()
     where id = a.id;
    perform registar_auditoria('pagamento_antes_rejeitado', 'pedidos', a.pedido_id,
      jsonb_build_object('pagamento_id', a.id, 'motivo', trim(p_motivo)));
    return;
  end if;
  select * into p from pedidos where id = a.pedido_id for update;
  if p.estado not in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega') then
    raise exception 'pedido_ja_fechado' using errcode = 'P0001',
      detail = 'O pedido já foi entregue ou cancelado: devolve o dinheiro ao cliente.';
  end if;
  if exists (select 1 from comprovativos_pagamento where referencia_chave = a.referencia_chave and deletado_em is null) then
    raise exception 'referencia_ja_usada' using errcode = 'P0001';
  end if;
  v := least(a.valor, pedido_falta_pagar(p));
  if v <= 0 then raise exception 'pedido_ja_pago' using errcode = 'P0001'; end if;
  update pedidos set pago_antes = pago_antes + v, atualizado_em = now() where id = p.id;
  update pagamentos_antecipados
     set estado = 'confirmado', valor = v, decidido_em = now(), decidido_por = funcionario_actual(), atualizado_em = now()
   where id = a.id;
  perform registar_auditoria('pagamento_antes_confirmado', 'pedidos', a.pedido_id,
    jsonb_build_object('pagamento_id', a.id, 'valor', v, 'referencia', a.referencia));
end $$;
revoke execute on function decidir_pagamento_antes(uuid, boolean, text) from public, anon;
grant execute on function decidir_pagamento_antes(uuid, boolean, text) to authenticated;

-- Dinheiro devolvido ao cliente (pedido cancelado, ou pago também na entrega)
create or replace function devolver_pagamento_antes(p_id uuid, p_referencia text) returns void
language plpgsql security definer set search_path = public as $$
declare
  a pagamentos_antecipados;
  p pedidos;
begin
  if not tem_permissao('financas.acertos') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'financas.acertos';
  end if;
  select * into a from pagamentos_antecipados where id = p_id for update;
  if not found then raise exception 'pagamento_inexistente' using errcode = 'P0001'; end if;
  select * into p from pedidos where id = a.pedido_id;
  if not ((a.estado = 'confirmado' and p.estado = 'cancelado')
          or (a.estado = 'pendente' and p.estado in ('cancelado', 'entregue_pago', 'estornado'))) then
    raise exception 'nada_a_devolver' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_referencia), '') = '' then raise exception 'referencia_invalida' using errcode = 'P0001'; end if;
  update pagamentos_antecipados
     set estado = 'devolvido', devolvido_ref = trim(p_referencia), decidido_em = now(),
         decidido_por = funcionario_actual(), atualizado_em = now()
   where id = a.id;
  perform registar_auditoria('pagamento_antes_devolvido', 'pedidos', a.pedido_id,
    jsonb_build_object('pagamento_id', a.id, 'valor', a.valor, 'referencia', trim(p_referencia)));
end $$;
revoke execute on function devolver_pagamento_antes(uuid, text) from public, anon;
grant execute on function devolver_pagamento_antes(uuid, text) to authenticated;

-- ------------------------------------------------------------------ 3. o que já foi pago antes conta em todo o lado
do $$
declare
  f      text;
  v_def  text;
  v_novo text;
  par    text[];
  regras jsonb := jsonb_build_array(
    -- protecção da coluna e regra 7 (parcelas + crédito + pacote + pago antes = valor final)
    jsonb_build_array('pedidos_antes_actualizar()', 'new.pago_pacote := old.pago_pacote;',
                      'new.pago_pacote := old.pago_pacote;' || chr(10) || '    new.pago_antes := old.pago_antes;'),
    jsonb_build_array('pedidos_antes_actualizar()', 'if v_soma + new.credito_indicacao_usado + new.pago_pacote',
                      'if v_soma + new.credito_indicacao_usado + new.pago_pacote + new.pago_antes'),
    jsonb_build_array('pedidos_antes_actualizar()', 'detail = (v_soma + new.credito_indicacao_usado + new.pago_pacote)::text',
                      'detail = (v_soma + new.credito_indicacao_usado + new.pago_pacote + new.pago_antes)::text'),
    jsonb_build_array('pedidos_proteger_insercao()', 'new.pago_pacote := 0;',
                      'new.pago_pacote := 0;' || chr(10) || '  new.pago_antes := 0;'),
    -- quanto o estafeta cobra
    jsonb_build_array('pedidos_operador()', '- x.pago_pacote - x.valor_empresa)', '- x.pago_pacote - x.pago_antes - x.valor_empresa)'),
    jsonb_build_array('agendados_operador(date,date,uuid)', '- x.pago_pacote - x.valor_empresa)', '- x.pago_pacote - x.pago_antes - x.valor_empresa)'),
    jsonb_build_array('pedidos_agendados()', '- x.pago_pacote - x.valor_empresa)', '- x.pago_pacote - x.pago_antes - x.valor_empresa)'),
    jsonb_build_array('entregas_feitas_hoje()', '- p.pago_pacote - p.valor_empresa)', '- p.pago_pacote - p.pago_antes - p.valor_empresa)'),
    jsonb_build_array('grupos_operador(date)', '- x.pago_pacote)::int', '- x.pago_pacote - x.pago_antes)::int'),
    jsonb_build_array('grupos_operador(date)', '- x.pago_pacote), 0)::int', '- x.pago_pacote - x.pago_antes), 0)::int'),
    jsonb_build_array('grupos_operador(date)', '''modo_pagamento'', g.modo_pagamento,', '''modo_pagamento'', g.modo_pagamento, ''tipo'', g.tipo,'),
    jsonb_build_array('grupo_detalhe(text)', '''modo_pagamento'', g.modo_pagamento,', '''modo_pagamento'', g.modo_pagamento, ''tipo'', g.tipo,'),
    jsonb_build_array('usar_credito(uuid,integer)', '- ped.pago_pacote then', '- ped.pago_pacote - ped.pago_antes then'),
    -- a venda leva a parte paga antes como forma de pagamento (não é dinheiro da caixa)
    jsonb_build_array('gerar_venda_pedido()', '    || case when new.valor_empresa > 0',
                      '    || case when new.pago_antes > 0' || chr(10)
                      || '            then jsonb_build_array(jsonb_build_object(''metodo'', ''Pago antes'', ''valor'', new.pago_antes))' || chr(10)
                      || '            else ''[]''::jsonb end' || chr(10)
                      || '    || case when new.valor_empresa > 0'),
    -- acertos: a plataforma recebeu este dinheiro (como nos pacotes)
    jsonb_build_array('acerto_valores_pedido(pedidos,integer)', 'coalesce(p.pago_pacote, 0)::int as pacote,',
                      '(coalesce(p.pago_pacote, 0) + coalesce(p.pago_antes, 0))::int as pacote,')
  );
  r jsonb;
begin
  for r in select * from jsonb_array_elements(regras) loop
    f := r ->> 0;
    v_def := pg_get_functiondef(f::regprocedure);
    if position(r ->> 2 in v_def) > 0 then continue; end if; -- já aplicado
    v_novo := replace(v_def, r ->> 1, r ->> 2);
    if v_novo = v_def then raise exception '% não tem o formato esperado (%)', f, r ->> 1; end if;
    execute v_novo;
  end loop;
end $$;
