-- Preços no formato "preço riscado": para a morada do cliente, devolve o preço com a campanha
-- de cada prato de uma cozinha (só quando uma campanha activa o baixa já com 1 unidade, tal como
-- o servidor cobra no pedido) e o valor a partir do qual a entrega é grátis nessa zona.
-- Não há "preço antigo" manual: o riscado só aparece com uma campanha verdadeira.
create or replace function precos_para_mim(p_ponto uuid, p_cozinha uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cli  uuid := cliente_actual();
  v_zona uuid;
  v_pratos jsonb := '[]'::jsonb;
  r      record;
  c      jsonb;
begin
  if v_cli is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  select pe.zona_id into v_zona
    from pontos_entrega pe
    join enderecos_cliente ec on ec.ponto_entrega_id = pe.id and ec.cliente_id = v_cli and ec.deletado_em is null
   where pe.id = p_ponto;
  if not found then
    return jsonb_build_object('entrega_gratis_acima', null, 'pratos', '[]'::jsonb);
  end if;
  for r in select id, preco from cardapio
            where cozinha_id = p_cozinha and deletado_em is null and disponivel and visivel_online loop
    c := aplicar_campanha(jsonb_build_array(jsonb_build_object('cardapio_id', r.id, 'qtd', 1, 'preco_unitario', r.preco)),
                          p_cozinha, v_zona, p_ponto, v_cli);
    if c is not null and ((c -> 'itens' -> 0 ->> 'preco_unitario')::int < r.preco) then
      v_pratos := v_pratos || jsonb_build_object('cardapio_id', r.id, 'preco', r.preco,
                                                 'preco_campanha', (c -> 'itens' -> 0 ->> 'preco_unitario')::int,
                                                 'campanha', c ->> 'nome');
    end if;
  end loop;
  return jsonb_build_object('entrega_gratis_acima', limiar_entrega_gratis(v_zona), 'pratos', v_pratos);
end $$;
revoke execute on function precos_para_mim(uuid, uuid) from public, anon;
grant execute on function precos_para_mim(uuid, uuid) to authenticated;
