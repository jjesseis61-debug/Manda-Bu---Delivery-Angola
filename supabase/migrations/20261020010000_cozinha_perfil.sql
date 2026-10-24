-- Separar a permissão em duas: "cardapio.gerir" fica só o cardápio (pratos, doses, opções);
-- "cozinha.perfil" (nova) é editar o perfil da própria cozinha (nome, contactos, localização).
-- A chave-mestra "cozinhas.gerir" continua a poder tudo e é a única que cria/apaga cozinhas.

-- Catálogo: nova permissão (grupo Cozinhas) e descrição mais clara da cardapio.gerir.
insert into permissoes (chave, grupo, descricao, dispositivo_id)
values ('cozinha.perfil', 'Cozinhas', 'Editar o perfil da própria cozinha (nome, contactos, localização)', 'servidor')
on conflict (chave) do nothing;

update permissoes
   set descricao = 'Editar o cardápio da própria cozinha (pratos, doses e opções)', atualizado_em = now()
 where chave = 'cardapio.gerir';

-- Não partir quem já tinha: quem tem cardapio.gerir hoje recebe também cozinha.perfil (mantém o perfil).
update funcionarios
   set permissoes_extra = coalesce(permissoes_extra, '{}'::jsonb) || jsonb_build_object('cozinha.perfil', true),
       atualizado_em = now()
 where (permissoes_extra ->> 'cardapio.gerir')::boolean is true;

update direcoes
   set permissoes = coalesce(permissoes, '{}'::jsonb) || jsonb_build_object('cozinha.perfil', true),
       atualizado_em = now()
 where (permissoes ->> 'cardapio.gerir')::boolean is true and deletado_em is null;

-- RLS: o PERFIL da cozinha passa a exigir cozinha.perfil (o cardápio continua com cardapio.gerir).
alter policy "editar" on public.cozinhas
  using ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cozinha.perfil', id))
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cozinha.perfil', id));

alter policy "criar" on public.cozinhas_localizacao
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cozinha.perfil', cozinha_id));
alter policy "editar" on public.cozinhas_localizacao
  using ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cozinha.perfil', cozinha_id))
  with check ((select tem_permissao('cozinhas.gerir')) or pode_na_cozinha('cozinha.perfil', cozinha_id));

-- Foto no bucket: a foto do PERFIL (cozinhas/<id>) passa a exigir cozinha.perfil; a foto do PRATO
-- (pratos/<id>) continua com cardapio.gerir. A chave-mestra faz tudo.
create or replace function foto_prato_pode_gerir(p_nome text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_seg     text := split_part(p_nome, '/', 2);
  v_cozinha uuid;
  v_perm    text;
begin
  if tem_permissao('cozinhas.gerir') then
    return true;
  end if;
  if v_seg !~ '^[0-9a-fA-F-]{36}$' then
    return false;
  end if;
  case split_part(p_nome, '/', 1)
    when 'cozinhas' then v_cozinha := v_seg::uuid; v_perm := 'cozinha.perfil';
    when 'pratos'   then v_cozinha := (select cozinha_id from cardapio where id = v_seg::uuid); v_perm := 'cardapio.gerir';
    else return false;
  end case;
  return v_cozinha is not null and pode_na_cozinha(v_perm, v_cozinha);
end $$;
revoke execute on function foto_prato_pode_gerir(text) from public, anon;
grant  execute on function foto_prato_pode_gerir(text) to authenticated;
