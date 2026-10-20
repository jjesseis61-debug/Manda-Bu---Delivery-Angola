-- Lista de números bloqueados + bloquear/desbloquear um utilizador (só o administrador principal).
-- O bloqueio atua em camadas: login (auth.users.banned_until, respeitado pelo GoTrue), registo
-- (registar_cliente recusa) e procura (mostra o selo). A fonte da verdade é o número; o
-- banned_until é só o reflexo nas contas de login que já existem.

-- 1. Lista de bloqueados (só servidor; o operador mexe por RPC)
create table utilizadores_bloqueados (
  telefone      text primary key,            -- normalizado
  motivo        text,
  bloqueado_por uuid references funcionarios(id),
  bloqueado_em  timestamptz not null default now()
);
create index utilizadores_bloqueados_por_idx on utilizadores_bloqueados (bloqueado_por);
alter table utilizadores_bloqueados enable row level security;
revoke all on utilizadores_bloqueados from anon, authenticated;

-- 2. Auxiliar reutilizável
create or replace function telefone_bloqueado(p_telefone text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from utilizadores_bloqueados where telefone = normalizar_telefone(p_telefone));
$$;

-- 3. Bloquear / desbloquear (só administrador principal)
create or replace function bloquear_utilizador(p_telefone text, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tel    text := normalizar_telefone(p_telefone);
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not e_administrador() then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if v_tel is null or v_tel = '' then
    raise exception 'telefone_invalido' using errcode = 'P0001';
  end if;
  insert into utilizadores_bloqueados (telefone, motivo, bloqueado_por)
  values (v_tel, v_motivo, funcionario_actual())
  on conflict (telefone) do update
    set motivo = excluded.motivo, bloqueado_por = excluded.bloqueado_por, bloqueado_em = now();
  -- Reflete nas contas de login existentes (o GoTrue passa a rejeitar os tokens)
  update auth.users set banned_until = 'infinity'
   where normalizar_telefone(phone) = v_tel;
  perform registar_auditoria('utilizador_bloqueado', 'telefone', null::uuid,
            jsonb_build_object('telefone', v_tel, 'motivo', v_motivo), true);
end $$;

create or replace function desbloquear_utilizador(p_telefone text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tel text := normalizar_telefone(p_telefone);
begin
  if not e_administrador() then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  delete from utilizadores_bloqueados where telefone = v_tel;
  update auth.users set banned_until = null
   where normalizar_telefone(phone) = v_tel;
  perform registar_auditoria('utilizador_desbloqueado', 'telefone', null::uuid,
            jsonb_build_object('telefone', v_tel));
end $$;

-- 4. Reforço no registo: um número bloqueado não cria nem liga um perfil de cliente.
--    (recria registar_cliente de 20261001052041 com a verificação acrescentada)
create or replace function registar_cliente(p_nome text, p_tipo text default 'Particular', p_nif text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_telefone text;
  v_cliente  uuid;
  v_nome     text := nullif(trim(p_nome), '');
begin
  if v_uid is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  select id into v_cliente from clientes where auth_user_id = v_uid and deletado_em is null;
  if found then
    return v_cliente;
  end if;
  if v_nome is null or length(v_nome) > 80 then
    raise exception 'nome_invalido' using errcode = 'P0001';
  end if;
  if p_tipo not in ('Particular', 'Empresa') then
    raise exception 'tipo_invalido' using errcode = 'P0001';
  end if;
  if p_tipo = 'Empresa' and nullif(trim(p_nif), '') is null then
    raise exception 'nif_obrigatorio' using errcode = 'P0001';
  end if;

  select normalizar_telefone(phone) into v_telefone from auth.users where id = v_uid;
  if v_telefone is null then
    raise exception 'telefone_nao_confirmado' using errcode = 'P0001';
  end if;
  if telefone_bloqueado(v_telefone) then
    raise exception 'utilizador_bloqueado' using errcode = '42501';
  end if;

  select id into v_cliente from clientes
   where normalizar_telefone(telefone) = v_telefone and deletado_em is null
   order by criado_em limit 1
   for update;
  if found then
    if exists (select 1 from clientes where id = v_cliente and auth_user_id is not null) then
      raise exception 'telefone_ja_associado' using errcode = 'P0001';
    end if;
    update clientes set auth_user_id = v_uid, atualizado_em = now() where id = v_cliente;
    perform preparar_cliente_programa(v_cliente);
    perform registar_auditoria('cliente_ligado_app', 'clientes', v_cliente, '{}'::jsonb);
  else
    insert into clientes (nome, tipo, telefone, nif, auth_user_id, dispositivo_id)
    values (v_nome, p_tipo, v_telefone, nullif(trim(p_nif), ''), v_uid, 'servidor')
    returning id into v_cliente;
    perform registar_auditoria('cliente_registado_app', 'clientes', v_cliente, '{}'::jsonb);
  end if;
  return v_cliente;
end $$;

-- 5. A procura passa a indicar quem está bloqueado (e o motivo). Recria procurar_utilizadores de
--    20261020020000 com o cruzamento da lista de bloqueados (mais duas colunas de saída, por isso
--    é preciso apagar primeiro).
drop function if exists procurar_utilizadores(text);
create or replace function procurar_utilizadores(p_termo text)
returns table (tipo text, id uuid, nome text, telefone text, inscrito_em timestamptz,
               tem_login boolean, cargo text, ultimo_pedido date, total_pedidos int,
               bloqueado boolean, motivo_bloqueio text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_termo    text := btrim(coalesce(p_termo, ''));
  v_digitos  text := regexp_replace(v_termo, '\D', '', 'g');
  v_nome     text := '%' || lower(v_termo) || '%';
  v_por_num  boolean := length(v_digitos) >= 3;
begin
  perform exigir_permissao('utilizadores.ver');
  if length(v_termo) < 2 then
    return;
  end if;
  return query
  with compras as (
    select p.cliente_id,
           max((p.entregue_em at time zone 'Africa/Luanda')::date) as ultimo,
           count(*)::int as n
      from pedidos p
     where p.deletado_em is null and p.estado = 'entregue_pago'
     group by p.cliente_id),
  achados as (
    -- Clientes
    select 'cliente'::text as tipo, c.id, c.nome, c.telefone, c.criado_em as inscrito_em,
           c.auth_user_id is not null as tem_login, null::text as cargo,
           x.ultimo as ultimo_pedido, coalesce(x.n, 0) as total_pedidos,
           normalizar_telefone(c.telefone) as tel_norm
      from clientes c
      left join compras x on x.cliente_id = c.id
     where c.deletado_em is null
       and ((v_por_num and regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g') like '%' || v_digitos)
            or lower(coalesce(c.nome, '')) like v_nome)
    union all
    -- Equipa
    select 'equipa'::text, f.id, f.nome, f.telefone, f.criado_em,
           f.auth_user_id is not null, f.cargo, null::date, 0,
           normalizar_telefone(f.telefone)
      from funcionarios f
     where f.deletado_em is null
       and ((v_por_num and regexp_replace(coalesce(f.telefone, ''), '\D', '', 'g') like '%' || v_digitos)
            or lower(coalesce(f.nome, '')) like v_nome)
    union all
    -- Contas de login (OTP) ainda sem perfil (só por número)
    select 'login'::text, u.id, null::text, u.phone, u.created_at,
           true, null::text, null::date, 0, normalizar_telefone(u.phone)
      from auth.users u
     where u.phone is not null and v_por_num
       and regexp_replace(u.phone, '\D', '', 'g') like '%' || v_digitos
       and not exists (select 1 from clientes c    where c.auth_user_id = u.id and c.deletado_em is null)
       and not exists (select 1 from funcionarios f where f.auth_user_id = u.id and f.deletado_em is null))
  select a.tipo, a.id, a.nome, a.telefone, a.inscrito_em, a.tem_login, a.cargo,
         a.ultimo_pedido, a.total_pedidos,
         b.telefone is not null as bloqueado, b.motivo
    from achados a
    left join utilizadores_bloqueados b on b.telefone = a.tel_norm
   order by a.inscrito_em desc nulls last
   limit 50;
end $$;

-- 6. Lista de todos os bloqueados (para a secção "Bloqueados", sem termo de procura). Resolve o
--    nome a partir de um cliente ou funcionário com o mesmo número, se existir.
create or replace function utilizadores_bloqueados_lista()
returns table (telefone text, motivo text, bloqueado_em timestamptz, bloqueado_por_nome text, nome text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('utilizadores.ver');
  return query
    select b.telefone, b.motivo, b.bloqueado_em,
           (select f.nome from funcionarios f where f.id = b.bloqueado_por),
           coalesce(
             (select c.nome from clientes c
               where normalizar_telefone(c.telefone) = b.telefone and c.deletado_em is null
               order by c.criado_em limit 1),
             (select f.nome from funcionarios f
               where normalizar_telefone(f.telefone) = b.telefone and f.deletado_em is null limit 1))
      from utilizadores_bloqueados b
     order by b.bloqueado_em desc;
end $$;

-- 7. Permissões de execução
revoke execute on function procurar_utilizadores(text)      from public, anon;
grant  execute on function procurar_utilizadores(text)      to authenticated;
revoke execute on function telefone_bloqueado(text)         from public, anon;
revoke execute on function bloquear_utilizador(text, text)  from public, anon;
revoke execute on function desbloquear_utilizador(text)     from public, anon;
revoke execute on function utilizadores_bloqueados_lista()  from public, anon;
grant  execute on function telefone_bloqueado(text)         to authenticated;
grant  execute on function bloquear_utilizador(text, text)  to authenticated;
grant  execute on function desbloquear_utilizador(text)     to authenticated;
grant  execute on function utilizadores_bloqueados_lista()  to authenticated;
