-- Gestão de funções e permissões pelo ecrã Pessoal (admin principal).
-- Até aqui o admin só podia marcar "é estafeta" (entregas.registar); as outras 21 permissões e a
-- pertença a cozinhas só se mexiam na base de dados. Isto dá-lhe:
--   * definir as permissões de cada funcionário (checkboxes do catálogo), e
--   * definir a que cozinha(s) pertence (necessário para as permissões por cozinha, ex.: pedidos.gerir).
-- A pertença fixa fica numa tabela própria (equipa_cozinha), separada dos turnos do dia a dia.

-- Equipa fixa da cozinha (pertença permanente)
create table equipa_cozinha (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references funcionarios(id),
  cozinha_id uuid not null references cozinhas(id),
  criado_em timestamptz not null default now(),
  unique (funcionario_id, cozinha_id)
);
alter table equipa_cozinha enable row level security;
revoke all on equipa_cozinha from public, anon, authenticated;
create index equipa_cozinha_func_idx on equipa_cozinha (funcionario_id);
create index equipa_cozinha_coz_idx on equipa_cozinha (cozinha_id);

-- Agora um funcionário é "da cozinha" por um turno OU pela equipa fixa (aditivo: nada deixa de valer)
create or replace function membro_da_cozinha(p_cozinha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from turnos t
                  where t.cozinha_id = p_cozinha and t.deletado_em is null
                    and t.funcionario_id = funcionario_actual())
      or exists (select 1 from equipa_cozinha e
                  where e.cozinha_id = p_cozinha and e.funcionario_id = funcionario_actual());
$$;

-- Catálogo das permissões, para o ecrã montar os grupos e as descrições
create or replace function permissoes_catalogo()
returns table (chave text, grupo text, descricao text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_admin_principal();
  return query select p.chave, p.grupo, p.descricao
                 from permissoes p where p.deletado_em is null order by p.grupo, p.chave;
end $$;

-- Definir as permissões de um funcionário (objeto {chave:true}); só chaves verdadeiras do catálogo
create or replace function definir_permissoes_funcionario(p_func uuid, p_permissoes jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_alvo  funcionarios;
  v_limpo jsonb := '{}'::jsonb;
  k       text;
begin
  perform exigir_admin_principal();
  select * into v_alvo from funcionarios where id = p_func and deletado_em is null;
  if not found then raise exception 'funcionario_inexistente' using errcode = 'P0001'; end if;
  if v_alvo.administrador_principal then
    raise exception 'admin_principal_tem_tudo' using errcode = 'P0001';
  end if;
  for k in select jsonb_object_keys(coalesce(p_permissoes, '{}'::jsonb)) loop
    if coalesce((p_permissoes ->> k)::boolean, false)
       and exists (select 1 from permissoes where chave = k and deletado_em is null) then
      v_limpo := v_limpo || jsonb_build_object(k, true);
    end if;
  end loop;
  update funcionarios set permissoes_extra = v_limpo, atualizado_em = now() where id = p_func;
  perform registar_auditoria('permissoes_definidas', 'funcionarios', p_func, jsonb_build_object('permissoes', v_limpo));
end $$;

-- Definir a(s) cozinha(s) de um funcionário (equipa fixa): sincroniza, mantendo as que ficam
create or replace function definir_cozinhas_funcionario(p_func uuid, p_cozinhas uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_admin_principal();
  if not exists (select 1 from funcionarios where id = p_func and deletado_em is null) then
    raise exception 'funcionario_inexistente' using errcode = 'P0001';
  end if;
  delete from equipa_cozinha
   where funcionario_id = p_func
     and (p_cozinhas is null or cozinha_id <> all(p_cozinhas));
  insert into equipa_cozinha (funcionario_id, cozinha_id)
    select p_func, c
      from unnest(coalesce(p_cozinhas, '{}'::uuid[])) as c
     where exists (select 1 from cozinhas k where k.id = c and k.deletado_em is null)
    on conflict (funcionario_id, cozinha_id) do nothing;
  perform registar_auditoria('cozinhas_definidas', 'funcionarios', p_func, jsonb_build_object('cozinhas', to_jsonb(p_cozinhas)));
end $$;

-- listar_pessoal passa a trazer também as permissões e as cozinhas de cada funcionário
drop function if exists listar_pessoal();
create function listar_pessoal()
returns table (id uuid, nome text, cargo text, telefone text,
               administrador_principal boolean, estafeta boolean, activo boolean,
               permissoes jsonb, cozinhas uuid[])
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_admin_principal();
  return query
    select f.id, f.nome, f.cargo, f.telefone, f.administrador_principal,
           tem_permissao_de(f.id, 'entregas.registar'), (f.deletado_em is null),
           coalesce(f.permissoes_extra, '{}'::jsonb),
           coalesce(array(select e.cozinha_id from equipa_cozinha e where e.funcionario_id = f.id), '{}'::uuid[])
      from funcionarios f
     order by (f.deletado_em is null) desc, f.nome;
end $$;

revoke execute on function
  listar_pessoal(), permissoes_catalogo(),
  definir_permissoes_funcionario(uuid, jsonb), definir_cozinhas_funcionario(uuid, uuid[])
  from public, anon;
grant execute on function
  listar_pessoal(), permissoes_catalogo(),
  definir_permissoes_funcionario(uuid, jsonb), definir_cozinhas_funcionario(uuid, uuid[])
  to authenticated;
