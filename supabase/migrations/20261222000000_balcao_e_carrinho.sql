-- Balcão certo e carrinho sem surpresas:
--  1. Balcões perto de uma posição (GPS «perto de mim»), como cozinhas_perto mas com lat/lng.
--  2. Pedido agendado: o prato tem de estar à venda à hora da entrega (antes via-se a hora do pedido).
--  3. Pratos fora do horário: quando voltam (próxima abertura nos 7 dias), para o cardápio o dizer
--     em vez de os esconder sem explicação.
--  4. Moradas: o mesmo ponto de entrega não fica guardado duas vezes no mesmo cliente
--     (limpa as repetidas, fica a principal ou a mais antiga).

-- ------------------------------------------------------------------ 1. perto de mim
create or replace function cozinhas_perto_de(p_lat numeric, p_lng numeric)
returns table (cozinha_id uuid, nome text, publica boolean, foto_url text, historia text,
               pratos integer, distancia_km numeric)
language sql stable security definer set search_path = public as $$
  select c.id, c.nome,
         c.consentimento_publico and funcionalidade_activa('perfil_cozinha'),
         case when c.consentimento_publico and funcionalidade_activa('perfil_cozinha') then c.foto_url end,
         case when c.consentimento_publico and funcionalidade_activa('perfil_cozinha') then c.historia end,
         (select count(*)::int from cardapio m where m.cozinha_id = c.id and m.disponivel and m.deletado_em is null),
         case when cl.lat is not null then
           round((6371 * acos(least(1, greatest(-1,
             cos(radians(p_lat)) * cos(radians(cl.lat)) * cos(radians(cl.lng) - radians(p_lng))
             + sin(radians(p_lat)) * sin(radians(cl.lat))))))::numeric, 1)
         end as distancia_km
    from cozinhas c
    left join cozinhas_localizacao cl on cl.cozinha_id = c.id and cl.deletado_em is null
   where cliente_actual() is not null and cozinha_aceita_pedidos(c.id)
     and p_lat between -90 and 90 and p_lng between -180 and 180
   order by distancia_km asc nulls last, c.id = cozinha_padrao() desc, c.nome;
$$;
revoke execute on function cozinhas_perto_de(numeric, numeric) from public, anon;
grant  execute on function cozinhas_perto_de(numeric, numeric) to authenticated;

-- ------------------------------------------------------------------ 2. janela à hora da entrega
create or replace function cardapio_fora_da_janela_em(p_id uuid, p_quando timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select not cardapio_aberto_em(p_id, coalesce(p_quando, now()));
$$;
revoke execute on function cardapio_fora_da_janela_em(uuid, timestamptz) from public, anon;
grant  execute on function cardapio_fora_da_janela_em(uuid, timestamptz) to authenticated;

create or replace function pedidos_validar_janela() returns trigger
language plpgsql set search_path = public as $$
declare
  it jsonb;
begin
  if e_escrita_cliente() then
    for it in select * from jsonb_array_elements(coalesce(new.itens, '[]'::jsonb)) loop
      -- Agendado: conta a hora da entrega (o prato tem de estar à venda nessa altura); senão, agora
      if cardapio_fora_da_janela_em((it ->> 'cardapio_id')::uuid, new.agendado_para) then
        raise exception 'item_indisponivel' using errcode = 'P0001', detail = it ->> 'cardapio_id';
      end if;
    end loop;
  end if;
  return new;
end $$;
revoke execute on function pedidos_validar_janela() from public, anon, authenticated;

-- ------------------------------------------------------------------ 3. quando volta
-- Próxima abertura de um prato (nos próximos 7 dias), ou null se estiver aberto ou sem horário previsto
create or replace function cardapio_proxima_abertura(p_id uuid) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  v_de timestamptz; v_ate timestamptz;
  v_hoje date := (now() at time zone 'Africa/Luanda')::date;
  v_prox timestamptz;
begin
  if cardapio_aberto_agora(p_id) then return null; end if;
  select disponivel_de, disponivel_ate into v_de, v_ate from cardapio where id = p_id;
  -- Janela de datas que ainda vai abrir
  if v_de is not null and v_de > now() and (v_ate is null or v_ate > v_de) then
    v_prox := v_de;
  end if;
  -- Horários semanais ou de um dia: o primeiro início a seguir a agora
  select least(v_prox, min(x.inicio)) into v_prox
    from (select ((d::date + h.hora_inicio) at time zone 'Africa/Luanda') as inicio
            from cardapio_horarios h
            cross join generate_series(v_hoje, v_hoje + 7, interval '1 day') d
           where h.cardapio_id = p_id
             and ((h.dia_semana is not null and h.dia_semana = extract(isodow from d)::int)
                  or (h.data is not null and h.data = d::date))) x
   where x.inicio > now();
  return v_prox;
end $$;
revoke execute on function cardapio_proxima_abertura(uuid) from public, anon, authenticated;

-- Pratos do balcão que estão fora do horário agora mas voltam nos próximos 7 dias
create or replace function cardapio_mais_tarde(p_cozinha uuid)
returns table (cardapio_id uuid, nome text, preco numeric, foto_url text, categoria text, proxima timestamptz)
language sql stable security definer set search_path = public as $$
  select m.id, m.nome, m.preco, m.foto_url, m.categoria, x.proxima
    from cardapio m
    cross join lateral (select cardapio_proxima_abertura(m.id) as proxima) x
   where cliente_actual() is not null
     and m.cozinha_id = p_cozinha and m.deletado_em is null and m.disponivel and m.visivel_online
     and not cardapio_aberto_agora(m.id)
     and x.proxima is not null
   order by x.proxima, m.nome
   limit 20;
$$;
revoke execute on function cardapio_mais_tarde(uuid) from public, anon;
grant  execute on function cardapio_mais_tarde(uuid) to authenticated;

-- ------------------------------------------------------------------ 4. moradas sem repetições
-- Fica uma por (cliente, ponto): a principal, senão a mais antiga; as outras são apagadas (reversível)
with ordenadas as (
  select id, row_number() over (partition by cliente_id, ponto_entrega_id
                                order by principal desc, criado_em, id) as n
    from enderecos_cliente
   where deletado_em is null
)
update enderecos_cliente e set deletado_em = now()
  from ordenadas o
 where o.id = e.id and o.n > 1;

create unique index if not exists enderecos_cliente_ponto_unico
  on enderecos_cliente (cliente_id, ponto_entrega_id) where deletado_em is null;
