-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I7 · Fotos nas avaliações
--
--   1. Bucket privado `fotos-avaliacoes` (só JPEG, até 5 MB). Cada foto tem uma linha
--      em fotos_avaliacao; o caminho do ficheiro é definido pelo servidor (<id>.jpg).
--   2. Envio: só o autor da avaliação, com o interruptor avaliacoes_fotos ligado, e só
--      para o caminho de uma foto sua ainda pendente. Até 2 fotos por avaliação (as
--      linhas sem ficheiro há mais de 15 minutos não contam).
--   3. Leitura dos ficheiros: fotos aprovadas (de avaliações não ocultas, com o
--      interruptor), as próprias e os moderadores. Pendentes e rejeitadas ficam
--      privadas.
--   4. Lista pública com as fotos aprovadas (lista_avaliacoes) e fila de moderação O7
--      (fotos_pendentes; aprovar/rejeitar com moderar_foto, já existente e auditada).
--
-- O interruptor avaliacoes_fotos não é ligado aqui.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Bucket privado
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos-avaliacoes', 'fotos-avaliacoes', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- 2. Envio
-- -----------------------------------------------------------------------------
-- Fotos que contam para o limite de 2: com ficheiro enviado, já moderadas, ou criadas
-- há menos de 15 minutos (envio em curso)
create or replace function fotos_da_avaliacao(p_avaliacao uuid) returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::int from fotos_avaliacao f
   where f.avaliacao_id = p_avaliacao and f.deletado_em is null
     and (f.estado <> 'pendente' or f.criado_em > now() - interval '15 minutes'
          or exists (select 1 from storage.objects o where o.bucket_id = 'fotos-avaliacoes' and o.name = f.caminho));
$$;

create or replace function fotos_antes_inserir() returns trigger
language plpgsql set search_path = public as $$
begin
  if fotos_da_avaliacao(new.avaliacao_id) >= 2 then
    raise exception 'limite_fotos' using errcode = 'P0001';
  end if;
  if e_escrita_cliente() then
    new.estado := 'pendente'; new.moderado_por := null; new.moderado_em := null;
    -- O caminho do ficheiro é do servidor: a app envia exactamente para este nome
    new.caminho := new.id::text || '.jpg';
  end if;
  return new;
end $$;

-- A app pode enviar este ficheiro? (política de INSERT do storage)
create or replace function foto_pode_enviar(p_caminho text) returns boolean
language sql stable security definer set search_path = public as $$
  select funcionalidade_activa('avaliacoes_fotos') and exists (
    select 1 from fotos_avaliacao f join avaliacoes a on a.id = f.avaliacao_id
     where f.caminho = p_caminho and f.estado = 'pendente' and f.deletado_em is null
       and a.cliente_id = cliente_actual() and a.deletado_em is null);
$$;

-- A sessão pode ler este ficheiro? (política de SELECT do storage)
create or replace function foto_pode_ver(p_caminho text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from fotos_avaliacao f join avaliacoes a on a.id = f.avaliacao_id
     where f.caminho = p_caminho and f.deletado_em is null and a.deletado_em is null
       and ((f.estado = 'aprovada' and not a.oculta and funcionalidade_activa('avaliacoes_fotos')
             and cliente_actual() is not null)
            or a.cliente_id = cliente_actual()
            or tem_permissao('avaliacoes.moderar')));
$$;

create policy fotos_avaliacoes_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos-avaliacoes' and foto_pode_enviar(name));
create policy fotos_avaliacoes_ler on storage.objects for select to authenticated
  using (bucket_id = 'fotos-avaliacoes' and foto_pode_ver(name));

-- -----------------------------------------------------------------------------
-- 3. Lista pública com as fotos aprovadas (C10)
-- -----------------------------------------------------------------------------
create or replace function lista_avaliacoes(p_cozinha uuid, p_prato uuid default null, p_limite integer default 30)
returns table (criado_em timestamptz, estrelas integer, comentario text, autor text, pratos jsonb, fotos text[])
language sql stable security definer set search_path = public as $$
  select a.criado_em, a.estrelas, a.comentario,
         nome_autor_avaliacao(a.cliente_id, a.usar_pseudonimo),
         coalesce((select jsonb_agg(jsonb_build_object('nome', pb.nome, 'estrelas', ap.estrelas) order by pb.nome)
                     from avaliacoes_pratos ap join pratos_base pb on pb.id = ap.prato_id
                    where ap.avaliacao_id = a.id and ap.deletado_em is null), '[]'),
         case when funcionalidade_activa('avaliacoes_fotos') then
           coalesce((select array_agg(f.caminho order by f.criado_em) from fotos_avaliacao f
                      where f.avaliacao_id = a.id and f.estado = 'aprovada' and f.deletado_em is null), '{}')
         else '{}' end
    from avaliacoes a
   where funcionalidade_activa('avaliacoes') and cliente_actual() is not null
     and a.cozinha_id = p_cozinha and not a.oculta and a.deletado_em is null
     and (p_prato is null or exists (select 1 from avaliacoes_pratos ap
                                      where ap.avaliacao_id = a.id and ap.prato_id = p_prato and ap.deletado_em is null))
   order by a.criado_em desc
   limit least(greatest(coalesce(p_limite, 30), 1), 100);
$$;

-- -----------------------------------------------------------------------------
-- 4. O7: fotos à espera de moderação (só as que já têm o ficheiro enviado)
-- -----------------------------------------------------------------------------
create or replace function fotos_pendentes()
returns table (foto_id uuid, caminho text, criado_em timestamptz, cozinha_nome text, estrelas integer,
               comentario text, autor_nome text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('avaliacoes.moderar');
  return query
  select f.id, f.caminho, f.criado_em, cz.nome, a.estrelas, a.comentario, c.nome
    from fotos_avaliacao f
    join avaliacoes a on a.id = f.avaliacao_id
    join clientes c on c.id = a.cliente_id
    join cozinhas cz on cz.id = a.cozinha_id
   where f.estado = 'pendente' and f.deletado_em is null and a.deletado_em is null
     and exists (select 1 from storage.objects o where o.bucket_id = 'fotos-avaliacoes' and o.name = f.caminho)
   order by f.criado_em;
end $$;

-- -----------------------------------------------------------------------------
-- 5. Privilégios
-- -----------------------------------------------------------------------------
revoke execute on function lista_avaliacoes(uuid, uuid, integer), fotos_pendentes(),
                           foto_pode_enviar(text), foto_pode_ver(text)
  from public, anon;
-- foto_pode_enviar e foto_pode_ver são usadas nas políticas do storage (sessão da app)
grant execute on function lista_avaliacoes(uuid, uuid, integer), fotos_pendentes(),
                          foto_pode_enviar(text), foto_pode_ver(text)
  to authenticated;
revoke execute on function fotos_da_avaliacao(uuid) from public, anon;
grant execute on function fotos_da_avaliacao(uuid) to authenticated;   -- usada pelo trigger SECURITY INVOKER
revoke execute on function fotos_antes_inserir() from public, anon, authenticated;
