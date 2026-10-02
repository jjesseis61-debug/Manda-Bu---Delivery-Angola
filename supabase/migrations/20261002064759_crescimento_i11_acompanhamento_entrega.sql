-- I11 · Acompanhamento da entrega em tempo real, como nas apps de táxi: enquanto o
-- pedido está "a caminho", a app do estafeta envia a posição e o cliente vê-o no
-- mapa com o tempo estimado de chegada. Interruptor `acompanhamento_entrega`.
--
-- Privacidade: guarda-se só a última posição de cada estafeta, apenas enquanto
-- tem pedidos a caminho (apaga-se quando o último é entregue ou cancelado), e o
-- cliente só a vê para o seu próprio pedido. Não há histórico de percursos.
-- O tempo estimado é uma aproximação pela distância (sem API de rotas paga).

insert into funcionalidades (chave, activa, dispositivo_id) values ('acompanhamento_entrega', false, 'servidor')
on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- 1. Quem leva o pedido: quem o marca "a caminho"
-- -----------------------------------------------------------------------------
alter table pedidos add column entregador_id uuid references funcionarios(id);
create index pedidos_entregador_idx on pedidos (entregador_id, estado);
comment on column pedidos.entregador_id is
  'Funcionário que marcou o pedido em_entrega (I11). Só o servidor escreve.';

create or replace function pedidos_registar_entregador() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.estado = 'em_entrega' and old.estado is distinct from 'em_entrega' then
    new.entregador_id := coalesce(funcionario_actual(), new.entregador_id);
  end if;
  return new;
end $$;

create trigger trg_pedidos_3_entregador before update on pedidos
for each row execute function pedidos_registar_entregador();

-- -----------------------------------------------------------------------------
-- 2. Última posição de cada estafeta (só servidor)
-- -----------------------------------------------------------------------------
create table posicoes_entregadores (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  funcionario_id   uuid not null unique references funcionarios(id),
  lat              double precision not null check (lat between -90 and 90),
  lng              double precision not null check (lng between -180 and 180),
  precisao         double precision check (precisao is null or precisao >= 0)
);
comment on table posicoes_entregadores is
  'Sincronização: Só servidor (registar_posicao_entrega); não sincroniza para o telemóvel. Última posição do estafeta, só durante entregas (I11).';
alter table posicoes_entregadores enable row level security;
revoke all on posicoes_entregadores from anon, authenticated;
create trigger trg_0_so_servidor before insert or update or delete on posicoes_entregadores
for each row execute function bloquear_escrita_dispositivo();

-- O estafeta deixa de ser seguido quando já não tem pedidos a caminho
create or replace function pedidos_parar_acompanhamento() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.estado = 'em_entrega' and new.estado is distinct from 'em_entrega' and old.entregador_id is not null
     and not exists (select 1 from pedidos p where p.entregador_id = old.entregador_id
                        and p.estado = 'em_entrega' and p.deletado_em is null and p.id <> new.id) then
    delete from posicoes_entregadores where funcionario_id = old.entregador_id;
  end if;
  return new;
end $$;

create trigger trg_pedidos_parar_acompanhamento after update on pedidos
for each row execute function pedidos_parar_acompanhamento();

-- -----------------------------------------------------------------------------
-- 3. API: o estafeta envia a posição; o cliente lê a do seu pedido
-- -----------------------------------------------------------------------------
-- Devolve quantos pedidos o estafeta tem a caminho (0 = a app pode parar de enviar)
create or replace function registar_posicao_entrega(p_lat double precision, p_lng double precision,
                                                    p_precisao double precision default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('entregas.registar');
  v_n    integer;
begin
  if not funcionalidade_activa('acompanhamento_entrega') then
    return 0;
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'posicao_invalida' using errcode = 'P0001';
  end if;
  select count(*)::int into v_n from pedidos
   where entregador_id = v_func and estado = 'em_entrega' and deletado_em is null;
  if v_n = 0 then
    delete from posicoes_entregadores where funcionario_id = v_func;
    return 0;
  end if;
  insert into posicoes_entregadores (funcionario_id, lat, lng, precisao, dispositivo_id)
  values (v_func, p_lat, p_lng, p_precisao, 'servidor')
  on conflict (funcionario_id) do update
     set lat = excluded.lat, lng = excluded.lng, precisao = excluded.precisao, atualizado_em = now();
  return v_n;
end $$;

-- Distância em km entre dois pontos (fórmula de haversine)
create or replace function distancia_km(lat1 double precision, lng1 double precision,
                                        lat2 double precision, lng2 double precision)
returns double precision language sql immutable set search_path = public as $$
  select 6371 * 2 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2)
                              + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

-- Para o cliente: posição do estafeta do SEU pedido, só enquanto está a caminho.
-- Tempo estimado: distância em linha recta × 1,4 (ruas) a 25 km/h, no mínimo 1 minuto.
create or replace function posicao_entrega(p_pedido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ped  pedidos;
  v_dest pontos_entrega;
  v_pos  posicoes_entregadores;
  v_km   double precision;
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
  end if;
  return jsonb_build_object(
    'activo', true,
    'estafeta', jsonb_build_object('lat', v_pos.lat, 'lng', v_pos.lng, 'actualizado_em', v_pos.atualizado_em),
    'destino', jsonb_build_object('lat', v_dest.lat, 'lng', v_dest.lng),
    'distancia_km', round(v_km::numeric, 1),
    'minutos', case when v_km is not null then greatest(1, ceil(v_km * 1.4 / 25 * 60))::int end);
end $$;

revoke execute on function pedidos_registar_entregador()  from public, anon, authenticated;
revoke execute on function pedidos_parar_acompanhamento() from public, anon, authenticated;
revoke execute on function distancia_km(double precision, double precision, double precision, double precision) from public, anon;
revoke execute on function registar_posicao_entrega(double precision, double precision, double precision) from public, anon;
revoke execute on function posicao_entrega(uuid) from public, anon;
grant  execute on function registar_posicao_entrega(double precision, double precision, double precision) to authenticated;
grant  execute on function posicao_entrega(uuid) to authenticated;
grant  execute on function distancia_km(double precision, double precision, double precision, double precision) to authenticated;
