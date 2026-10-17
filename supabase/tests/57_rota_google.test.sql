-- Gate B · Rota/ETA pelo Google em posicao_entrega, com fallback total à estimativa por distância.
-- Verifica: (1) com `rota_google` desligado usa sempre a estimativa, mesmo havendo cache;
-- (2) ligado e com cache recente usa a rota por estrada (fonte 'google', minutos do cache, polyline);
-- (3) ligado mas com cache velho (> 2 min) volta à estimativa.
begin;
\ir _helpers.psql
select plan(7);

-- Cenário: um pedido a caminho, com estafeta posicionado e destino com coordenadas
select testes.def('cliente', testes.cliente('Cliente Rota', 'Particular', '921000111'));
select testes.def('estafeta', testes.funcionario('Estafeta Rota', array['entregas.registar']));
select testes.def('ponto', testes.ponto('residencial', -8.90, 13.20));
select testes.def('pedido', testes.pedido(testes.u('cliente'), testes.u('ponto')));

-- Pôr o pedido a caminho e com entregador, sem accionar a máquina de estados
alter table pedidos disable trigger user;
update pedidos set estado = 'em_entrega', entregador_id = testes.u('estafeta') where id = testes.u('pedido');
alter table pedidos enable trigger user;

-- Posição do estafeta (longe do destino, para a estimativa dar claramente != do cache)
alter table posicoes_entregadores disable trigger user;
insert into posicoes_entregadores (funcionario_id, lat, lng, dispositivo_id)
values (testes.u('estafeta'), -8.96, 13.26, 'servidor');
alter table posicoes_entregadores enable trigger user;

-- Cache da rota por estrada (recente): 7 min, 3,2 km, com linha
insert into rotas_estafeta (pedido_id, minutos, km, polyline)
values (testes.u('pedido'), 7, 3.2, 'abc123');

select testes.funcionalidade('acompanhamento_entrega', true);
select testes.entrar(testes.u('cliente'));

-- (1) rota_google desligado: estimativa, e NÃO usa o cache (minutos != 7)
select is(posicao_entrega(testes.u('pedido')) ->> 'fonte', 'estimativa',
          'com rota_google desligado, a fonte é a estimativa');
select isnt(posicao_entrega(testes.u('pedido')) ->> 'minutos', '7',
            'com rota_google desligado, ignora o cache do Google');
select is(posicao_entrega(testes.u('pedido')) ->> 'polyline', null,
          'sem rota_google não devolve a linha da rota');

-- (2) rota_google ligado + cache recente: rota por estrada
select testes.funcionalidade('rota_google', true);
select is(posicao_entrega(testes.u('pedido')) ->> 'fonte', 'google',
          'com rota_google ligado e cache recente, a fonte é o Google');
select is(posicao_entrega(testes.u('pedido')) ->> 'minutos', '7',
          'usa os minutos do cache (rota por estrada)');
select is(posicao_entrega(testes.u('pedido')) ->> 'polyline', 'abc123',
          'devolve a linha da rota');

-- (3) cache velho (> 2 min): volta à estimativa
update rotas_estafeta set atualizado_em = now() - interval '5 minutes' where pedido_id = testes.u('pedido');
select is(posicao_entrega(testes.u('pedido')) ->> 'fonte', 'estimativa',
          'com o cache velho, volta à estimativa por distância');

select * from finish();
rollback;
