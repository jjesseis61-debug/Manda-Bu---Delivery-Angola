-- =============================================================================
-- Prato montável: o valor mínimo conta sobre o preço FINAL (#7)
-- -----------------------------------------------------------------------------
-- Até aqui o servidor verificava o mínimo sobre "prato + opções" (opcoes_do_item), mas depois
-- descontava os ingredientes que o cliente tirou — o preço final podia ficar abaixo do mínimo.
-- A app já verificava sobre o preço final (com os ingredientes tirados). Agora o servidor faz o
-- mesmo: depois de descontar os ingredientes, volta a verificar o mínimo.
-- Acrescenta-se a regra à função actual, sem a copiar.
-- =============================================================================
do $$
declare
  v_def  text := pg_get_functiondef('orcamento_pedido(jsonb, uuid, uuid, uuid)'::regprocedure);
  v_novo text;
begin
  if position('minimo_montavel' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def,
    '(v_preco := greatest\(v_preco - v_desc_comp, 0\);)',
    E'\\1\n      if coalesce(v_card.minimo_montavel, 0) > 0 and v_preco < v_card.minimo_montavel then raise exception ''abaixo_do_minimo'' using errcode = ''P0001'', detail = v_card.minimo_montavel::text; end if;');
  if v_novo = v_def then
    raise exception 'orcamento_pedido não tem o formato esperado';
  end if;
  execute v_novo;
end $$;
