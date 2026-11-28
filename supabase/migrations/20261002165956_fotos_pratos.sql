-- Fotos dos pratos e das cozinhas: bucket público `fotos-pratos` (os clientes vêem as fotos
-- sem sessão nem URL assinada). Só quem tem cozinhas.gerir envia, troca ou apaga.
-- Caminhos: pratos/<cardapio_id>/<ficheiro>.jpg e cozinhas/<cozinha_id>/<ficheiro>.jpg.
-- O endereço público fica em cardapio.foto_url / cozinhas.foto_url.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos-pratos', 'fotos-pratos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

-- Caminho válido: pratos/<id de um prato> ou cozinhas/<id de uma cozinha>, seguido do ficheiro
-- (SECURITY INVOKER: só é usada nas políticas de escrita, por quem já tem cozinhas.gerir)
create or replace function foto_prato_caminho_valido(p_nome text) returns boolean
language sql stable set search_path = public as $$
  select case split_part(p_nome, '/', 1)
           when 'pratos' then exists (select 1 from cardapio c where c.id::text = split_part(p_nome, '/', 2))
           when 'cozinhas' then exists (select 1 from cozinhas c where c.id::text = split_part(p_nome, '/', 2))
           else false
         end
     and split_part(p_nome, '/', 3) ~ '^[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$'
     and split_part(p_nome, '/', 4) = '';
$$;
revoke execute on function foto_prato_caminho_valido(text) from public, anon;
grant execute on function foto_prato_caminho_valido(text) to authenticated;

create policy fotos_pratos_ler on storage.objects for select to anon, authenticated
  using (bucket_id = 'fotos-pratos');
create policy fotos_pratos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos-pratos' and tem_permissao('cozinhas.gerir') and foto_prato_caminho_valido(name));
create policy fotos_pratos_trocar on storage.objects for update to authenticated
  using (bucket_id = 'fotos-pratos' and tem_permissao('cozinhas.gerir'))
  with check (bucket_id = 'fotos-pratos' and tem_permissao('cozinhas.gerir') and foto_prato_caminho_valido(name));
create policy fotos_pratos_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos-pratos' and tem_permissao('cozinhas.gerir'));
