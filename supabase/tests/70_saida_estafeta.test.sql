-- Saída para entrega: com reserva, o entregador é SEMPRE o estafeta reservado (mesmo que um gerente
-- carregue por ele). Sem reserva, é quem marca. E o cliente passa a ver o nome do estafeta.
begin;
\ir _helpers.psql
select plan(5);

select testes.def('cz', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa) values ('Viana', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), testes.u('cz'));
select testes.def('est1', testes.funcionario('Emerson Mota', array['entregas.registar']));
select testes.def('est2', testes.funcionario('Bruno Alves', array['entregas.registar']));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('ponto', testes.ponto('residencial', -8.9200, 13.1800, testes.u('zona')));

create function pg_temp.pedido_confirmado() returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, zona_id, cozinha_id, subtotal, itens, estado)
  values (testes.u('ana'), testes.u('ponto'), testes.u('zona'), testes.u('cz'), 3000,
          jsonb_build_array(jsonb_build_object('nome', 'Calulu', 'qtd', 1, 'preco_unitario', 3000)), 'confirmado')
  returning id;
$$;

-- Ajuste 1: o gerente atribui ao est1 e carrega "Saiu para entrega" por ele.
-- O entregador tem de ficar o est1 (não o gerente), e a reserva liberta-se.
select testes.def('p', pg_temp.pedido_confirmado());
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select atribuir_entrega(testes.u('p'), testes.u('est1'));
select mudar_estado_pedido(testes.u('p'), 'em_entrega');
reset role; select testes.sair();
select is((select entregador_id from pedidos where id = testes.u('p')), testes.u('est1'),
          'gerente marca a saída de um pedido reservado: o entregador fica o estafeta reservado, não o gerente');
select ok((select estado = 'em_entrega' and atribuido_a is null from pedidos where id = testes.u('p')),
          'o pedido fica em entrega e a reserva liberta-se');

-- Sem reserva (recolha directa no balcão): o entregador é quem marca a saída.
select testes.def('pd', pg_temp.pedido_confirmado());
select testes.entrar_funcionario(testes.u('est2'));
set local role authenticated;
select mudar_estado_pedido(testes.u('pd'), 'em_entrega');
reset role; select testes.sair();
select is((select entregador_id from pedidos where id = testes.u('pd')), testes.u('est2'),
          'sem reserva, quem marca a saída fica como entregador');

-- Ajuste 3: o cliente vê o primeiro nome do estafeta do seu pedido.
select testes.funcionalidade('acompanhamento_entrega', true);
select testes.entrar_funcionario(testes.u('est1'));
set local role authenticated;
select registar_posicao_entrega(-8.9000, 13.1800, 12);
reset role; select testes.sair();
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('ve', posicao_entrega(testes.u('p'))::text);
reset role; select testes.sair();
select is(testes.v('ve')::jsonb ->> 'estafeta_nome', 'Emerson', 'o cliente vê o primeiro nome do estafeta');
select is((testes.v('ve')::jsonb #>> '{estafeta,lat}')::numeric, -8.9, 'e continua a ver onde ele está');

select * from finish();
rollback;
