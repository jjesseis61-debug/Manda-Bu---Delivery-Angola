-- "Quem preparou": ao marcar o pedido em_preparacao, fica o funcionário na ficha do pedido.
begin;
\ir _helpers.psql
select plan(4);

select testes.def('cli', testes.cliente('Cliente Prep'));
select testes.def('cozinheiro', testes.funcionario('Cozinheiro Prep', array['pedidos.gerir']));
select testes.def('ped', testes.pedido(testes.u('cli')));

-- Antes: sem preparador
select is((select preparado_por from pedidos where id = testes.u('ped')), null, 'pedido novo não tem preparador');

-- O cozinheiro marca em preparação
select testes.def('sql_prep', format($f$select mudar_estado_pedido(%L, 'em_preparacao')$f$, testes.u('ped')));
select testes.entrar_funcionario(testes.u('cozinheiro'));
set local role authenticated;
select lives_ok(testes.v('sql_prep'), 'o cozinheiro marca o pedido em preparação');
reset role; select testes.sair();

select is((select preparado_por from pedidos where id = testes.u('ped')), testes.u('cozinheiro'),
          'ao entrar em_preparacao fica o funcionário como preparador');
select isnt((select preparado_em from pedidos where id = testes.u('ped')), null,
            'fica a hora da preparação');

select * from finish();
rollback;
