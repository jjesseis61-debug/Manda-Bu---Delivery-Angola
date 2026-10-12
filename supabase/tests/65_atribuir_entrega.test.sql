-- Atribuição explícita de entregas: o gerente reserva a um estafeta; outro estafeta não pode pegar; o
-- reservado aceita (em entrega); recusar liberta; a reserva expira; barreiras de permissão.
begin;
\ir _helpers.psql
select plan(8);

select testes.def('cz', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa) values ('Viana', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), testes.u('cz'));
select testes.def('est1', testes.funcionario('Estafeta 1', array['entregas.registar']));
select testes.def('est2', testes.funcionario('Estafeta 2', array['entregas.registar']));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('ponto', testes.ponto('residencial', null, null, testes.u('zona')));

create function pg_temp.pedido_confirmado() returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, zona_id, cozinha_id, subtotal, itens, estado)
  values (testes.u('ana'), testes.u('ponto'), testes.u('zona'), testes.u('cz'), 3000,
          jsonb_build_array(jsonb_build_object('nome', 'Calulu', 'qtd', 1, 'preco_unitario', 3000)), 'confirmado')
  returning id;
$$;
select testes.def('p', pg_temp.pedido_confirmado());

-- Gerente atribui o pedido ao estafeta 1
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select atribuir_entrega(testes.u('p'), testes.u('est1'));
select testes.def('n_estafetas', (select count(*)::int from estafetas_para_atribuir(testes.u('cz'))));
reset role;
select testes.sair();
select is((select atribuido_a from pedidos where id = testes.u('p')), testes.u('est1'), 'o pedido fica reservado ao estafeta 1');
select is(testes.v('n_estafetas')::int, 2, 'o seletor lista os 2 estafetas');

-- O estafeta 1 vê "a mim"; o estafeta 2 vê reservado a outro
select testes.entrar_funcionario(testes.u('est1'));
set local role authenticated;
select testes.def('mim1', (select atribuido_a_mim::text from pedidos_operador() where pedido_id = testes.u('p')));
reset role; select testes.sair();
select testes.entrar_funcionario(testes.u('est2'));
set local role authenticated;
select testes.def('mim2', (select atribuido_a_mim::text from pedidos_operador() where pedido_id = testes.u('p')));
select testes.def('nome2', (select atribuido_a_nome from pedidos_operador() where pedido_id = testes.u('p')));
select testes.def('e_outro', testes.erro(format($$select mudar_estado_pedido(%L, 'em_entrega')$$, testes.u('p'))));
reset role; select testes.sair();
select ok(testes.v('mim1') = 'true' and testes.v('mim2') = 'false' and testes.v('nome2') = 'Estafeta 1',
          'o reservado vê "a mim"; o outro vê reservado ao Estafeta 1');
select matches(testes.v('e_outro'), '^42501', 'outro estafeta não pode pegar num pedido reservado');

-- O estafeta 1 aceita (marca em entrega): fica entregador e a reserva liberta-se
select testes.entrar_funcionario(testes.u('est1'));
set local role authenticated;
select mudar_estado_pedido(testes.u('p'), 'em_entrega');
reset role; select testes.sair();
select ok((select estado = 'em_entrega' and entregador_id = testes.u('est1') and atribuido_a is null
             from pedidos where id = testes.u('p')),
          'o reservado aceita: fica entregador e a reserva liberta-se');

-- Barreira: um estafeta não pode atribuir
select testes.def('p_barr', pg_temp.pedido_confirmado());
select testes.entrar_funcionario(testes.u('est1'));
set local role authenticated;
select testes.def('e_est_atribui', testes.erro(format($$select atribuir_entrega(%L, %L)$$, testes.v('p_barr')::uuid, testes.u('est2'))));
reset role; select testes.sair();
select matches(testes.v('e_est_atribui'), '^42501', 'um estafeta não pode atribuir entregas');

-- Recusar liberta a reserva
select testes.def('p2', pg_temp.pedido_confirmado());
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select atribuir_entrega(testes.u('p2'), testes.u('est1'));
reset role; select testes.sair();
select testes.entrar_funcionario(testes.u('est1'));
set local role authenticated;
select recusar_entrega(testes.u('p2'));
reset role; select testes.sair();
select is((select atribuido_a from pedidos where id = testes.u('p2')), null::uuid, 'recusar liberta a reserva');

-- A reserva expira: reservado ao est1 mas há 20 min -> o est2 já pode pegar
select testes.def('p3', pg_temp.pedido_confirmado());
update pedidos set atribuido_a = testes.u('est1'), atribuido_em = now() - interval '20 minutes' where id = testes.u('p3');
select testes.entrar_funcionario(testes.u('est2'));
set local role authenticated;
select testes.def('e_expira', testes.erro(format($$select mudar_estado_pedido(%L, 'em_entrega')$$, testes.u('p3'))));
reset role; select testes.sair();
select is(testes.v('e_expira'), 'sem_erro', 'reserva expirada: outro estafeta já pode pegar (sem erro)');

select * from finish();
rollback;
