-- Receitas da terra (R1 — base): conteúdo editorial (texto + 1 foto) de cozinha angolana que termina
-- num CTA de pedido ("não queres cozinhar? a [cozinha] faz por ti"). Atrás do interruptor 'receitas'
-- e da permissão 'receitas.gerir'. A geração com Claude é o R2; métricas e aviso são o R3.

-- 1. Interruptor (nasce desligado) e permissão editorial
insert into funcionalidades (chave, activa, dispositivo_id) values ('receitas', false, 'servidor')
  on conflict (chave) do nothing;
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'receitas.gerir', 'Conteúdo', 'Criar, editar e publicar receitas (Cozinha de casa)')
  on conflict (chave) do nothing;

-- 2. Tabela
create table if not exists receitas (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null,
  resumo        text,
  corpo         text not null,
  foto_url      text,
  cozinha_id    uuid references cozinhas(id),
  prato_base_id uuid references pratos_base(id),   -- reservado para o CTA ao prato (R2+)
  estado        text not null default 'rascunho' check (estado in ('rascunho', 'publicada', 'arquivada')),
  origem        text not null default 'manual'    check (origem in ('manual', 'claude')),
  aberturas     integer not null default 0,        -- métrica (R3)
  toques_pedir  integer not null default 0,        -- métrica (R3)
  autor         uuid,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  publicado_em  timestamptz,
  deletado_em   timestamptz
);
create index if not exists receitas_publicadas_idx on receitas (publicado_em desc)
  where estado = 'publicada' and deletado_em is null;
-- Índices das chaves estrangeiras (exigido pelo endurecimento)
create index if not exists receitas_cozinha_idx on receitas (cozinha_id);
create index if not exists receitas_prato_idx   on receitas (prato_base_id);

-- 3. RLS: o cliente (sempre autenticado) vê só as publicadas e com o interruptor ligado; quem gere vê
--    e escreve tudo. As funções de sessão vão em (select ...) para serem avaliadas uma vez por consulta.
alter table receitas enable row level security;
create policy receitas_ler on receitas for select to authenticated
  using ((estado = 'publicada' and deletado_em is null and (select funcionalidade_activa('receitas')))
         or (select tem_permissao('receitas.gerir')));
create policy receitas_criar on receitas for insert to authenticated
  with check ((select tem_permissao('receitas.gerir')));
create policy receitas_alterar on receitas for update to authenticated
  using ((select tem_permissao('receitas.gerir'))) with check ((select tem_permissao('receitas.gerir')));
-- Apagar é soft-delete (update deletado_em); não há policy de delete.
grant select, insert, update on receitas to authenticated;

-- 4. Leitura pública (cliente) por RPC — lista e detalhe, já com o nome da cozinha do CTA
create or replace function receitas_publicas()
returns table (id uuid, titulo text, resumo text, foto_url text, cozinha_id uuid, cozinha_nome text)
language sql stable security definer set search_path = public as $$
  select r.id, r.titulo, r.resumo, r.foto_url, r.cozinha_id, c.nome
    from receitas r
    left join cozinhas c on c.id = r.cozinha_id
   where r.estado = 'publicada' and r.deletado_em is null and funcionalidade_activa('receitas')
   order by r.publicado_em desc nulls last;
$$;

create or replace function receita_publica(p_id uuid)
returns table (id uuid, titulo text, resumo text, corpo text, foto_url text, cozinha_id uuid, cozinha_nome text)
language sql stable security definer set search_path = public as $$
  select r.id, r.titulo, r.resumo, r.corpo, r.foto_url, r.cozinha_id, c.nome
    from receitas r
    left join cozinhas c on c.id = r.cozinha_id
   where r.id = p_id and r.estado = 'publicada' and r.deletado_em is null and funcionalidade_activa('receitas');
$$;

revoke execute on function receitas_publicas()      from public, anon;
revoke execute on function receita_publica(uuid)     from public, anon;
grant  execute on function receitas_publicas()      to authenticated;
grant  execute on function receita_publica(uuid)     to authenticated;

-- 5. Bucket público das fotos de receitas (leitura por todos; escrita só com receitas.gerir)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos-receitas', 'fotos-receitas', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do nothing;
create policy receitas_foto_ler on storage.objects for select to anon, authenticated
  using (bucket_id = 'fotos-receitas');
create policy receitas_foto_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos-receitas' and (select tem_permissao('receitas.gerir')));
create policy receitas_foto_trocar on storage.objects for update to authenticated
  using (bucket_id = 'fotos-receitas' and (select tem_permissao('receitas.gerir')))
  with check (bucket_id = 'fotos-receitas' and (select tem_permissao('receitas.gerir')));
create policy receitas_foto_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos-receitas' and (select tem_permissao('receitas.gerir')));
