-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I2 · Desconto limitado ao valor do pedido
--
-- O desconto de indicação (valor garantido da ligação) nunca passa o valor do
-- pedido (subtotal + taxa de entrega): o valor final nunca fica negativo.
-- O desconto é de uso único: num pedido mais pequeno do que o desconto, a parte
-- que sobra não passa para o pedido seguinte (desconto_usado fica true quando o
-- pedido é entregue e pago, como até aqui).
--   1. calcular_desconto_indicacao (before insert on pedidos): limita o desconto.
--   2. orcamento_pedido: o orçamento mostra o desconto já limitado.
-- =============================================================================

-- 1. Desconto no pedido (6.4), limitado ao valor do pedido
create or replace function calcular_desconto_indicacao() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g pedidos_grupo;
begin
  if new.grupo_id is not null then
    g := grupo_para_adesao(new.grupo_id);
    new.ponto_entrega_id := g.ponto_entrega_id;
    new.cozinha_id := g.cozinha_id;
  end if;

  if new.cozinha_id is null then
    new.cozinha_id := cozinha_padrao();
  end if;

  -- O servidor ignora qualquer valor enviado pela app e recalcula
  select d.valor into new.desconto_indicacao
    from avaliar_desconto_indicacao(new.cliente_id, new.ponto_entrega_id) d;
  -- Nunca mais do que o valor do pedido: o valor final não fica negativo
  new.desconto_indicacao := least(coalesce(new.desconto_indicacao, 0),
                                  greatest(coalesce(new.subtotal, 0) + coalesce(new.taxa_entrega, 0), 0));
  return new;
end $$;

-- 2. Orçamento do checkout com o desconto já limitado
create or replace function orcamento_pedido(p_itens jsonb, p_ponto_entrega uuid,
                                            p_cozinha uuid default null, p_grupo uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_cliente  uuid := cliente_actual();
  v_cozinha  uuid := case when funcionalidade_activa('multi_cozinha')
                          then coalesce(p_cozinha, cozinha_padrao()) else cozinha_padrao() end;
  v_item     jsonb;
  v_qtd      numeric;
  v_card     cardapio;
  v_itens    jsonb := '[]';
  v_subtotal integer := 0;
  v_ponto    pontos_entrega;
  v_zona     zonas;
  v_taxa     integer := 0;
  v_desc     record;
  v_desconto integer;
begin
  if jsonb_typeof(p_itens) is distinct from 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'pedido_vazio' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_itens) > 30 then
    raise exception 'itens_a_mais' using errcode = 'P0001';
  end if;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    begin
      v_qtd := (v_item ->> 'qtd')::numeric;
      select * into v_card from cardapio
       where id = (v_item ->> 'cardapio_id')::uuid and deletado_em is null;
    exception when invalid_text_representation then
      raise exception 'item_indisponivel' using errcode = 'P0001';
    end;
    if v_qtd is null or v_qtd <> trunc(v_qtd) or v_qtd < 1 or v_qtd > 50 then
      raise exception 'quantidade_invalida' using errcode = 'P0001';
    end if;
    if v_card.id is null or not v_card.disponivel or v_card.cozinha_id <> v_cozinha then
      raise exception 'item_indisponivel' using errcode = 'P0001', detail = v_item ->> 'cardapio_id';
    end if;
    v_itens := v_itens || jsonb_strip_nulls(jsonb_build_object(
      'cardapio_id', v_card.id,
      'prato_base_id', v_card.prato_base_id,
      'nome', v_card.nome,
      'qtd', v_qtd::int,
      'preco_unitario', v_card.preco,
      'componentes_excluidos', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_excluidos', 'null') end,
      'componentes_ajustados', case when v_card.prato_base_id is not null
                                    then nullif(v_item -> 'componentes_ajustados', 'null') end));
    v_subtotal := v_subtotal + v_qtd::int * v_card.preco;
    v_card := null;
  end loop;

  -- Pedido de grupo: o ponto e a taxa são os do grupo (fase I6)
  if p_grupo is null then
    if p_ponto_entrega is null then
      raise exception 'ponto_obrigatorio' using errcode = 'P0001';
    end if;
    select * into v_ponto from pontos_entrega where id = p_ponto_entrega and deletado_em is null;
    if not found
       or (v_cliente is not null
           and v_ponto.criado_por_cliente is distinct from v_cliente
           and not exists (select 1 from enderecos_cliente e
                            where e.ponto_entrega_id = v_ponto.id and e.cliente_id = v_cliente
                              and e.deletado_em is null)) then
      raise exception 'ponto_invalido' using errcode = 'P0001';
    end if;
    select * into v_zona from zonas where id = v_ponto.zona_id and deletado_em is null;
    if not found then
      raise exception 'ponto_sem_zona' using errcode = 'P0001';
    end if;
    v_taxa := round(coalesce(v_zona.taxa, 0))::int;
  end if;

  select * into v_desc from avaliar_desconto_indicacao(v_cliente, p_ponto_entrega);
  -- O desconto nunca passa o valor do pedido (subtotal + taxa)
  v_desconto := least(coalesce(v_desc.valor, 0), v_subtotal + v_taxa);

  return jsonb_build_object(
    'itens', v_itens,
    'subtotal', v_subtotal,
    'zona_id', v_zona.id,
    'zona_nome', v_zona.nome,
    'taxa_entrega', v_taxa,
    'desconto', v_desconto,
    'motivo_desconto', v_desc.motivo,
    'total', v_subtotal + v_taxa - v_desconto);
end $$;

revoke execute on function calcular_desconto_indicacao() from public, anon, authenticated;
revoke execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) from public, anon;
grant execute on function orcamento_pedido(jsonb, uuid, uuid, uuid) to authenticated;
