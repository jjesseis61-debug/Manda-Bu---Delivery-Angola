-- A cozinha acompanha o estafeta ao vivo: posição do estafeta de um pedido para a EQUIPA.
-- Espelho da posicao_entrega (que é só para o cliente dono), mas autorizada a quem gere a cozinha
-- do pedido ou ao próprio estafeta. Reutiliza posicoes_entregadores (já alimentada pelo estafeta).
create or replace function posicao_pedido(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ped  pedidos;
  v_dest pontos_entrega;
  v_pos  posicoes_entregadores;
  v_nome text;
  v_km   double precision;
begin
  select * into v_ped from pedidos where id = p_pedido and deletado_em is null;
  if not found then
    raise exception 'pedido_inexistente' using errcode = 'P0001';
  end if;
  -- Quem gere a cozinha do pedido, ou o próprio estafeta do pedido.
  if not (pode_na_cozinha('pedidos.gerir', v_ped.cozinha_id)
          or (funcionario_actual() is not null and v_ped.entregador_id = funcionario_actual())) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if not funcionalidade_activa('acompanhamento_entrega') or v_ped.estado <> 'em_entrega' then
    return jsonb_build_object('activo', false);
  end if;
  select split_part(trim(nome), ' ', 1) into v_nome from funcionarios where id = v_ped.entregador_id;
  select * into v_dest from pontos_entrega where id = v_ped.ponto_entrega_id;
  select * into v_pos from posicoes_entregadores
   where funcionario_id = v_ped.entregador_id and atualizado_em > now() - interval '10 minutes';
  if v_pos.id is null then
    return jsonb_build_object('activo', true, 'estafeta_nome', v_nome, 'estafeta', null,
                              'destino', jsonb_build_object('lat', v_dest.lat, 'lng', v_dest.lng));
  end if;
  if v_dest.lat is not null then
    v_km := distancia_km(v_pos.lat, v_pos.lng, v_dest.lat, v_dest.lng);
  end if;
  return jsonb_build_object(
    'activo', true,
    'estafeta_nome', v_nome,
    'estafeta', jsonb_build_object('lat', v_pos.lat, 'lng', v_pos.lng, 'actualizado_em', v_pos.atualizado_em),
    'destino', jsonb_build_object('lat', v_dest.lat, 'lng', v_dest.lng),
    'distancia_km', case when v_km is not null then round(v_km::numeric, 1) end,
    'minutos', case when v_km is not null then greatest(1, ceil(v_km * 1.4 / 25 * 60))::int end);
end $$;
revoke execute on function posicao_pedido(uuid) from public, anon;
grant  execute on function posicao_pedido(uuid) to authenticated;
