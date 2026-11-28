-- =============================================================================
-- Visitante pela porta da frente (passo 1) — «Ver o cardápio primeiro» na página de entrada
-- -----------------------------------------------------------------------------
-- O visitante escolhe o bairro (zona de entrega) e vê as cozinhas que lhe podem servir, da mais
-- perto para a mais longe (pelo centro da zona, quando a zona o tem). Depois abre o cardápio da
-- cozinha com visitante_cardapio e só dá o número em «Pedir».
-- Só nomes de zonas e de cozinhas que já aparecem na app; nada de taxas internas, moradas ou contactos.
-- =============================================================================

create or replace function visitante_zonas() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'nome', btrim(z.nome)) order by z.nome), '[]'::jsonb)
    from zonas z
   where z.deletado_em is null;
$$;
revoke execute on function visitante_zonas() from public;
grant  execute on function visitante_zonas() to anon, authenticated;

/**
 * Cozinhas que aceitam pedidos (sem as de condomínio) e têm pratos visíveis na app.
 * Com zona com centro: ordenadas pela distância (km, arredondado); sem zona ou sem centro: a
 * cozinha principal primeiro e depois pelo nome. Foto e história só com o perfil público autorizado.
 */
create or replace function visitante_cozinhas(p_zona uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with z as (
    select centro_lat as lat, centro_lng as lng from zonas
     where id = p_zona and deletado_em is null and centro_lat is not null
  ), k as (
    select c.id, c.nome,
           c.consentimento_publico and funcionalidade_activa('perfil_cozinha') as publica,
           c.foto_url,
           (select count(*)::int from cardapio m where m.cozinha_id = c.id and prato_para_visitante(m.id)) as pratos,
           case when cl.lat is not null and z.lat is not null then
             round((6371 * acos(least(1, greatest(-1,
               cos(radians(z.lat)) * cos(radians(cl.lat)) * cos(radians(cl.lng) - radians(z.lng))
               + sin(radians(z.lat)) * sin(radians(cl.lat))))))::numeric, 1)
           end as distancia_km
      from cozinhas c
      left join cozinhas_localizacao cl on cl.cozinha_id = c.id and cl.deletado_em is null
      left join z on true
     where cozinha_aceita_pedidos(c.id) and condominio_da_cozinha(c.id) is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', k.id, 'nome', k.nome, 'pratos', k.pratos, 'distancia_km', k.distancia_km,
           'foto_url', case when k.publica then k.foto_url end)
           order by k.distancia_km asc nulls last, k.id = cozinha_padrao() desc, k.nome), '[]'::jsonb)
    from k
   where k.pratos > 0;
$$;
revoke execute on function visitante_cozinhas(uuid) from public;
grant  execute on function visitante_cozinhas(uuid) to anon, authenticated;
