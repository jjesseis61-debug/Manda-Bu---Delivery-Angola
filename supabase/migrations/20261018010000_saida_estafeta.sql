-- Saída para entrega confirmada pelo estafeta reservado + o cliente passa a ver o nome do estafeta.
--
-- Problema corrigido: ao entrar "em_entrega", o gatilho punha entregador_id := funcionario_actual().
-- Como o gerente não é bloqueado, quando o OPERADOR carregava "Saiu para entrega" ficava ele próprio
-- como entregador: a reserva do estafeta era limpa, o estafeta perdia o pedido da lista e o cliente
-- passaria a seguir a localização do operador. Agora, havendo reserva, o entregador é SEMPRE o estafeta
-- reservado (mesmo que um gerente carregue por ele numa excepção). Sem reserva (recolha directa no
-- balcão) mantém-se quem marcou.

-- Ajuste 1: ao entrar "em entrega", o entregador é o estafeta reservado (enquanto a reserva está
-- activa). Sem reserva, ou com a reserva já expirada, é quem marca a saída.
create or replace function pedidos_registar_entregador() returns trigger
language plpgsql set search_path = public as $$
declare
  v_reserva_activa boolean;
begin
  if new.estado = 'em_entrega' and old.estado is distinct from 'em_entrega' then
    v_reserva_activa := new.atribuido_a is not null
      and new.atribuido_em > now() - make_interval(mins => (select entrega_reserva_min from parametros where unico));
    if v_reserva_activa
       and new.atribuido_a is distinct from funcionario_actual()
       and not pode_na_cozinha('pedidos.gerir', new.cozinha_id) then
      raise exception 'reservado_a_outro' using errcode = '42501';
    end if;
    -- Reserva activa: o entregador é o estafeta reservado (não quem carrega o botão, por ex. um gerente).
    -- Sem reserva (ou reserva expirada): é quem marca a saída (recolha directa, ou quem pega o pedido caído).
    new.entregador_id := case when v_reserva_activa then new.atribuido_a
                              else coalesce(funcionario_actual(), new.entregador_id) end;
    new.atribuido_a := null;
    new.atribuido_em := null;
  end if;
  return new;
end $$;

-- Ajuste 3: a posição do estafeta do pedido do cliente passa a trazer o NOME do estafeta
-- (mostrado no cartão e no balão do mapa). O nome vem mesmo antes de haver localização, para o
-- cliente ver logo quem é. Mantém a rota por estrada (Google) e a estimativa por distância.
create or replace function posicao_entrega(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ped   pedidos;
  v_dest  pontos_entrega;
  v_pos   posicoes_entregadores;
  v_rota  rotas_estafeta;
  v_km    double precision;
  v_min   integer;
  v_fonte text := 'estimativa';
  v_poly  text;
  v_nome  text;
begin
  select * into v_ped from pedidos
   where id = p_pedido and cliente_id = cliente_actual() and cliente_actual() is not null and deletado_em is null;
  if not found then
    raise exception 'pedido_inexistente' using errcode = 'P0001';
  end if;
  if not funcionalidade_activa('acompanhamento_entrega') or v_ped.estado <> 'em_entrega' then
    return jsonb_build_object('activo', false);
  end if;
  select split_part(trim(nome), ' ', 1) into v_nome from funcionarios where id = v_ped.entregador_id;
  select * into v_dest from pontos_entrega where id = v_ped.ponto_entrega_id;
  select * into v_pos from posicoes_entregadores
   where funcionario_id = v_ped.entregador_id and atualizado_em > now() - interval '10 minutes';
  if v_pos.id is null then
    -- Ainda sem localização: dá o nome do estafeta à mesma (o ponto aparece quando ele partilhar).
    return jsonb_build_object('activo', true, 'estafeta_nome', v_nome, 'estafeta', null,
                              'destino', jsonb_build_object('lat', v_dest.lat, 'lng', v_dest.lng));
  end if;
  if v_dest.lat is not null then
    v_km := distancia_km(v_pos.lat, v_pos.lng, v_dest.lat, v_dest.lng);
    v_min := greatest(1, ceil(v_km * 1.4 / 25 * 60))::int;
  end if;
  -- Rota por estrada (Google), quando ligada e recente: substitui a estimativa
  if funcionalidade_activa('rota_google') then
    select * into v_rota from rotas_estafeta
     where pedido_id = v_ped.id and atualizado_em > now() - interval '2 minutes';
    if v_rota.pedido_id is not null then
      v_min := v_rota.minutos;
      v_km := coalesce(v_rota.km, v_km);
      v_poly := v_rota.polyline;
      v_fonte := 'google';
    end if;
  end if;
  return jsonb_build_object(
    'activo', true,
    'estafeta_nome', v_nome,
    'estafeta', jsonb_build_object('lat', v_pos.lat, 'lng', v_pos.lng, 'actualizado_em', v_pos.atualizado_em),
    'destino', jsonb_build_object('lat', v_dest.lat, 'lng', v_dest.lng),
    'distancia_km', case when v_km is not null then round(v_km::numeric, 1) end,
    'minutos', v_min,
    'fonte', v_fonte,
    'polyline', v_poly);
end $$;
revoke execute on function posicao_entrega(uuid) from public, anon;
grant  execute on function posicao_entrega(uuid) to authenticated;
