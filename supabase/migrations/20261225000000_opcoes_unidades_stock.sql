-- Opções que contam o stock (latas de gasosa, garrafas de água, sumos engarrafados): a cozinha liga
-- «contar_stock» numa opção que tem o produto nos ingredientes (opcoes.componentes) e o cliente vê o que
-- resta de verdade («Restam 4»), ou «Hoje não há» quando acabou (Cialdini: escassez só quando é real).
--
-- O que resta = saldo do produto no stock de longo prazo da cozinha (entradas menos consumos)
--             - o que já está prometido em pedidos ainda sem venda (não cancelados nem estornados),
-- dividido pelo que cada opção gasta. Com vários produtos conta o que acabar primeiro.
-- Só contam produtos de 'Longo Prazo' (o 'Diário' não tem movimentos por venda).
-- Um pedido feito pela app não pode levar mais do que resta (trava a opção, como as doses dos pratos);
-- os pedidos da equipa contam mas não são travados.

alter table opcoes add column if not exists contar_stock boolean not null default false;
comment on column opcoes.contar_stock is
  'A app mostra o que resta desta opção pelo stock dos produtos dos ingredientes, e o pedido não passa do que resta';

-- Quanto de cada produto (em unidade base) está prometido em pedidos da cozinha que ainda não viraram venda
create or replace function stock_prometido(p_cozinha uuid, p_produto uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(coalesce((i ->> 'qtd')::numeric, 1)
                      * quantidade_unidade_base((comp ->> 'quantidade')::numeric, comp ->> 'unidade', pr.categoria_medida)), 0)
    from pedidos p
    cross join jsonb_array_elements(coalesce(p.itens, '[]')) i
    cross join jsonb_array_elements(coalesce(i -> 'opcoes', '[]')) e
    join opcoes o on o.id::text = coalesce(e ->> 'id', e #>> '{}')
    cross join jsonb_array_elements(o.componentes) comp
    join produtos pr on pr.id = p_produto
   where p.cozinha_id = p_cozinha and p.deletado_em is null
     and p.estado not in ('cancelado', 'estornado')
     and not exists (select 1 from vendas v where v.pedido_id = p.id and v.deletado_em is null)
     and comp ->> 'produto_id' = p_produto::text
     and jsonb_typeof(comp -> 'quantidade') = 'number';
$$;
revoke execute on function stock_prometido(uuid, uuid) from public, anon, authenticated;

-- Unidades que restam de uma opção (null = a opção não conta stock ou não tem produto de longo prazo)
create or replace function unidades_opcao(p_opcao uuid) returns integer
language sql stable security definer set search_path = public as $$
  with o as (
    select o.id, o.componentes, c.cozinha_id
      from opcoes o
      join opcoes_grupos g on g.id = o.grupo_id
      join cardapio c on c.id = g.cardapio_id
     where o.id = p_opcao and o.contar_stock and o.deletado_em is null
  ), comp as (
    select o.cozinha_id, pr.id as produto_id,
           quantidade_unidade_base((x ->> 'quantidade')::numeric, x ->> 'unidade', pr.categoria_medida) as por_unidade
      from o
      cross join jsonb_array_elements(o.componentes) x
      join produtos pr on pr.id::text = x ->> 'produto_id' and pr.deletado_em is null and pr.tipo_estoque = 'Longo Prazo'
     where jsonb_typeof(x -> 'quantidade') = 'number'
  )
  select min(greatest(floor((
           coalesce((select sum(case when e.tipo = 'Entrada' then e.quantidade else -e.quantidade end)
                       from estoque_longo_prazo e
                      where e.cozinha_id = comp.cozinha_id and e.produto_id = comp.produto_id and e.deletado_em is null), 0)
           - stock_prometido(comp.cozinha_id, comp.produto_id)) / comp.por_unidade), 0))::int
    from comp
   where comp.por_unidade > 0;
$$;
revoke execute on function unidades_opcao(uuid) from public, anon, authenticated;

-- Para a app do cliente: o que resta de cada opção que conta stock, nos pratos de uma cozinha
create or replace function unidades_opcoes(p_cozinha uuid) returns table (opcao_id uuid, restantes integer)
language sql stable security definer set search_path = public as $$
  select o.id, unidades_opcao(o.id)
    from opcoes o
    join opcoes_grupos g on g.id = o.grupo_id and g.deletado_em is null
    join cardapio c on c.id = g.cardapio_id and c.deletado_em is null
   where c.cozinha_id = p_cozinha and o.contar_stock and o.deletado_em is null
     and unidades_opcao(o.id) is not null;
$$;
revoke execute on function unidades_opcoes(uuid) from public, anon;
grant execute on function unidades_opcoes(uuid) to authenticated;

-- Pedido feito pela app: trava as opções que contam stock e confirma que chegam para todas as linhas
create or replace function pedidos_unidades_opcoes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_rest integer;
begin
  -- Só trava o cliente na app (dentro desta função current_user é o dono, por isso não serve e_escrita_cliente)
  if cliente_actual() is null or funcionario_actual() is not null then return new; end if;
  -- As opções chegam como ids (app) ou já como objectos {id, nome, preco_extra}
  for r in select coalesce(e ->> 'id', e #>> '{}') as opcao_id, sum(coalesce((i ->> 'qtd')::int, 1)) as qtd
             from jsonb_array_elements(coalesce(new.itens, '[]')) i
             cross join jsonb_array_elements(coalesce(i -> 'opcoes', '[]')) e
            where coalesce(e ->> 'id', e #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            group by 1 loop
    perform 1 from opcoes where id = r.opcao_id::uuid and contar_stock for update;
    if found then
      v_rest := unidades_opcao(r.opcao_id::uuid);
      if v_rest is not null and v_rest < r.qtd then
        raise exception 'opcao_esgotada' using errcode = 'P0001',
          detail = (select nome from opcoes where id = r.opcao_id::uuid);
      end if;
    end if;
  end loop;
  return new;
end $$;
revoke execute on function pedidos_unidades_opcoes() from public, anon, authenticated;
drop trigger if exists trg_pedidos_02_unidades_opcoes on pedidos;
create trigger trg_pedidos_02_unidades_opcoes before insert on pedidos
for each row execute function pedidos_unidades_opcoes();
