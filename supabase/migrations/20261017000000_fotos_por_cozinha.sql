-- 2.ª fase do cardápio por cozinha: FOTOS dos pratos e do perfil também por-cozinha.
-- O caminho no bucket é pratos/<cardapio_id>/… ou cozinhas/<cozinha_id>/…; resolvemos a cozinha a
-- partir do caminho e aplicamos a mesma regra: chave-mestra OU cardapio.gerir da própria cozinha.

create or replace function foto_prato_pode_gerir(p_nome text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_seg     text := split_part(p_nome, '/', 2);
  v_cozinha uuid;
begin
  if tem_permissao('cozinhas.gerir') then
    return true;
  end if;
  if v_seg !~ '^[0-9a-fA-F-]{36}$' then
    return false;
  end if;
  v_cozinha := case split_part(p_nome, '/', 1)
                 when 'cozinhas' then v_seg::uuid
                 when 'pratos'   then (select cozinha_id from cardapio where id = v_seg::uuid)
                 else null
               end;
  return v_cozinha is not null and pode_na_cozinha('cardapio.gerir', v_cozinha);
end $$;
revoke execute on function foto_prato_pode_gerir(text) from public, anon;
grant  execute on function foto_prato_pode_gerir(text) to authenticated;

-- Enviar / trocar / apagar fotos: chave-mestra OU gerente de cardápio da cozinha do caminho.
alter policy fotos_pratos_enviar on storage.objects
  with check (bucket_id = 'fotos-pratos' and foto_prato_pode_gerir(name) and foto_prato_caminho_valido(name));
alter policy fotos_pratos_trocar on storage.objects
  using (bucket_id = 'fotos-pratos' and foto_prato_pode_gerir(name))
  with check (bucket_id = 'fotos-pratos' and foto_prato_pode_gerir(name) and foto_prato_caminho_valido(name));
alter policy fotos_pratos_apagar on storage.objects
  using (bucket_id = 'fotos-pratos' and foto_prato_pode_gerir(name));
