-- =============================================================================
-- Fotos reais por opção do prato montável
-- -----------------------------------------------------------------------------
-- Cada opção (Funge, Arroz, Frango…) passa a poder ter uma foto própria, no mesmo
-- bucket público `fotos-pratos`, caminho opcoes/<opcao_id>/<ficheiro>. O operador
-- envia a foto (permissão cozinhas.gerir) e a app do cliente mostra-a no lugar do
-- emoji. Sem foto, continua o emoji automático.
-- =============================================================================

alter table opcoes add column if not exists foto_url text;

-- O caminho das fotos passa a aceitar também opcoes/<id de uma opção>.
-- (SECURITY INVOKER: só usada nas políticas de escrita do bucket, por cozinhas.gerir.)
create or replace function foto_prato_caminho_valido(p_nome text) returns boolean
language sql stable set search_path = public as $$
  select case split_part(p_nome, '/', 1)
           when 'pratos' then exists (select 1 from cardapio c where c.id::text = split_part(p_nome, '/', 2))
           when 'cozinhas' then exists (select 1 from cozinhas c where c.id::text = split_part(p_nome, '/', 2))
           when 'opcoes' then exists (select 1 from opcoes o where o.id::text = split_part(p_nome, '/', 2))
           else false
         end
     and split_part(p_nome, '/', 3) ~ '^[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$'
     and split_part(p_nome, '/', 4) = '';
$$;
revoke execute on function foto_prato_caminho_valido(text) from public, anon;
grant execute on function foto_prato_caminho_valido(text) to authenticated;
