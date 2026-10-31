-- Cartão de selos (R1): conta pedidos pagos (global); ao atingir N, o próximo pedido tem frete grátis.
-- Com o interruptor desligado é no-op. Um pedido cancelado liberta o prémio.
begin;
\ir _helpers.psql
select plan(9);

select testes.def('rui', testes.cliente('Rui Selos'));
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaSelo', 'Própria', 700, 'Fixo') returning id)
  select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco, do_dia) values ('Prato Selo', 2000, true) returning id)
  select testes.def('prato', id) from m;
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('rui'), testes.u('casa'));

-- Cartão curto para o teste: 2 pedidos dão direito a frete grátis
update parametros set selos_necessarios = 2 where unico;

-- 1) Interruptor desligado por omissão
select is((select activa from funcionalidades where chave = 'selos'), false, 'o interruptor selos nasce desligado');

-- 2) Desligado: meus_selos não devolve nada
select testes.entrar(testes.u('rui'));
set local role authenticated;
select testes.def('off', coalesce(meus_selos()::text, 'NULO'));
reset role; select testes.sair();
select is(testes.v('off'), 'NULO', 'com o interruptor desligado, meus_selos é null');

select testes.funcionalidade('selos', true);

-- Um pedido pago (abaixo do necessário)
select testes.pagar(testes.pedido(testes.u('rui')));
select testes.entrar(testes.u('rui'));
set local role authenticated;
select testes.def('premio1', (meus_selos() ->> 'tem_premio'));
select testes.def('faltam1', (meus_selos() ->> 'faltam'));
reset role; select testes.sair();
select is(testes.v('premio1'), 'false', '1 pedido pago: ainda não há prémio');
select is(testes.v('faltam1'), '1', 'falta 1 pedido para o prémio');

-- Segundo pedido pago: atinge o necessário (2)
select testes.pagar(testes.pedido(testes.u('rui')));
select testes.entrar(testes.u('rui'));
set local role authenticated;
select testes.def('premio2', (meus_selos() ->> 'tem_premio'));
-- Novo pedido real (como a app): o trigger aplica o frete grátis
with p as (
  insert into pedidos (cliente_id, ponto_entrega_id, itens)
  values (testes.u('rui'), testes.u('casa'),
          jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', 1)))
  returning id)
select testes.def('novo', id) from p;
select testes.def('novo_premio', (select selo_premio from pedidos where id = testes.u('novo'))::text);
select testes.def('novo_taxa',   (select taxa_entrega from pedidos where id = testes.u('novo'))::text);
select testes.def('premio_depois', (meus_selos() ->> 'tem_premio'));
reset role; select testes.sair();
select is(testes.v('premio2'), 'true', '2 pedidos pagos: há prémio disponível');
select is(testes.v('novo_premio'), 'true', 'o novo pedido marca selo_premio');
select is(testes.v('novo_taxa'), '0', 'com prémio, o frete fica grátis (taxa 0)');
select is(testes.v('premio_depois'), 'false', 'o prémio foi usado: já não há outro');

-- Cancelar o pedido do prémio liberta-o de novo
update pedidos set estado = 'cancelado' where id = testes.u('novo');
select testes.entrar(testes.u('rui'));
set local role authenticated;
select testes.def('premio_cancelado', (meus_selos() ->> 'tem_premio'));
reset role; select testes.sair();
select is(testes.v('premio_cancelado'), 'true', 'cancelar o pedido do prémio devolve o prémio');

select * from finish();
rollback;
