-- Correcção da trava das opções que contam o stock: quem tem conta de cliente e de funcionário
-- (dono, gerentes) também é travado quando pede para si próprio na app. Só os pedidos que a equipa
-- faz para outro cliente (operador) passam sem trava, como nas doses dos pratos.
create or replace function pedidos_unidades_opcoes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_rest integer;
begin
  -- Dentro desta função current_user é o dono (não serve e_escrita_cliente): conta o pedido feito para si próprio
  if cliente_actual() is null or new.cliente_id is distinct from cliente_actual() then return new; end if;
  -- As opções chegam como ids (app) ou já como objectos {id, nome, preco_extra}
  for r in select coalesce(e ->> 'id', e #>> '{}') as opcao_id, sum(coalesce((i ->> 'qtd')::int, 1)) as qtd
             from jsonb_array_elements(coalesce(new.itens, '[]')) i
             cross join jsonb_array_elements(coalesce(i -> 'opcoes', '[]')) e
            where coalesce(e ->> 'id', e #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            group by 1 loop
    perform 1 from opcoes where id = r.opcao_id::uuid and contar_stock for update;
    if found then
      v_rest := unidades_opcao(r.opcao_id::uuid);
      if v_rest is not null and v_rest < r.qtd then
        raise exception 'opcao_esgotada' using errcode = 'P0001',
          detail = (select nome from opcoes where id = r.opcao_id::uuid);
      end if;
    end if;
  end loop;
  return new;
end $$;
revoke execute on function pedidos_unidades_opcoes() from public, anon, authenticated;
