-- Gestão do caixa na app do operador (abrir, sangrias, fecho com contagem).
-- A tabela `caixa` vem do modelo base, mas nenhuma app a abria: sem caixa aberta não se marca
-- "entregue e pago" (regra 8) nem se confirma um pacote pago na loja. Quem tem vendas.registar
-- na cozinha abre e fecha a caixa (a permissão já diz "abrir e fechar a caixa").
--
-- Regras:
--  * Uma caixa aberta por posto e cozinha (a de ontem por fechar tem de ser fechada primeiro).
--  * O caixa físico só soma a parcela Dinheiro das vendas (regras de negócio, secção 7),
--    mais os pacotes pagos na loja, menos as sangrias.
--  * No fecho guarda-se o resumo, o valor contado e a diferença; a caixa fechada não muda.

-- Quem regista vendas também tem de ver as caixas (até aqui só entregas/pedidos as viam)
alter policy ler on caixa using (
  deletado_em is null
  and (tem_permissao('vendas.registar') or tem_permissao('entregas.registar') or tem_permissao('pedidos.gerir')));

-- Caixa fechada não muda (nem por escrita directa na tabela)
alter policy editar on caixa
  using (fechamento is null
         and (pode_na_cozinha('vendas.registar', cozinha_id) or pode_na_cozinha('entregas.registar', cozinha_id)))
  with check (pode_na_cozinha('vendas.registar', cozinha_id) or pode_na_cozinha('entregas.registar', cozinha_id));

-- Caixa para gerir: existe, é de uma cozinha onde o funcionário tem vendas.registar, e (se pedido) está aberta
create or replace function caixa_para_gerir(p_caixa uuid, p_aberta boolean default true) returns caixa
language plpgsql stable security definer set search_path = public as $$
declare
  c caixa;
begin
  select * into c from caixa where id = p_caixa and deletado_em is null;
  if not found then raise exception 'caixa_inexistente' using errcode = 'P0001'; end if;
  if not pode_na_cozinha('vendas.registar', c.cozinha_id) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'vendas.registar';
  end if;
  if p_aberta and c.fechamento is not null then raise exception 'caixa_fechada' using errcode = 'P0001'; end if;
  return c;
end $$;
revoke execute on function caixa_para_gerir(uuid, boolean) from public, anon, authenticated;

create or replace function abrir_caixa(p_cozinha uuid, p_posto text, p_troco numeric default 0) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_func  uuid := exigir_permissao('vendas.registar');
  v_posto text := trim(coalesce(p_posto, ''));
  v_id    uuid;
begin
  if p_cozinha is null or not exists (select 1 from cozinhas where id = p_cozinha and deletado_em is null) then
    raise exception 'cozinha_inexistente' using errcode = 'P0001';
  end if;
  if not pode_na_cozinha('vendas.registar', p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'vendas.registar';
  end if;
  if length(v_posto) not between 1 and 40 then raise exception 'posto_invalido' using errcode = 'P0001'; end if;
  if p_troco is null or p_troco < 0 or p_troco > 100000000 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('caixa:' || p_cozinha || ':' || lower(v_posto)));
  if exists (select 1 from caixa where cozinha_id = p_cozinha and lower(posto) = lower(v_posto)
                and fechamento is null and deletado_em is null) then
    raise exception 'caixa_ja_aberta' using errcode = 'P0001';
  end if;
  insert into caixa (dispositivo_id, posto, data, troco_inicial, sangrias, funcionario_id, funcionario_nome, cozinha_id)
  values ('servidor', v_posto, hoje_luanda(), p_troco, '[]'::jsonb, v_func,
          (select nome from funcionarios where id = v_func), p_cozinha)
  returning id into v_id;
  perform registar_auditoria('caixa_aberta', 'caixa', v_id, jsonb_build_object('posto', v_posto, 'troco_inicial', p_troco));
  return v_id;
end $$;

