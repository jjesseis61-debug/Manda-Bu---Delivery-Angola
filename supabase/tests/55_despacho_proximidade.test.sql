-- Sugestão de despacho: o estafeta online mais perto de cada pedido pronto a sair.
begin;
\ir _helpers.psql
select plan(3);

select testes.def('est', testes.funcionario('Estafeta Perto', array['entregas.registar']));
insert into posicoes_entregadores (funcionario_id, lat, lng, dispositivo_id)
values (testes.u('est'), -8.841, 13.231, 'servidor');
select testes.def('op', testes.funcionario('Despacho', array['pedidos.gerir']));
with z as (insert into zonas (nome, tipo, taxa) values ('Zona Despacho', 'Própria', 300) returning id)
select testes.def('zona', id) from z;
select testes.def('ponto', testes.ponto('residencial', -8.84, 13.23, testes.u('zona')));
select testes.def('cli', testes.cliente('Cliente Despacho'));
insert into pedidos (id, cliente_id, ponto_entrega_id, subtotal, estado)
values ('00000000-0000-0000-0000-0000000d0001', testes.u('cli'), testes.u('ponto'), 3000, 'confirmado');

select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select testes.def('sug', sugestao_despacho(cozinha_padrao()));
reset role;
select testes.sair();
select is(jsonb_array_length(testes.v('sug')::jsonb), 1, 'um pedido pronto a despachar');
select is(testes.v('sug')::jsonb -> 0 -> 'sugestao' ->> 'nome', 'Estafeta Perto',
          'sugere o estafeta online mais perto');

-- Um estafeta (sem pedidos.gerir) não vê a sugestão de despacho
select testes.entrar_funcionario(testes.u('est'));
set local role authenticated;
select testes.def('e_sug', testes.erro(format($$select sugestao_despacho(%L)$$, cozinha_padrao())));
reset role;
select testes.sair();
select ok(testes.v('e_sug') like '42501%', 'sugestao_despacho exige pedidos.gerir');

select * from finish();
rollback;
