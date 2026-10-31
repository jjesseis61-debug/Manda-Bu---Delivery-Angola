-- A cozinha (ou o próprio estafeta) acompanha a posição do estafeta de um pedido a caminho.
-- Quem não gere a cozinha nem é o estafeta do pedido não vê.
begin;
\ir _helpers.psql
select plan(5);

select testes.def('cz', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa) values ('Viana', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), testes.u('cz'));
select testes.def('est', testes.funcionario('Emerson Mota', array['entregas.registar']));
select testes.def('cozinheiro', testes.funcionario('Cozinheiro', array['equipa.reconhecer']));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('residencial', -8.9200, 13.1800, testes.u('zona')));

create function pg_temp.pedido_em(p_cozinha uuid) returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, zona_id, cozinha_id, subtotal, itens, estado)
  values (testes.u('ana'), testes.u('casa'), testes.u('zona'), p_cozinha, 3000,
          jsonb_build_array(jsonb_build_object('nome', 'Calulu', 'qtd', 1, 'preco_unitario', 3000)), 'confirmado')
  returning id;
$$;
select testes.def('p', pg_temp.pedido_em(testes.u('cz')));
select testes.def('p_nao', pg_temp.pedido_em(testes.u('cz')));

-- O estafeta marca a saída e partilha a posição
select testes.funcionalidade('acompanhamento_entrega', true);
select testes.entrar_funcionario(testes.u('est'));
set local role authenticated;
select mudar_estado_pedido(testes.u('p'), 'em_entrega');
select registar_posicao_entrega(-8.9000, 13.1800, 12);
select testes.def('est_ve', posicao_pedido(testes.u('p'))::text);
reset role; select testes.sair();
select is(testes.v('est_ve')::jsonb ->> 'activo', 'true', 'o próprio estafeta vê a posição do seu pedido');

-- O gerente da cozinha vê o estafeta (nome + localização)
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('ger_ve', posicao_pedido(testes.u('p'))::text);
select testes.def('ger_nao', posicao_pedido(testes.u('p_nao'))::text);
reset role; select testes.sair();
select is(testes.v('ger_ve')::jsonb ->> 'estafeta_nome', 'Emerson', 'o gerente da cozinha vê o nome do estafeta');
select is((testes.v('ger_ve')::jsonb #>> '{estafeta,lat}')::numeric, -8.9, 'e vê onde ele está');
select is(testes.v('ger_nao')::jsonb ->> 'activo', 'false', 'pedido que não está a caminho: sem acompanhamento');

-- Um funcionário que não gere a cozinha nem é o estafeta não vê
select testes.entrar_funcionario(testes.u('cozinheiro'));
set local role authenticated;
select testes.def('e_coz', testes.erro(format('select posicao_pedido(%L)', testes.v('p'))));
reset role; select testes.sair();
select is(testes.v('e_coz'), '42501:sem_permissao', 'quem não gere a cozinha nem é o estafeta não acompanha');

select * from finish();
rollback;
