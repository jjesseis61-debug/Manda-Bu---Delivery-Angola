-- I2 · O desconto de indicação nunca passa o valor do pedido (subtotal + taxa)
begin;
\ir _helpers.psql
select plan(11);

select testes.funcionalidade('indicacao', true);
select testes.def('ana', testes.cliente('Ana Indicadora'));
with z as (insert into zonas (nome, tipo, taxa) values ('Sem taxa', 'Própria', 0) returning id)
select testes.def('zona0', id) from z;
with z as (insert into zonas (nome, tipo, taxa) values ('Taxa 100', 'Própria', 100) returning id)
select testes.def('zona100', id) from z;
with m as (insert into cardapio (nome, preco) values ('Pastel', 300) returning id)
select testes.def('pastel', id) from m;
with m as (insert into cardapio (nome, preco) values ('Muamba', 2500) returning id)
select testes.def('muamba', id) from m;

-- Indicado com pedido mais pequeno do que o desconto (300 < 500), sem taxa
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno'));
select testes.def('casa_bruno', testes.ponto('residencial', null, null, testes.u('zona0')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('bruno'), testes.u('casa_bruno'));
select testes.entrar(testes.u('bruno'));
set local role authenticated;
select testes.def('orc', orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('pastel'), 'qtd', 1)),
                                          testes.u('casa_bruno')));
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('bruno'), testes.u('casa_bruno'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('pastel'), 'qtd', 1)))
           returning id)
select testes.def('p_bruno', id) from x;
select testes.def('e_credito', testes.erro(format($$select usar_credito(%L, 100)$$, testes.v('p_bruno'))));
reset role;
select testes.sair();

select results_eq($$select (testes.v('orc')::jsonb ->> 'desconto')::int, (testes.v('orc')::jsonb ->> 'total')::int$$,
                  $$values (300, 0)$$, 'orçamento: desconto limitado a 300 (valor do pedido), total 0');
select results_eq(format($$select subtotal::int, taxa_entrega::int, desconto_indicacao::int,
                                  (subtotal + taxa_entrega - desconto_indicacao)::int from pedidos where id = %L$$, testes.u('p_bruno')),
                  $$values (300, 0, 300, 0)$$, 'pedido: desconto 300, valor final 0 (nunca negativo)');
select ok(testes.v('e_credito') <> 'sem_erro', 'crédito não pode ser usado num pedido de valor final 0');

-- Entregue e pago com valor final 0: sem parcelas, vendas somam 0
select testes.def('entregador', testes.funcionario('Entregador', array['entregas.registar']));
select testes.entrar_funcionario(testes.u('entregador'));
select lives_ok(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, '[]')$$,
                       testes.u('p_bruno'), testes.caixa()),
                'entregue e pago com valor final 0 (sem parcelas)');
select testes.sair();
select is((select sum(valor_total)::int from vendas where pedido_id = testes.u('p_bruno')), 0, 'venda gerada com total 0');
select is((select desconto_usado from ligacoes_indicacao where indicado_id = testes.u('bruno')), true,
          'desconto de uso único: fica usado mesmo que só 300 dos 500 tenham sido aplicados');

-- O pedido seguinte já não tem desconto (a parte que sobrou não passa)
select testes.entrar(testes.u('bruno'));
set local role authenticated;
select testes.def('orc2', orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)),
                                           testes.u('casa_bruno')));
reset role;
select testes.sair();
select is((testes.v('orc2')::jsonb ->> 'desconto')::int, 0, 'pedido seguinte sem desconto');

-- Com taxa: o limite é subtotal + taxa (300 + 100 = 400)
select testes.def('carla', testes.indicado(testes.u('ana'), 'Carla'));
select testes.def('casa_carla', testes.ponto('residencial', null, null, testes.u('zona100')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('carla'), testes.u('casa_carla'));
select testes.entrar(testes.u('carla'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('carla'), testes.u('casa_carla'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('pastel'), 'qtd', 1)))
           returning id)
select testes.def('p_carla', id) from x;
reset role;
select testes.sair();
select results_eq(format($$select desconto_indicacao::int, (subtotal + taxa_entrega - desconto_indicacao)::int
                             from pedidos where id = %L$$, testes.u('p_carla')),
                  $$values (400, 0)$$, 'com taxa de 100: desconto 400 (subtotal + taxa), valor final 0');

-- Pedido maior do que o desconto: desconto inteiro, como antes
select testes.def('dora', testes.indicado(testes.u('ana'), 'Dora'));
select testes.def('casa_dora', testes.ponto('residencial', null, null, testes.u('zona100')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('dora'), testes.u('casa_dora'));
select testes.entrar(testes.u('dora'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('dora'), testes.u('casa_dora'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)))
           returning id)
select testes.def('p_dora', id) from x;
reset role;
select testes.sair();
select results_eq(format($$select desconto_indicacao::int, (subtotal + taxa_entrega - desconto_indicacao)::int
                             from pedidos where id = %L$$, testes.u('p_dora')),
                  $$values (500, 2100)$$, 'pedido maior: desconto inteiro de 500 (2.500 + 100 − 500 = 2.100)');

-- Pedidos criados pelo servidor (sem itens do cardápio) seguem a mesma regra
select testes.def('eva', testes.indicado(testes.u('ana'), 'Eva'));
with x as (insert into pedidos (cliente_id, ponto_entrega_id, subtotal, taxa_entrega)
           values (testes.u('eva'), testes.ponto('empresa'), 200, 0) returning desconto_indicacao)
select testes.def('desc_eva', desconto_indicacao) from x;
select is(testes.v('desc_eva')::int, 200, 'pedido criado pelo servidor: desconto limitado a 200');
select ok(not exists (select 1 from pedidos where subtotal + taxa_entrega - desconto_indicacao < 0),
          'nenhum pedido com valor final negativo');

select * from finish();
rollback;
