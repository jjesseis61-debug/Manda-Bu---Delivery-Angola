-- Receitas: o botão «Pedir» segue o prato e o balcão do cliente (não uma cozinha fixa).
--  1. A receita liga-se aos pratos do cardápio que a fazem (de uma ou várias cozinhas).
--  2. receita_onde_pedir: o balcão escolhido, se vender o prato; senão o mais perto que o venda;
--     senão «ninguém faz perto de ti».
--  3. «Quero que façam»: interesse dos clientes num prato que ninguém vende (sinal para as cozinhas).
--  4. Funil: cada toque em «Pedir» fica registado; conta como venda um pedido (não cancelado) do mesmo
--     cliente, nas 24 h seguintes, com um dos pratos ligados à receita.

-- ------------------------------------------------------------------ 1. pratos ligados
create table if not exists receitas_pratos (
  receita_id  uuid not null references receitas(id),
  cardapio_id uuid not null references cardapio(id),
  criado_em   timestamptz not null default now(),
  primary key (receita_id, cardapio_id)
);
create index if not exists receitas_pratos_cardapio_idx on receitas_pratos (cardapio_id);
alter table receitas_pratos enable row level security;
revoke all on receitas_pratos from public, anon, authenticated;

-- As receitas que já existem ficam ligadas aos pratos com o mesmo nome (ex.: «Cocada amarela» ↔ «Cocada»,
-- «Calulu de peixe» ↔ «Funje + Calulu de Peixe»); as outras ficam sem pratos até o operador escolher.
insert into receitas_pratos (receita_id, cardapio_id)
select r.id, m.id
  from receitas r
  join cardapio m on m.deletado_em is null
                 and (lower(m.nome) like '%' || lower(r.titulo) || '%' or lower(r.titulo) like '%' || lower(m.nome) || '%')
 where r.deletado_em is null
on conflict do nothing;

create or replace function receita_pratos_gerir(p_receita uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('receitas.gerir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'receitas.gerir';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('cardapio_id', m.id, 'nome', m.nome, 'preco', m.preco,
                                                        'cozinha_id', c.id, 'cozinha_nome', c.nome,
                                                        'disponivel', m.disponivel and m.visivel_online)
                                    order by c.nome, m.nome)
                     from receitas_pratos rp join cardapio m on m.id = rp.cardapio_id join cozinhas c on c.id = m.cozinha_id
                    where rp.receita_id = p_receita and m.deletado_em is null), '[]'::jsonb);
end $$;
revoke execute on function receita_pratos_gerir(uuid) from public, anon;
grant execute on function receita_pratos_gerir(uuid) to authenticated;

