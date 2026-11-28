-- Impacto de preço: conta os pedidos atendidos (entregue_pago) a cada preço de um prato, os clientes
-- distintos e o total; os cancelados/estornados ficam num sub-total à parte. Só auditoria.ver consulta.
begin;
\ir _helpers.psql
select plan(10);

-- Um prato (basta o id que fica congelado em pedidos.itens como cardapio_id) e três clientes.
select testes.def('card', gen_random_uuid());
select testes.def('c1', testes.cliente('Cliente 1'));
select testes.def('c2', testes.cliente('Cliente 2'));
select testes.def('c3', testes.cliente('Cliente 3'));

-- O gatilho gerar_venda_pedido é "after update of estado", por isso um insert directo com o estado
-- já definido não o dispara — semeamos os pedidos sem a maquinaria de vendas/stock.
-- Preço 2000: A (c1, entregue, 1), B (c2, entregue, 2), C (c1, cancelado). Preço 2500: D (c1), E (c3).
insert into pedidos (cliente_id, estado, subtotal, itens) values
  (testes.u('c1'), 'entregue_pago', 2000, jsonb_build_array(jsonb_build_object('cardapio_id', testes.v('card'), 'nome', 'Prato', 'qtd', 1, 'preco_unitario', 2000))),
  (testes.u('c2'), 'entregue_pago', 4000, jsonb_build_array(jsonb_build_object('cardapio_id', testes.v('card'), 'nome', 'Prato', 'qtd', 2, 'preco_unitario', 2000))),
  (testes.u('c1'), 'cancelado',     2000, jsonb_build_array(jsonb_build_object('cardapio_id', testes.v('card'), 'nome', 'Prato', 'qtd', 1, 'preco_unitario', 2000))),
  (testes.u('c1'), 'entregue_pago', 2500, jsonb_build_array(jsonb_build_object('cardapio_id', testes.v('card'), 'nome', 'Prato', 'qtd', 1, 'preco_unitario', 2500))),
  (testes.u('c3'), 'entregue_pago', 2500, jsonb_build_array(jsonb_build_object('cardapio_id', testes.v('card'), 'nome', 'Prato', 'qtd', 1, 'preco_unitario', 2500)));

-- Um auditor (auditoria.ver) e um estranho (sem a permissão).
select testes.def('auditor', testes.funcionario('Auditor', array['auditoria.ver']));
select testes.def('estranho', testes.funcionario('Estranho', array['pedidos.gerir']));

select testes.entrar_funcionario(testes.u('auditor'));
set local role authenticated;
select testes.def('n_precos', (select count(*)::int from impacto_preco_prato(testes.u('card'))));
select testes.def('e2000', (select pedidos_entregues from impacto_preco_prato(testes.u('card')) where preco = 2000));
select testes.def('cl2000', (select clientes from impacto_preco_prato(testes.u('card')) where preco = 2000));
select testes.def('t2000', (select total_kz from impacto_preco_prato(testes.u('card')) where preco = 2000));
select testes.def('x2000', (select pedidos_cancelados from impacto_preco_prato(testes.u('card')) where preco = 2000));
select testes.def('e2500', (select pedidos_entregues from impacto_preco_prato(testes.u('card')) where preco = 2500));
select testes.def('t2500', (select total_kz from impacto_preco_prato(testes.u('card')) where preco = 2500));
select testes.def('mov_todos', (select count(*)::int from movimento_preco_prato(testes.u('card'))));
select testes.def('mov_2500', (select count(*)::int from movimento_preco_prato(testes.u('card'), 2500)));
reset role; select testes.sair();

select is(testes.v('n_precos')::int, 2, 'há dois preços distintos cobrados');
select is(testes.v('e2000')::int, 2, 'preço 2000: 2 pedidos atendidos (entregues)');
select is(testes.v('cl2000')::int, 2, 'preço 2000: 2 clientes distintos');
select is(testes.v('t2000')::bigint, 6000::bigint, 'preço 2000: total recebido 1×2000 + 2×2000 = 6000');
select is(testes.v('x2000')::int, 1, 'preço 2000: 1 pedido cancelado, fora do total');
select is(testes.v('e2500')::int, 2, 'preço 2500: 2 pedidos atendidos');
select is(testes.v('t2500')::bigint, 5000::bigint, 'preço 2500: total recebido 2×2500 = 5000');
select is(testes.v('mov_todos')::int, 5, 'o movimento lista todas as linhas do prato');
select is(testes.v('mov_2500')::int, 2, 'o movimento filtra por um preço');

-- Quem não tem auditoria.ver não consulta o impacto.
select testes.entrar_funcionario(testes.u('estranho'));
set local role authenticated;
select testes.def('e_estranho', testes.erro(format($$select * from impacto_preco_prato(%L)$$, testes.u('card'))));
reset role; select testes.sair();
select matches(testes.v('e_estranho'), '^42501', 'sem auditoria.ver NÃO vê o impacto (42501)');

select * from finish();
rollback;
