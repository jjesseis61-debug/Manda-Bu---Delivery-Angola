-- =============================================================================
-- Visitante (passo 2): a taxa de entrega do bairro, antes de dar o número
-- -----------------------------------------------------------------------------
-- O visitante vê, ao escolher o bairro, quanto custa a entrega lá e a partir de quanto fica
-- grátis (a mesma taxa e o mesmo limiar que o orçamento usa). Tira a surpresa no fim.
-- É só o que o cliente já vê no carrinho; o orçamento do servidor continua a decidir.
-- =============================================================================

create or replace function visitante_zonas() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', z.id, 'nome', btrim(z.nome),
           'taxa', round(coalesce(z.taxa, 0))::int,
           'entrega_gratis_acima', limiar_entrega_gratis(z.id))
           order by z.nome), '[]'::jsonb)
    from zonas z
   where z.deletado_em is null;
$$;
revoke execute on function visitante_zonas() from public;
grant  execute on function visitante_zonas() to anon, authenticated;