create or replace function receita_guardar_pratos(p_receita uuid, p_cardapio uuid[]) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v integer;
begin
  if not tem_permissao('receitas.gerir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'receitas.gerir';
  end if;
  if not exists (select 1 from receitas where id = p_receita and deletado_em is null) then
    raise exception 'receita_inexistente' using errcode = 'P0001';
  end if;
  delete from receitas_pratos where receita_id = p_receita and cardapio_id <> all (coalesce(p_cardapio, '{}'));
  insert into receitas_pratos (receita_id, cardapio_id)
  select p_receita, m.id from cardapio m where m.id = any (coalesce(p_cardapio, '{}')) and m.deletado_em is null
  on conflict do nothing;
  select count(*) into v from receitas_pratos where receita_id = p_receita;
  perform registar_auditoria('receita_pratos', 'receitas', p_receita, jsonb_build_object('pratos', v));
  return v;
end $$;
revoke execute on function receita_guardar_pratos(uuid, uuid[]) from public, anon;
grant execute on function receita_guardar_pratos(uuid, uuid[]) to authenticated;

-- ------------------------------------------------------------------ 2. onde pedir
create table if not exists receitas_interesse (
  receita_id uuid not null references receitas(id),
  cliente_id uuid not null references clientes(id),
  criado_em  timestamptz not null default now(),
  primary key (receita_id, cliente_id)
);
create index if not exists receitas_interesse_cliente_idx on receitas_interesse (cliente_id);
alter table receitas_interesse enable row level security;
revoke all on receitas_interesse from public, anon, authenticated;

-- estado: 'aqui' (o balcão escolhido vende), 'perto' (outro balcão vende; o mais perto),
--         'ninguem' (nenhum balcão que aceite pedidos vende o prato)
create or replace function receita_onde_pedir(p_receita uuid, p_cozinha uuid default null, p_ponto uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  r         record;
  v_quero   boolean;
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not exists (select 1 from receitas where id = p_receita and estado = 'publicada' and deletado_em is null
                    and funcionalidade_activa('receitas')) then
    raise exception 'receita_inexistente' using errcode = 'P0001';
  end if;
  v_quero := exists (select 1 from receitas_interesse where receita_id = p_receita and cliente_id = v_cliente);

  with candidatos as (
    select m.id as cardapio_id, m.nome, m.preco, c.id as cozinha_id, c.nome as cozinha_nome
      from receitas_pratos rp
      join cardapio m on m.id = rp.cardapio_id and m.deletado_em is null and m.disponivel and m.visivel_online
      join cozinhas c on c.id = m.cozinha_id
     where rp.receita_id = p_receita and cozinha_aceita_pedidos(c.id) and condominio_da_cozinha(c.id) is null
  ), perto as (
    select k.cozinha_id, k.distancia_km from cozinhas_perto(p_ponto) k where p_ponto is not null
  )
  select x.*, p.distancia_km,
         case when x.cozinha_id = p_cozinha then 'aqui' else 'perto' end as estado
    into r
    from candidatos x
    left join perto p on p.cozinha_id = x.cozinha_id
   order by (x.cozinha_id = p_cozinha) desc nulls last, p.distancia_km nulls last, (x.cozinha_id = cozinha_padrao()) desc, x.preco
   limit 1;

  if r.cardapio_id is null then
    return jsonb_build_object('estado', 'ninguem', 'quero', v_quero,
                              'interessados', (select count(*) from receitas_interesse where receita_id = p_receita));
  end if;
  return jsonb_build_object('estado', r.estado, 'cozinha_id', r.cozinha_id, 'cozinha_nome', r.cozinha_nome,
                            'cardapio_id', r.cardapio_id, 'prato_nome', r.nome, 'preco', r.preco,
                            'distancia_km', r.distancia_km, 'quero', v_quero);
end $$;
revoke execute on function receita_onde_pedir(uuid, uuid, uuid) from public, anon;
grant execute on function receita_onde_pedir(uuid, uuid, uuid) to authenticated;

-- ------------------------------------------------------------------ 3. «quero que façam»
create or replace function receita_quero(p_receita uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
begin
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not exists (select 1 from receitas where id = p_receita and estado = 'publicada' and deletado_em is null) then
    raise exception 'receita_inexistente' using errcode = 'P0001';
  end if;
  insert into receitas_interesse (receita_id, cliente_id) values (p_receita, v_cliente) on conflict do nothing;
  return (select count(*)::int from receitas_interesse where receita_id = p_receita);
end $$;
revoke execute on function receita_quero(uuid) from public, anon;
grant execute on function receita_quero(uuid) to authenticated;

-- ------------------------------------------------------------------ 4. funil: toque -> pedido
create table if not exists receitas_toques (
  id         uuid primary key default gen_random_uuid(),
  receita_id uuid not null references receitas(id),
  cliente_id uuid not null references clientes(id),
  criado_em  timestamptz not null default now()
);
create index if not exists receitas_toques_receita_idx on receitas_toques (receita_id, criado_em);
create index if not exists receitas_toques_cliente_idx on receitas_toques (cliente_id);
alter table receitas_toques enable row level security;
revoke all on receitas_toques from public, anon, authenticated;

create or replace function receita_tocou_pedir(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update receitas set toques_pedir = toques_pedir + 1
   where id = p_id and estado = 'publicada' and deletado_em is null;
  if found and cliente_actual() is not null then
    insert into receitas_toques (receita_id, cliente_id) values (p_id, cliente_actual());
  end if;
end $$;
revoke execute on function receita_tocou_pedir(uuid) from public, anon;
grant execute on function receita_tocou_pedir(uuid) to authenticated;

-- Números de cada receita para o operador: aberturas, toques, pedidos que vieram dela, interesse e quem a faz
create or replace function receitas_metricas() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('receitas.gerir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'receitas.gerir';
  end if;
  return coalesce((
    select jsonb_object_agg(r.id, jsonb_build_object(
             'aberturas', r.aberturas,
             'toques', r.toques_pedir,
             'pedidos', (select count(distinct p.id)
                           from receitas_toques t
                           join pedidos p on p.cliente_id = t.cliente_id and p.deletado_em is null and p.estado <> 'cancelado'
                                         and p.criado_em between t.criado_em and t.criado_em + interval '24 hours'
                          where t.receita_id = r.id
                            and exists (select 1 from jsonb_array_elements(p.itens) i
                                         join receitas_pratos rp on rp.receita_id = r.id
                                                                and rp.cardapio_id::text = i ->> 'cardapio_id')),
             'interessados', (select count(*) from receitas_interesse i where i.receita_id = r.id),
             'cozinhas', (select coalesce(jsonb_agg(distinct c.nome), '[]'::jsonb)
                            from receitas_pratos rp join cardapio m on m.id = rp.cardapio_id and m.deletado_em is null
                            join cozinhas c on c.id = m.cozinha_id
                           where rp.receita_id = r.id)))
      from receitas r where r.deletado_em is null), '{}'::jsonb);
end $$;
revoke execute on function receitas_metricas() from public, anon;
grant execute on function receitas_metricas() to authenticated;
