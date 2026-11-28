-- Ecrã "Utilizadores" (operador): procurar quem está inscrito — clientes, equipa e contas de
-- login (OTP) que ainda não têm perfil — por nome ou por número (ignorando o formato do número).

-- 1. Permissão (entra no catálogo do ecrã Pessoal automaticamente)
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'utilizadores.ver', 'Clientes',
   'Procurar utilizadores inscritos (clientes, equipa e contas de login) por nome ou número')
on conflict (chave) do nothing;

-- 2. Procura unificada. A procura por número compara os últimos dígitos (>= 3), por isso encontra
--    com ou sem indicativo (+244). A procura por nome é por conteúdo, sem distinguir maiúsculas.
create or replace function procurar_utilizadores(p_termo text)
returns table (tipo text, id uuid, nome text, telefone text, inscrito_em timestamptz,
               tem_login boolean, cargo text, ultimo_pedido date, total_pedidos int)
language plpgsql stable security definer set search_path = public as $$
declare
  v_termo    text := btrim(coalesce(p_termo, ''));
  v_digitos  text := regexp_replace(v_termo, '\D', '', 'g');
  v_nome     text := '%' || lower(v_termo) || '%';
  v_por_num  boolean := length(v_digitos) >= 3;
begin
  perform exigir_permissao('utilizadores.ver');
  if length(v_termo) < 2 then
    return;  -- termo demasiado curto
  end if;
  return query
  with compras as (
    select p.cliente_id,
           max((p.entregue_em at time zone 'Africa/Luanda')::date) as ultimo,
           count(*)::int as n
      from pedidos p
     where p.deletado_em is null and p.estado = 'entregue_pago'
     group by p.cliente_id)
  -- Clientes
  select 'cliente'::text, c.id, c.nome, c.telefone, c.criado_em,
         c.auth_user_id is not null, null::text, x.ultimo, coalesce(x.n, 0)
    from clientes c
    left join compras x on x.cliente_id = c.id
   where c.deletado_em is null
     and ((v_por_num and regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g') like '%' || v_digitos)
          or lower(coalesce(c.nome, '')) like v_nome)
  union all
  -- Equipa
  select 'equipa'::text, f.id, f.nome, f.telefone, f.criado_em,
         f.auth_user_id is not null, f.cargo, null::date, 0
    from funcionarios f
   where f.deletado_em is null
     and ((v_por_num and regexp_replace(coalesce(f.telefone, ''), '\D', '', 'g') like '%' || v_digitos)
          or lower(coalesce(f.nome, '')) like v_nome)
  union all
  -- Contas de login (OTP) ainda sem perfil de cliente nem de equipa (só por número)
  select 'login'::text, u.id, null::text, u.phone, u.created_at,
         true, null::text, null::date, 0
    from auth.users u
   where u.phone is not null and v_por_num
     and regexp_replace(u.phone, '\D', '', 'g') like '%' || v_digitos
     and not exists (select 1 from clientes c    where c.auth_user_id = u.id and c.deletado_em is null)
     and not exists (select 1 from funcionarios f where f.auth_user_id = u.id and f.deletado_em is null)
  order by 5 desc nulls last  -- inscrito_em: mais recentes primeiro
  limit 50;
end $$;

revoke execute on function procurar_utilizadores(text) from public, anon;
grant  execute on function procurar_utilizadores(text) to authenticated;
