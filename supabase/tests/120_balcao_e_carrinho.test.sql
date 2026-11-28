-- Balcão certo e carrinho: balcões perto de uma posição (GPS), pedido agendado vê a hora da entrega,
-- pratos fora do horário dizem quando voltam, moradas sem repetições.
begin;
\ir _helpers.psql
select plan(11);

select testes.funcionalidade('multi_cozinha', true);

with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Zona BC', 'Própria', 700, 'Fixo') returning id)
  select testes.def('zona', id) from z;
with c as (insert into cozinhas (nome, responsavel) values ('Maianga BC', 'Ana') returning id) select testes.def('mai', id) from c;
with c as (insert into cozinhas (nome, responsavel) values ('Viana BC', 'Bia') returning id) select testes.def('via', id) from c;
update cozinhas set estado = 'activa', aberta = true where id in (testes.u('mai'), testes.u('via'));
insert into cozinhas_localizacao (cozinha_id, lat, lng) values (testes.u('mai'), -8.83, 13.24), (testes.u('via'), -8.90, 13.37);

select testes.def('cli', testes.cliente('Clara Balcão'));
select testes.def('casa', testes.ponto('residencial', -8.83, 13.24, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('cli'), testes.u('casa'));

-- Prato que só abre amanhã (janela de datas) e prato com horário só amanhã às 12h–14h (Luanda)
with m as (insert into cardapio (nome, preco, cozinha_id, disponivel_de) values ('Amanhã BC', 3000, testes.u('mai'), now() + interval '1 day') returning id)
  select testes.def('amanha', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Almoço BC', 3500, testes.u('mai')) returning id)
  select testes.def('almoco', id) from m;
insert into cardapio_horarios (cardapio_id, dia_semana, hora_inicio, hora_fim)
values (testes.u('almoco'), extract(isodow from (now() at time zone 'Africa/Luanda')::date + 1)::int, '12:00', '14:00');

-- 1) Perto de mim (GPS): o mais perto primeiro
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('perto', (select string_agg(nome, ',' order by distancia_km) from cozinhas_perto_de(-8.84, 13.25)));
select testes.def('mais_tarde', (select string_agg(nome || '@' || to_char(proxima at time zone 'Africa/Luanda', 'HH24:MI'), ',' order by nome)
                                   from cardapio_mais_tarde(testes.u('mai'))));
-- 2) Agendado: o prato tem de estar à venda à hora da entrega
select testes.def('e_ja', testes.erro(format(
  $f$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens) values (%L, %L, %L,
       jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)))$f$,
  testes.v('cli'), testes.v('casa'), testes.v('mai'), testes.v('amanha'))));
select testes.def('e_agendado', testes.erro(format(
  $f$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, agendado_para, itens) values (%L, %L, %L, now() + interval '2 days',
       jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)))$f$,
  testes.v('cli'), testes.v('casa'), testes.v('mai'), testes.v('amanha'))));
-- 3) Morada repetida
select testes.def('e_morada', testes.erro(format($f$insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (%L, %L)$f$,
                                                 testes.v('cli'), testes.v('casa'))));
reset role;

select ok(array_position(string_to_array(testes.v('perto'), ','), 'Maianga BC') < array_position(string_to_array(testes.v('perto'), ','), 'Viana BC'),
          'perto de mim: Maianga (perto) antes de Viana (longe)');
select ok(testes.v('perto') like '%Viana BC%', 'perto de mim: Viana também aparece');
select ok(testes.v('mais_tarde') like '%Almoço BC@12:00%', 'o prato com horário diz quando volta (12h00)');
select ok(testes.v('mais_tarde') like '%Amanhã BC@%', 'o prato com data de início também aparece');
select is(testes.v('e_ja'), 'P0001:item_indisponivel', 'pedir já um prato que só abre amanhã: recusado');
select is(testes.v('e_agendado'), 'sem_erro', 'agendado para quando o prato já está à venda: aceite');
select ok(testes.v('e_morada') like '23505:%', 'a mesma morada não fica guardada duas vezes');
select is((select cardapio_proxima_abertura(id) from cardapio where id = testes.u('almoco')) at time zone 'Africa/Luanda',
          ((now() at time zone 'Africa/Luanda')::date + 1 + time '12:00')::timestamp, 'próxima abertura: amanhã às 12h00');

-- Agendado para fora do horário do prato: recusado (antes passava, porque se via a hora do pedido)
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('e_fora', testes.erro(format(
  $f$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, agendado_para, itens) values (%L, %L, %L,
       ((now() at time zone 'Africa/Luanda')::date + 1 + time '18:00') at time zone 'Africa/Luanda',
       jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)))$f$,
  testes.v('cli'), testes.v('casa'), testes.v('mai'), testes.v('almoco'))));
select testes.def('e_dentro', testes.erro(format(
  $f$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, agendado_para, itens) values (%L, %L, %L,
       ((now() at time zone 'Africa/Luanda')::date + 1 + time '12:30') at time zone 'Africa/Luanda',
       jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)))$f$,
  testes.v('cli'), testes.v('casa'), testes.v('mai'), testes.v('almoco'))));
reset role;
select is(testes.v('e_fora'), 'P0001:item_indisponivel', 'agendado para as 18h, fora do horário do prato: recusado');
select is(testes.v('e_dentro'), 'sem_erro', 'agendado para as 12h30, dentro do horário: aceite');

-- A limpeza das repetidas: fica a principal (ou a mais antiga)
select is((select count(*)::int from pg_indexes where indexname = 'enderecos_cliente_ponto_unico'), 1, 'índice único das moradas');

select * from finish();
rollback;
