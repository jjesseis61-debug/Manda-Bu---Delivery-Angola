-- Impacto de uma alteração de preço: quantos pedidos foram atendidos a cada preço de um prato,
-- quantos clientes distintos e o movimento cliente a cliente. Liga o pedido ao prato pelo
-- cardapio_id congelado em pedidos.itens, e usa o preco_unitario que o cliente pagou na altura.
-- "Atendido" = entregue e pago (entregue_pago); cancelado/estornado vão num sub-total à parte.
-- Barreira: só o Administrador principal (tem tudo) ou quem tenha "auditoria.ver".

-- 1) Resumo por preço cobrado: pedidos entregues, clientes distintos, total recebido e cancelados.
create or replace function impacto_preco_prato(p_cardapio uuid)
returns table(preco int, pedidos_entregues int, clientes int, total_kz bigint, pedidos_cancelados int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('auditoria.ver') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'auditoria.ver';
  end if;
  return query
  with linhas as (
    select p.estado, p.cliente_id,
           (it ->> 'preco_unitario')::int as preco,
           coalesce((it ->> 'qtd')::int, 1)  as qtd
      from pedidos p
      cross join lateral jsonb_array_elements(p.itens) it
     where p.deletado_em is null
       and it ->> 'cardapio_id' = p_cardapio::text
  )
  select l.preco,
         count(*) filter (where l.estado = 'entregue_pago')::int,
         count(distinct l.cliente_id) filter (where l.estado = 'entregue_pago')::int,
         coalesce(sum(l.preco::bigint * l.qtd) filter (where l.estado = 'entregue_pago'), 0)::bigint,
         count(*) filter (where l.estado in ('cancelado', 'estornado'))::int
    from linhas l
   group by l.preco
   order by l.preco;
end $$;
revoke execute on function impacto_preco_prato(uuid) from public, anon;
grant  execute on function impacto_preco_prato(uuid) to authenticated;

-- 2) Movimento cliente a cliente de um prato (opcionalmente só de um preço).
create or replace function movimento_preco_prato(p_cardapio uuid, p_preco int default null)
returns table(quando timestamptz, cliente text, qtd int, preco int, estado text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('auditoria.ver') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'auditoria.ver';
  end if;
  return query
  select p.criado_em, c.nome,
         coalesce((it ->> 'qtd')::int, 1),
         (it ->> 'preco_unitario')::int,
         p.estado
    from pedidos p
    join clientes c on c.id = p.cliente_id
    cross join lateral jsonb_array_elements(p.itens) it
   where p.deletado_em is null
     and it ->> 'cardapio_id' = p_cardapio::text
     and (p_preco is null or (it ->> 'preco_unitario')::int = p_preco)
   order by p.criado_em desc
   limit 300;
end $$;
revoke execute on function movimento_preco_prato(uuid, int) from public, anon;
grant  execute on function movimento_preco_prato(uuid, int) to authenticated;
