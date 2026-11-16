-- =============================================================================
-- Entrega grátis a partir de um valor
-- -----------------------------------------------------------------------------
-- Decisões do dono (16/11/2026):
--  * o valor conta DEPOIS dos descontos (subtotal − desconto de convite); a taxa de entrega não conta;
--  * o operador gere: um valor geral (parametros.entrega_gratis_acima, 0 = desligado) e, em cada zona,
--    zonas.entrega_gratis_acima: vazio = usa o valor geral; 0 = esta zona nunca tem entrega grátis;
--    > 0 = valor próprio desta zona.
-- Pedidos de grupo ficam de fora (a taxa da entrega única reparte-se no fecho do grupo).
-- O selo de frete grátis só se gasta quando a entrega ainda tem custo (não se perde num pedido já grátis).
-- =============================================================================

alter table parametros
  add column if not exists entrega_gratis_acima int not null default 0
    check (entrega_gratis_acima between 0 and 10000000);
comment on column parametros.entrega_gratis_acima is
  'Entrega grátis a partir deste valor (Kz, depois dos descontos, sem a taxa). 0 = desligado';

alter table zonas
  add column if not exists entrega_gratis_acima int
    check (entrega_gratis_acima is null or entrega_gratis_acima between 0 and 10000000);
comment on column zonas.entrega_gratis_acima is
  'Entrega grátis nesta zona: vazio = usa o valor geral (parametros); 0 = nunca; > 0 = a partir deste valor (Kz)';

-- Valor a partir do qual a entrega é grátis numa zona (null = sem entrega grátis)
create or replace function limiar_entrega_gratis(p_zona uuid)
returns int language sql stable security definer set search_path = public as $$
  select nullif(coalesce(z.entrega_gratis_acima, (select entrega_gratis_acima from parametros where unico), 0), 0)
    from zonas z where z.id = p_zona;
$$;
revoke execute on function limiar_entrega_gratis(uuid) from public, anon, authenticated;

-- orcamento_pedido: aplica a entrega grátis e devolve o que falta (acrescentado à definição actual, sem a copiar)
do $$
declare
  v_def  text := pg_get_functiondef('orcamento_pedido(jsonb,uuid,uuid,uuid)'::regprocedure);
  v_novo text;
begin
  if position('limiar_entrega_gratis' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(v_sem\s+text;)', E'\\1\n  v_limiar   integer;\n  v_gratis   boolean := false;');
  v_novo := regexp_replace(v_novo, '(\n\s*return\s+jsonb_build_object\(\s*''itens'')',
    E'\n  -- Entrega grátis a partir de um valor, contado depois dos descontos (o operador gere por zona)\n'
    || E'  if p_grupo is null then\n'
    || E'    v_limiar := limiar_entrega_gratis(v_zona.id);\n'
    || E'    if v_limiar is not null and v_taxa > 0 and v_subtotal - v_desconto >= v_limiar then\n'
    || E'      v_taxa := 0;\n'
    || E'      v_gratis := true;\n'
    || E'      v_desconto := least(v_desconto, v_subtotal);\n'
    || E'    end if;\n'
    || E'  end if;\n\\1');
  v_novo := regexp_replace(v_novo, '(''taxa_grupo_estimada''\s*,\s*v_estimada)\s*\)\s*;',
    E'\\1,\n    ''entrega_gratis'', v_gratis,\n'
    || E'    ''entrega_gratis_acima'', v_limiar,\n'
    || E'    ''falta_entrega_gratis'', case when v_limiar is not null and v_taxa > 0\n'
    || E'                                   then greatest(v_limiar - (v_subtotal - v_desconto), 0) end);');
  if position('v_limiar   integer' in v_novo) = 0 or position('v_gratis := true' in v_novo) = 0
     or position('''falta_entrega_gratis''' in v_novo) = 0 then
    raise exception 'orcamento_pedido não tem o formato esperado';
  end if;
  execute v_novo;
end $$;

-- Selo de frete grátis: não se gasta num pedido cuja entrega já é grátis
do $$
declare
  v_def  text := pg_get_functiondef('pedidos_aplicar_selo()'::regprocedure);
  v_novo text;
begin
  if position('taxa_entrega, 0) > 0' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(if\s+e_escrita_cliente\(\)\s+and\s+funcionalidade_activa\(''selos''\))',
                           E'\\1 and coalesce(new.taxa_entrega, 0) > 0');
  if v_novo = v_def then
    raise exception 'pedidos_aplicar_selo não tem o formato esperado';
  end if;
  execute v_novo;
end $$;
