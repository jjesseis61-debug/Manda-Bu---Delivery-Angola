-- Agendamento do cardápio: janela por data/hora. O cliente só vê e só pede dentro da janela;
-- o gestor (cozinhas.gerir) vê tudo para poder agendar.
begin;
\ir _helpers.psql
select plan(10);

select testes.def('ana', testes.cliente('Ana Agenda'));
select testes.def('gestor', testes.funcionario('Gestor Cardápio', array['cozinhas.gerir']));
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaAg', 'Própria', 700, 'Fixo') returning id)
  select testes.def('zona', id) from z;
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));

-- Três pratos: um dentro da janela (agora), um agendado para amanhã, um já expirado
with m as (insert into cardapio (nome, preco) values ('Agora', 2000) returning id)
  select testes.def('agora', id) from m;
with m as (insert into cardapio (nome, preco, disponivel_de) values ('Futuro', 2000, now() + interval '1 day') returning id)
  select testes.def('futuro', id) from m;
with m as (insert into cardapio (nome, preco, disponivel_ate) values ('Expirado', 2000, now() - interval '1 hour') returning id)
  select testes.def('expirado', id) from m;

-- 1) O predicado da janela
select is(janela_aberta(null, null), true, 'sem limites: aberta');
select is(janela_aberta(now() + interval '1 day', null), false, 'início no futuro: fechada');
select is(janela_aberta(null, now() - interval '1 hour'), false, 'fim no passado: fechada');
select is(janela_aberta(now() - interval '1 hour', now() + interval '1 hour'), true, 'dentro da janela: aberta');

-- 2) Leitura (RLS): o cliente só vê o que está dentro da janela
select testes.entrar(testes.u('ana'));
set local role authenticated;
select is((select count(*)::int from cardapio
            where id in (testes.u('agora'), testes.u('futuro'), testes.u('expirado'))),
          1, 'o cliente só vê o prato dentro da janela');
select is((select count(*)::int from cardapio where id = testes.u('futuro')), 0,
          'o cliente não vê o prato agendado para o futuro');
reset role; select testes.sair();

-- 3) O gestor vê tudo (para agendar/gerir)
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select is((select count(*)::int from cardapio
            where id in (testes.u('agora'), testes.u('futuro'), testes.u('expirado'))),
          3, 'o gestor (cozinhas.gerir) vê os três, dentro e fora da janela');
reset role; select testes.sair();

-- 4) Guarda do pedido: não deixa pedir fora da janela; deixa dentro
select testes.def('sql_futuro', format(
  $f$insert into pedidos (cliente_id, ponto_entrega_id, itens) values (%L, %L,
       jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)))$f$,
  testes.u('ana'), testes.u('casa'), testes.u('futuro')));
select testes.def('sql_expirado', format(
  $f$insert into pedidos (cliente_id, ponto_entrega_id, itens) values (%L, %L,
       jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)))$f$,
  testes.u('ana'), testes.u('casa'), testes.u('expirado')));
select testes.def('sql_agora', format(
  $f$insert into pedidos (cliente_id, ponto_entrega_id, itens) values (%L, %L,
       jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)))$f$,
  testes.u('ana'), testes.u('casa'), testes.u('agora')));

select testes.entrar(testes.u('ana'));
set local role authenticated;
select throws_ok(testes.v('sql_futuro'),   'P0001', 'item_indisponivel', 'não deixa pedir prato agendado para o futuro');
select throws_ok(testes.v('sql_expirado'), 'P0001', 'item_indisponivel', 'não deixa pedir prato já expirado');
select lives_ok(testes.v('sql_agora'), 'deixa pedir o prato que está dentro da janela');
reset role; select testes.sair();

select * from finish();
rollback;
