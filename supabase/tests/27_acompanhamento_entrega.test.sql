-- I11 · Acompanhamento da entrega: o estafeta envia a posição, o cliente vê-a só no seu pedido
begin;
\ir _helpers.psql
select plan(14);

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('rui', testes.cliente('Rui Costa'));
select testes.def('casa', testes.ponto('residencial', -8.9200, 13.1800, testes.u('zona')));
select testes.def('pedido', testes.pedido(testes.u('ana'), testes.u('casa')));
select testes.def('estafeta', testes.funcionario('Estafeta', array['entregas.registar']));
select testes.def('cozinheiro', testes.funcionario('Cozinheiro', array['equipa.reconhecer']));

-- O estafeta marca "a caminho": fica como entregador do pedido
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select mudar_estado_pedido(testes.u('pedido'), 'em_entrega');
select testes.def('off', registar_posicao_entrega(-8.9000, 13.1800));
reset role;
select is((select entregador_id from pedidos where id = testes.u('pedido')), testes.u('estafeta'),
          'quem marca o pedido a caminho fica como entregador');
select is(testes.v('off')::int, 0, 'acompanhamento_entrega desligado: a posição não é guardada');

select testes.funcionalidade('acompanhamento_entrega', true);
set local role authenticated;
select testes.def('n', registar_posicao_entrega(-8.9000, 13.1800, 12));
select testes.def('e_pos', testes.erro('select registar_posicao_entrega(95, 13)'));
select testes.def('e_tabela', testes.erro('select count(*) from posicoes_entregadores'));
reset role;
select is(testes.v('n')::int, 1, 'com o interruptor: posição guardada, 1 pedido a caminho');
select is(testes.v('e_pos'), 'P0001:posicao_invalida', 'coordenadas fora do mapa: recusadas');
select ok(testes.v('e_tabela') like '42501:%', 'a tabela de posições não se lê directamente');

-- O cliente vê o estafeta e o tempo estimado do seu pedido
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('ana_ve', posicao_entrega(testes.u('pedido'))::text);
reset role;
select is((testes.v('ana_ve')::jsonb #>> '{estafeta,lat}')::numeric, -8.9, 'o cliente vê onde está o estafeta');
select is((testes.v('ana_ve')::jsonb ->> 'distancia_km')::numeric, 2.2, 'distância ao destino (2,2 km)');
select is((testes.v('ana_ve')::jsonb ->> 'minutos')::int, 8, 'tempo estimado: 2,2 km × 1,4 a 25 km/h ≈ 8 minutos');

-- Outro cliente e quem não é estafeta não têm acesso
select testes.entrar(testes.u('rui'));
set local role authenticated;
select testes.def('e_rui', testes.erro(format('select posicao_entrega(%L)', testes.v('pedido'))));
reset role;
select is(testes.v('e_rui'), 'P0001:pedido_inexistente', 'outro cliente não vê a posição deste pedido');
select testes.entrar_funcionario(testes.u('cozinheiro'));
set local role authenticated;
select testes.def('e_coz', testes.erro('select registar_posicao_entrega(-8.9, 13.18)'));
reset role;
select is(testes.v('e_coz'), '42501:sem_permissao', 'sem entregas.registar não se envia posição');

-- Posição com mais de 10 minutos não se mostra
update posicoes_entregadores set atualizado_em = now() - interval '11 minutes' where funcionario_id = testes.u('estafeta');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('velha', posicao_entrega(testes.u('pedido'))::text);
reset role;
select is(testes.v('velha')::jsonb -> 'estafeta', 'null'::jsonb, 'posição antiga (mais de 10 minutos) não se mostra');

-- Entregue: a posição é apagada e o acompanhamento termina
select testes.pagar(testes.u('pedido'));
select is((select count(*)::int from posicoes_entregadores where funcionario_id = testes.u('estafeta')), 0,
          'pedido entregue: a posição do estafeta é apagada');
set local role authenticated;
select testes.def('fim', posicao_entrega(testes.u('pedido'))::text);
reset role;
select is(testes.v('fim')::jsonb ->> 'activo', 'false', 'depois da entrega já não há acompanhamento');

select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('depois', registar_posicao_entrega(-8.9000, 13.1800));
reset role;
select is(testes.v('depois')::int, 0, 'sem pedidos a caminho a app pára de enviar (devolve 0)');

select * from finish();
rollback;
