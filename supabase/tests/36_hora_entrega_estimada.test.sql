-- Hora de entrega estimada: pedido normal (+ tempo_entrega_min) e pedido de grupo (hora do grupo)
begin;
\ir _helpers.psql
select plan(5);

select testes.funcionalidade('multi_cozinha', false);
select testes.funcionalidade('pedidos_grupo', true);
with z as (insert into zonas (nome, tipo, taxa) values ('Viana', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Chocos', 6000) returning id) select testes.def('chocos', id) from m;
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('ponto', testes.ponto('residencial', null, null, testes.u('zona')));
select testes.def('esc', testes.ponto('empresa', -8.83, 13.24, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('ponto')), (testes.u('ana'), testes.u('esc'));

select is((select tempo_entrega_min from parametros where unico), 45, 'tempo de entrega por defeito: 45 minutos');

select testes.entrar(testes.u('ana'));
set local role authenticated;
-- o telemóvel tenta mandar uma hora à sua escolha: é ignorada
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens, hora_prometida)
           values (testes.u('ana'), testes.u('ponto'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 1)),
                   now() + interval '5 minutes') returning id)
select testes.def('p', id) from x;
with g as (insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
           values (testes.u('esc'), now() + interval '3 hours', now() + interval '2 hours', 'individual') returning id)
select testes.def('g', id) from g;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('ana'), testes.u('g'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 1))) returning id)
select testes.def('pg', id) from x;
reset role;
select testes.sair();

select is((select hora_prometida from pedidos where id = testes.u('p')), now() + interval '45 minutes',
          'pedido normal: hora do pedido + 45 minutos (a hora mandada pelo telemóvel é ignorada)');
select is((select hora_prometida from pedidos where id = testes.u('pg')), (select hora_entrega from pedidos_grupo where id = testes.u('g')),
          'pedido de grupo: a hora de entrega do grupo');

-- a direcção muda o tempo para 60 minutos
select testes.def('dir', testes.funcionario('Direcção', array['plataforma.parametros']));
select testes.entrar_funcionario(testes.u('dir'));
set local role authenticated;
select alterar_parametros('{"tempo_entrega_min": 60}');
select testes.def('e_curto', testes.erro($$select alterar_parametros('{"tempo_entrega_min": 5}')$$));
reset role;
select is((select tempo_entrega_min from parametros where unico), 60, 'a direcção ajusta o tempo de entrega');
select ok(testes.v('e_curto') <> 'sem_erro', 'tempo de entrega fora de 10–240 minutos é recusado');

select * from finish();
rollback;
