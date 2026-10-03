-- Relatórios com pratos sem ficha técnica e métricas de turno com pedidos sem hora prometida
begin;
\ir _helpers.psql
select plan(5);

select testes.funcionalidade('multi_cozinha', false);
select testes.def('cz', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa) values ('Viana', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Chocos', 6000) returning id) select testes.def('chocos', id) from m;
with m as (insert into cardapio (nome, preco) values ('Arroz', 1000) returning id) select testes.def('arroz', id) from m;
with m as (insert into cardapio (nome, preco) values ('Zimbo', 1500) returning id) select testes.def('zimbo', id) from m;
select testes.def('dir', testes.funcionario('Direcção', array['relatorios.exportar', 'equipa.reconhecer', 'pedidos.gerir']));
insert into turnos (data, funcionario_id, cozinha_id, periodo, hora_inicio, hora_fim)
values (hoje_luanda(), testes.u('dir'), testes.u('cz'), 'manha', '00:00', '23:59');
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('ponto', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('ponto'));

-- 3 Chocos, 2 Arroz, 1 Zimbo (nenhum com ficha técnica)
select testes.entrar(testes.u('ana'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens) values (testes.u('ana'), testes.u('ponto'),
  jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 2), jsonb_build_object('cardapio_id', testes.u('arroz'), 'qtd', 2))) returning id)
select testes.def('p1', id) from x;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens) values (testes.u('ana'), testes.u('ponto'),
  jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 1), jsonb_build_object('cardapio_id', testes.u('zimbo'), 'qtd', 1))) returning id)
select testes.def('p2', id) from x;
reset role;
select testes.sair();
-- todos os pedidos têm hora prometida (+45 min); o segundo chegou tarde
update pedidos set hora_prometida = now() - interval '2 hours' where id = testes.u('p2');
select testes.pagar(testes.u('p1'));
select testes.pagar(testes.u('p2'));

select testes.entrar_funcionario(testes.u('dir'));
set local role authenticated;
select testes.def('rel', relatorio_cozinha(testes.u('cz'), hoje_luanda() - 1, hoje_luanda()));
select testes.def('met', (select row_to_json(m)::text from metricas_turno(testes.u('cz'), hoje_luanda() - extract(isodow from hoje_luanda())::int + 1) m));
reset role;

select is(testes.v('rel')::jsonb -> 'prato_mais_pedido' ->> 'nome', 'Chocos', 'prato mais pedido sem ficha técnica: o prato do cardápio com mais unidades');
select is((testes.v('rel')::jsonb -> 'prato_mais_pedido' ->> 'quantidade')::numeric, 3::numeric, 'e a quantidade só desse prato (2 + 1)');
select is((testes.v('met')::jsonb ->> 'entregas')::int, 2, 'métricas: contam todas as entregas do turno');
select is((testes.v('met')::jsonb ->> 'entregas_a_horas')::int, 1, 'uma chegou dentro da hora prometida, a outra tarde');
select is((testes.v('met')::jsonb ->> 'pct_a_horas')::numeric, 50::numeric, 'percentagem a horas: 50%');

select * from finish();
rollback;
