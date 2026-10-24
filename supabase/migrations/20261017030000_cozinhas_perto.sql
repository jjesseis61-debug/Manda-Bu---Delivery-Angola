-- Fase 3 do seletor de zonas: ordenar os balcões pela distância ao ponto de entrega do cliente.
-- Recebe o ponto (não as coordenadas — ficam no servidor), resolve lat/lng e calcula a distância por
-- haversine. Mesmos campos e barreira de cozinhas_para_pedir; os balcões sem localização vão para o fim.

create or replace function cozinhas_perto(p_ponto uuid)
returns table (cozinha_id uuid, nome text, publica boolean, foto_url text, historia text,
               pratos integer, distancia_km numeric)
language sql stable security definer set search_path = public as $$
  with p as (
    select (select lat from pontos_entrega where id = p_ponto) as lat,
           (select lng from pontos_entrega where id = p_ponto) as lng
  )
  select c.id, c.nome,
         c.consentimento_publico and funcionalidade_activa('perfil_cozinha'),
         case when c.consentimento_publico and funcionalidade_activa('perfil_cozinha') then c.foto_url end,
         case when c.consentimento_publico and funcionalidade_activa('perfil_cozinha') then c.historia end,
         (select count(*)::int from cardapio m where m.cozinha_id = c.id and m.disponivel and m.deletado_em is null),
         case when cl.lat is not null and p.lat is not null then
           round((6371 * acos(least(1, greatest(-1,
             cos(radians(p.lat)) * cos(radians(cl.lat)) * cos(radians(cl.lng) - radians(p.lng))
             + sin(radians(p.lat)) * sin(radians(cl.lat))))))::numeric, 1)
         end as distancia_km
    from cozinhas c
    left join cozinhas_localizacao cl on cl.cozinha_id = c.id and cl.deletado_em is null
    cross join p
   where cliente_actual() is not null and cozinha_aceita_pedidos(c.id)
   order by distancia_km asc nulls last, c.id = cozinha_padrao() desc, c.nome;
$$;
revoke execute on function cozinhas_perto(uuid) from public, anon;
grant  execute on function cozinhas_perto(uuid) to authenticated;