-- Dinheiro que devia estar na caixa: troco + parcelas Dinheiro das vendas + pacotes pagos na loja − sangrias
create or replace function resumo_caixa(p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c        caixa := caixa_para_gerir(p_caixa, false);
  v_vendas numeric;
  v_pedidos int;
  v_pac    numeric;
  v_npac   int;
  v_sang   numeric;
begin
  select coalesce(sum((p ->> 'valor')::numeric), 0), count(distinct v.pedido_id)
    into v_vendas, v_pedidos
    from vendas v cross join lateral jsonb_array_elements(v.parcelas) p
   where v.caixa_id = c.id and v.deletado_em is null and p ->> 'metodo' = 'Dinheiro';
  select coalesce(sum(preco), 0), count(*) into v_pac, v_npac
    from adesoes_pacote
   where caixa_id = c.id and metodo = 'loja' and deletado_em is null and estado in ('activa', 'reembolsada');
  select coalesce(sum((s ->> 'valor')::numeric), 0) into v_sang from jsonb_array_elements(c.sangrias) s;
  return jsonb_build_object(
    'caixa_id', c.id, 'posto', c.posto, 'data', c.data, 'cozinha_id', c.cozinha_id,
    'aberta_por', c.funcionario_nome, 'troco_inicial', coalesce(c.troco_inicial, 0),
    'dinheiro_vendas', v_vendas, 'pedidos', v_pedidos, 'dinheiro_pacotes', v_pac, 'pacotes', v_npac,
    'sangrias', v_sang, 'lista_sangrias', c.sangrias,
    'esperado', coalesce(c.troco_inicial, 0) + v_vendas + v_pac - v_sang,
    'fechamento', c.fechamento);
end $$;

create or replace function registar_sangria(p_caixa uuid, p_valor numeric, p_motivo text) returns numeric
language plpgsql security definer set search_path = public as $$
declare
  v_func   uuid := exigir_permissao('vendas.registar');
  c        caixa;
  v_motivo text := trim(coalesce(p_motivo, ''));
begin
  perform caixa_para_gerir(p_caixa);
  select * into c from caixa where id = p_caixa for update;
  if c.fechamento is not null then raise exception 'caixa_fechada' using errcode = 'P0001'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > 100000000 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if length(v_motivo) not between 1 and 120 then raise exception 'motivo_obrigatorio' using errcode = 'P0001'; end if;
  update caixa
     set sangrias = sangrias || jsonb_build_array(jsonb_build_object(
           'valor', p_valor, 'motivo', v_motivo, 'em', now(), 'funcionario_id', v_func,
           'funcionario_nome', (select nome from funcionarios where id = v_func))),
         atualizado_em = now()
   where id = p_caixa;
  perform registar_auditoria('caixa_sangria', 'caixa', p_caixa, jsonb_build_object('valor', p_valor, 'motivo', v_motivo));
  return (select coalesce(sum((s ->> 'valor')::numeric), 0) from caixa, jsonb_array_elements(sangrias) s where id = p_caixa);
end $$;

create or replace function fechar_caixa(p_caixa uuid, p_contado numeric, p_observacao text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('vendas.registar');
  c      caixa;
  v_res  jsonb;
  v_fech jsonb;
begin
  perform caixa_para_gerir(p_caixa);
  select * into c from caixa where id = p_caixa for update;
  if c.fechamento is not null then raise exception 'caixa_fechada' using errcode = 'P0001'; end if;
  if p_contado is null or p_contado < 0 or p_contado > 100000000 then raise exception 'valor_invalido' using errcode = 'P0001'; end if;
  if p_observacao is not null and length(p_observacao) > 300 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  v_res := resumo_caixa(p_caixa);
  v_fech := (v_res - 'fechamento' - 'lista_sangrias' - 'caixa_id' - 'cozinha_id') || jsonb_build_object(
    'contado', p_contado, 'diferenca', p_contado - (v_res ->> 'esperado')::numeric,
    'fechado_em', now(), 'funcionario_id', v_func,
    'funcionario_nome', (select nome from funcionarios where id = v_func),
    'observacao', nullif(trim(p_observacao), ''));
  update caixa set fechamento = v_fech, atualizado_em = now() where id = p_caixa;
  perform registar_auditoria('caixa_fechada', 'caixa', p_caixa, v_fech);
  return v_fech;
end $$;

revoke execute on function abrir_caixa(uuid, text, numeric)       from public, anon;
revoke execute on function resumo_caixa(uuid)                     from public, anon;
revoke execute on function registar_sangria(uuid, numeric, text)  from public, anon;
revoke execute on function fechar_caixa(uuid, numeric, text)      from public, anon;
grant  execute on function abrir_caixa(uuid, text, numeric)       to authenticated;
grant  execute on function resumo_caixa(uuid)                     to authenticated;
grant  execute on function registar_sangria(uuid, numeric, text)  to authenticated;
grant  execute on function fechar_caixa(uuid, numeric, text)      to authenticated;
