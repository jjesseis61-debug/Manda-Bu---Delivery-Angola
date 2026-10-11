-- Agendar a entrega: validação, hora_prometida, fila da cozinha e alertas.
begin;
\ir _helpers.psql
select plan(6);

select testes.def('cli', testes.cliente('Cliente Agenda'));
select testes.def('op', testes.funcionario('Despacho', array['pedidos.gerir']));
with x as (insert into zonas (nome, tipo, taxa) values ('Zona Agenda', 'Própria', 300) returning id)
select testes.def('zona', id) from x;
select testes.def('ponto', testes.ponto('residencial', null, null, testes.u('zona')));
update pontos_entrega set criado_por_cliente = testes.u('cli') where id = testes.u('ponto');
with x as (insert into cardapio (nome, preco, cozinha_id) values ('Prato Agenda', 3000, cozinha_padrao()) returning id)
select testes.def('prato', id) from x;

-- 1. O cliente não pode agendar no passado (ou a menos de 20 min)
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('e_passado', testes.erro(format(
  $$insert into pedidos (cliente_id, ponto_entrega_id, itens, subtotal, agendado_para)
    values (%L, %L, jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1, 'preco_unitario', 3000, 'nome', 'Prato Agenda')),
            3000, now() - interval '1 hour')$$,
  testes.u('cli'), testes.u('ponto'), testes.u('prato'))));
reset role;
select testes.sair();
select is(split_part(testes.v('e_passado'), ':', 1), 'P0001', 'cliente não agenda no passado');

-- 2. Agendamento válido (servidor): hora_prometida = hora agendada
insert into pedidos (id, cliente_id, subtotal, agendado_para)
values ('00000000-0000-0000-0000-0000000a0001', testes.u('cli'), 3000, date_trunc('minute', now()) + interval '3 hours');
select is((select hora_prometida from pedidos where id = '00000000-0000-0000-0000-0000000a0001'),
          (select agendado_para from pedidos where id = '00000000-0000-0000-0000-0000000a0001'),
          'hora_prometida = hora agendada');

-- Um agendado perto (+30 min) entra já na fila; o de +3 h ainda não
insert into pedidos (id, cliente_id, subtotal, agendado_para)
values ('00000000-0000-0000-0000-0000000a0002', testes.u('cli'), 3000, now() + interval '30 minutes');

select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select testes.def('fila_perto', (select count(*) from pedidos_operador() where pedido_id = '00000000-0000-0000-0000-0000000a0002'));
select testes.def('fila_longe', (select count(*) from pedidos_operador() where pedido_id = '00000000-0000-0000-0000-0000000a0001'));
select testes.def('agendados_longe', (select count(*) from pedidos_agendados() where pedido_id = '00000000-0000-0000-0000-0000000a0001'));
reset role;
select testes.sair();
select is(testes.v('fila_perto')::int, 1, 'o agendado perto (+30 min) entra na fila activa');
select is(testes.v('fila_longe')::int, 0, 'o agendado longe (+3 h) ainda não entra na fila');
select is(testes.v('agendados_longe')::int, 1, 'o agendado longe aparece em pedidos_agendados');

-- 3. O job de alertas não dá "sem confirmação" a um agendado (mesmo criado há horas)
insert into pedidos (id, cliente_id, subtotal, criado_em, agendado_para)
values ('00000000-0000-0000-0000-0000000a0003', testes.u('cli'), 3000, now() - interval '3 hours', now() + interval '5 hours');
select job_alertas_pedidos();
select ok(not exists (select 1 from alertas_pedido
                       where pedido_id = '00000000-0000-0000-0000-0000000a0003' and tipo = 'sem_confirmacao'),
          'pedido agendado não é alertado como "por confirmar"');

select * from finish();
rollback;
