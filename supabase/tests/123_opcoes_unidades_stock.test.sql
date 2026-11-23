-- Opções que contam o stock (gasosa em lata): o que resta vem do stock menos o prometido em pedidos,
-- o pedido da app não passa do que resta, cancelar devolve e a venda não conta duas vezes.
begin;
\ir _helpers.psql
select plan(9);

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
select testes.funcionalidade('pratos_montaveis', true);
with m as (insert into cardapio (nome, preco) values ('Serve o teu prato', 500) returning id) select testes.def('prato', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('prato'), 'Bebida', 0, 1) returning id)
select testes.def('g', id) from g;
with p as (insert into produtos (nome, tipo_estoque, categoria_medida) values ('Gasosa lata 33 cl', 'Longo Prazo', 'Unidade') returning id)
select testes.def('lata', id) from p;
with o as (insert into opcoes (grupo_id, nome, preco_extra, contar_stock, componentes)
           values (testes.u('g'), 'Gasosa', 500, true,
                   jsonb_build_array(jsonb_build_object('produto_id', testes.v('lata'), 'quantidade', 1, 'unidade', 'un')))
           returning id)
select testes.def('gasosa', id) from o;
with o as (insert into opcoes (grupo_id, nome, preco_extra) values (testes.u('g'), 'Água', 200) returning id) select testes.def('agua', id) from o;
insert into estoque_longo_prazo (cozinha_id, produto_id, tipo, quantidade)
values (cozinha_padrao(), testes.u('lata'), 'Entrada', 3);

select is(unidades_opcao(testes.u('gasosa')), 3, 'restam as 3 latas do stock');
select is(unidades_opcao(testes.u('agua')), null, 'opção que não conta stock: sem contagem');

select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));
create function pg_temp.pedir(p_opcao text, p_qtd int) returns text language plpgsql as $$
declare v uuid;
begin
  perform testes.entrar(testes.u('ana'));
  set local role authenticated;
  insert into pedidos (cliente_id, ponto_entrega_id, itens)
  values (testes.u('ana'), testes.u('casa'), jsonb_build_array(jsonb_build_object(
            'cardapio_id', testes.v('prato'), 'qtd', p_qtd, 'opcoes', jsonb_build_array(testes.v(p_opcao)))))
  returning id into v;
  reset role;
  perform testes.sair();
  return v::text;
exception when others then
  reset role;
  perform testes.sair();
  return sqlstate || ':' || sqlerrm;
end $$;

select testes.def('p1', pg_temp.pedir('gasosa', 2));
select is(unidades_opcao(testes.u('gasosa')), 1, 'o pedido promete 2 latas: resta 1');
select is(pg_temp.pedir('gasosa', 2), 'P0001:opcao_esgotada', 'não se pede mais do que resta');

select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('lista', (select jsonb_agg(to_jsonb(u)) from unidades_opcoes(cozinha_padrao()) u));
select testes.def('e_func', testes.erro(format($$select unidades_opcao(%L)$$, testes.v('gasosa'))));
reset role;
select testes.sair();
select ok(testes.v('lista')::jsonb = jsonb_build_array(jsonb_build_object('opcao_id', testes.v('gasosa'), 'restantes', 1)),
          'a app vê o que resta só das opções que contam stock');
select ok(testes.v('e_func') like '42501:%', 'a função interna não se chama directamente');

update pedidos set estado = 'cancelado', motivo_cancelamento = 'Desistiu' where id = testes.u('p1');
select is(unidades_opcao(testes.u('gasosa')), 3, 'cancelar devolve as latas');

-- Entregue e pago: a venda desconta do stock e o pedido deixa de contar como prometido (não conta duas vezes)
select testes.def('p2', pg_temp.pedir('gasosa', 2));
select testes.pagar(testes.u('p2'));
select is(unidades_opcao(testes.u('gasosa')), 1, 'depois da venda: 3 - 2 = 1, sem contar duas vezes');
select is(pg_temp.pedir('agua', 5) ~ '^[0-9a-f-]{36}$', true, 'opção sem contagem de stock pede-se à vontade');

select * from finish();
rollback;
