-- Cadastro de pessoal (estafetas e outros funcionários) pela app + mapa de acompanhamento dos
-- estafetas para a cozinha/despacho. Duas partes:
--
-- A) O administrador principal cria/edita/desativa funcionários pela app e marca "é estafeta"
--    (permissão entregas.registar individual, guardada em permissoes_extra). Mesma barreira do
--    definir_telefone_funcionario (só administrador_principal); tudo auditado.
-- B) posicoes_estafetas(cozinha): quem faz o despacho (pedidos.gerir) vê os estafetas de serviço
--    num mapa, só enquanto têm entregas a decorrer (mesma privacidade do I11: última posição,
--    apagada no fim, sem histórico).

-- =====================================================================
-- A) Pessoal — só administrador principal
-- =====================================================================

create or replace function exigir_admin_principal() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v uuid := funcionario_actual();
begin
  if v is null or not exists (select 1 from funcionarios
                               where id = v and administrador_principal and deletado_em is null) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'administrador_principal';
  end if;
  return v;
end $$;

-- Lista para o ecrã Pessoal: activos primeiro, por nome. `estafeta` cobre a permissão vinda da
-- direcção ou do extra individual.
create or replace function listar_pessoal()
returns table (id uuid, nome text, cargo text, telefone text,
               administrador_principal boolean, estafeta boolean, activo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_admin_principal();
  return query
    select f.id, f.nome, f.cargo, f.telefone, f.administrador_principal,
           tem_permissao_de(f.id, 'entregas.registar'), (f.deletado_em is null)
      from funcionarios f
     order by (f.deletado_em is null) desc, f.nome;
end $$;

create or replace function criar_funcionario(p_nome text, p_cargo text default null,
                                             p_telefone text default null, p_estafeta boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id       uuid;
  v_telefone text := normalizar_telefone(p_telefone);
begin
  perform exigir_admin_principal();
  if p_nome is null or length(btrim(p_nome)) = 0 or length(p_nome) > 120 then
    raise exception 'nome_invalido' using errcode = 'P0001';
  end if;
  if p_telefone is not null and (v_telefone is null or v_telefone !~ '^9\d{8}$') then
    raise exception 'numero_invalido' using errcode = 'P0001';
  end if;
  if v_telefone is not null and exists (select 1 from funcionarios
                                         where normalizar_telefone(telefone) = v_telefone and deletado_em is null) then
    raise exception 'numero_repetido' using errcode = 'P0001';
  end if;
  insert into funcionarios (nome, cargo, telefone, permissoes_extra, dispositivo_id)
  values (btrim(p_nome), nullif(btrim(coalesce(p_cargo, '')), ''), v_telefone,
          case when p_estafeta then jsonb_build_object('entregas.registar', true) else '{}'::jsonb end,
          'servidor')
  returning id into v_id;
  perform registar_auditoria('funcionario_criado', 'funcionarios', v_id,
                             jsonb_build_object('nome', btrim(p_nome), 'estafeta', coalesce(p_estafeta, false)));
  return v_id;
end $$;

-- Edita nome/cargo, liga/desliga "é estafeta" (só o extra individual) e activa/desactiva.
-- Desactivar liberta o login (auth_user_id) para o número poder ser reatribuído.
create or replace function editar_funcionario(p_id uuid, p_nome text, p_cargo text default null,
                                             p_estafeta boolean default null, p_activo boolean default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_alvo  funcionarios;
  v_extra jsonb;
begin
  perform exigir_admin_principal();
  select * into v_alvo from funcionarios where id = p_id;
  if not found then
    raise exception 'funcionario_inexistente' using errcode = 'P0001';
  end if;
  if v_alvo.administrador_principal and p_activo is false then
    raise exception 'admin_principal_protegido' using errcode = 'P0001';
  end if;
  if p_nome is null or length(btrim(p_nome)) = 0 or length(p_nome) > 120 then
    raise exception 'nome_invalido' using errcode = 'P0001';
  end if;
  v_extra := coalesce(v_alvo.permissoes_extra, '{}'::jsonb);
  if p_estafeta is not null then
    v_extra := case when p_estafeta then v_extra || jsonb_build_object('entregas.registar', true)
                    else v_extra - 'entregas.registar' end;
  end if;
  update funcionarios
     set nome = btrim(p_nome),
         cargo = nullif(btrim(coalesce(p_cargo, '')), ''),
         permissoes_extra = v_extra,
         deletado_em = case when p_activo is false then coalesce(deletado_em, now())
                            when p_activo is true then null
                            else deletado_em end,
         auth_user_id = case when p_activo is false then null else auth_user_id end,
         atualizado_em = now()
   where id = p_id;
  perform registar_auditoria('funcionario_editado', 'funcionarios', p_id,
                             jsonb_build_object('estafeta', p_estafeta, 'activo', p_activo));
end $$;

-- Auxiliar só do servidor: nem as apps a chamam (o Supabase concede execute a authenticated por
-- omissão, por isso revoga-se também de authenticated).
revoke execute on function exigir_admin_principal() from public, anon, authenticated;
revoke execute on function listar_pessoal(),
  criar_funcionario(text, text, text, boolean),
  editar_funcionario(uuid, text, text, boolean, boolean) from public, anon;
grant execute on function listar_pessoal(),
  criar_funcionario(text, text, text, boolean),
  editar_funcionario(uuid, text, text, boolean, boolean) to authenticated;

-- =====================================================================
-- B) Mapa de acompanhamento dos estafetas (despacho: pedidos.gerir)
-- =====================================================================

create or replace function posicoes_estafetas(p_cozinha uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  if not tem_permissao('pedidos.gerir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir';
  end if;
  if not funcionalidade_activa('acompanhamento_entrega') then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
            'funcionario_id', f.id,
            'nome', f.nome,
            'lat', pe.lat,
            'lng', pe.lng,
            'pedidos_a_levar', (select count(*) from pedidos p
                                 where p.entregador_id = f.id and p.estado = 'em_entrega'
                                   and p.deletado_em is null and p.cozinha_id = p_cozinha),
            'atualizado_em', pe.atualizado_em) order by f.nome), '[]'::jsonb)
    into v
    from posicoes_entregadores pe
    join funcionarios f on f.id = pe.funcionario_id and f.deletado_em is null
   where exists (select 1 from pedidos p
                  where p.entregador_id = f.id and p.estado = 'em_entrega'
                    and p.deletado_em is null and p.cozinha_id = p_cozinha);
  return v;
end $$;

revoke execute on function posicoes_estafetas(uuid) from public, anon;
grant  execute on function posicoes_estafetas(uuid) to authenticated;
