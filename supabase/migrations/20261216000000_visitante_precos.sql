-- Preço riscado também para o visitante (quem ainda não entrou): só as campanhas para todos e as
-- do bairro escolhido (as de condomínio precisam da morada; os limites por cliente não se aplicam a
-- quem não tem conta). O preço é o mesmo que o servidor cobra no pedido por 1 unidade.
create or replace function visitante_precos(p_cozinha uuid, p_zona uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_zona uuid;
  v_pratos jsonb := '[]'::jsonb;
  r record;
  c jsonb;
begin
  select id into v_zona from zonas where id = p_zona and deletado_em is null;
  for r in select id, preco from cardapio
            where cozinha_id = p_cozinha and deletado_em is null and disponivel and visivel_online
            limit 300 loop
    c := aplicar_campanha(jsonb_build_array(jsonb_build_object('cardapio_id', r.id, 'qtd', 1, 'preco_unitario', r.preco)),
                          p_cozinha, v_zona, null, null);
    if c is not null and ((c -> 'itens' -> 0 ->> 'preco_unitario')::int < r.preco) then
      v_pratos := v_pratos || jsonb_build_object('cardapio_id', r.id, 'preco', r.preco,
                                                 'preco_campanha', (c -> 'itens' -> 0 ->> 'preco_unitario')::int,
                                                 'campanha', c ->> 'nome');
    end if;
  end loop;
  return jsonb_build_object('entrega_gratis_acima', case when v_zona is not null then limiar_entrega_gratis(v_zona) end,
                            'pratos', v_pratos);
end $$;
revoke execute on function visitante_precos(uuid, uuid) from public;
grant execute on function visitante_precos(uuid, uuid) to anon, authenticated;
