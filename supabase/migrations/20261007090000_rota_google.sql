-- Gate B do mapa · Rota/ETA pelo Google (cirúrgico), com fallback total ao cálculo por distância.
--
-- Regra: sem o interruptor `rota_google` (desligado de origem) — ou sem a chave GOOGLE_ROTAS_API_KEY
-- na edge function `rota-estafeta` — o tempo continua a ser estimado pela distância em linha recta,
-- exactamente como antes. O Google entra só quando ligado E com chave; caso contrário, 100% estimativa.
--
-- Como funciona: a edge function (service role) calcula a rota por estrada com trânsito (Google
-- Directions), com limite de ritmo (throttle) e guarda em `rotas_estafeta`. O `posicao_entrega` usa
-- esse valor enquanto for recente (< 2 min) e cai na estimativa quando não existir. A chave vive só
-- no servidor (secret), nunca no telemóvel, por isso ligar/desligar não precisa de APK novo.

insert into funcionalidades (chave, activa, dispositivo_id) values ('rota_google', false, 'servidor')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- Cache da rota por pedido (só o serviço escreve; o cliente lê via posicao_entrega)
-- -----------------------------------------------------------------------------
create table rotas_estafeta (
  pedido_id      uuid primary key references pedidos(id) on delete cascade,
  minutos        integer not null check (minutos > 0),
  km             double precision check (km is null or km >= 0),
  polyline       text,
  atualizado_em  timestamptz not null default now()
);
comment on table rotas_estafeta is
  'Cache da rota/ETA por estrada (Google Directions), escrita pela edge function rota-estafeta (service role). Lida por posicao_entrega enquanto recente (< 2 min).';
alter table rotas_estafeta enable row level security;
revoke all on rotas_estafeta from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Limpar a rota quando o pedido deixa de estar a caminho (recria o trigger do I11,
-- mantendo o comportamento de parar o acompanhamento do estafeta)
-- -----------------------------------------------------------------------------
create or replace function pedidos_parar_acompanhamento() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.estado = 'em_entrega' and new.estado is distinct from 'em_entrega' then
    delete from rotas_estafeta where pedido_id = new.id;
    if old.entregador_id is not null
       and not exists (select 1 from pedidos p where p.entregador_id = old.entregador_id
                          and p.estado = 'em_entrega' and p.deletado_em is null and p.id <> new.id) then
      delete from posicoes_entregadores where funcionario_id = old.entregador_id;
    end if;
  end if;
  return new;
end $$;
revoke execute on function pedidos_parar_acompanhamento() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- posicao_entrega: prefere a rota por estrada (recente) quando `rota_google` está ligado;
-- senão usa a estimativa por distância. Devolve `fonte` ('google' | 'estimativa') e `polyline`.
-- -----------------------------------------------------------------------------
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
begin
  select * into v_ped from pedidos
   where id = p_pedido and cliente_id = cliente_actual() and cliente_actual() is not null and deletado_em is null;
  if not found then
    raise exception 'pedido_inexistente' using errcode = 'P0001';
  end if;
  if not funcionalidade_activa('acompanhamento_entrega') or v_ped.estado <> 'em_entrega' then
    return jsonb_build_object('activo', false);
  end if;
  select * into v_dest from pontos_entrega where id = v_ped.ponto_entrega_id;
  select * into v_pos from posicoes_entregadores
   where funcionario_id = v_ped.entregador_id and atualizado_em > now() - interval '10 minutes';
  if v_pos.id is null then
    return jsonb_build_object('activo', true, 'estafeta', null,
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
    'estafeta', jsonb_build_object('lat', v_pos.lat, 'lng', v_pos.lng, 'actualizado_em', v_pos.atualizado_em),
    'destino', jsonb_build_object('lat', v_dest.lat, 'lng', v_dest.lng),
    'distancia_km', case when v_km is not null then round(v_km::numeric, 1) end,
    'minutos', v_min,
    'fonte', v_fonte,
    'polyline', v_poly);
end $$;
revoke execute on function posicao_entrega(uuid) from public, anon;
grant  execute on function posicao_entrega(uuid) to authenticated;
