-- Horários do cardápio: janela por hora (com meia-noite), por dia da semana e por data; e a RLS.
begin;
\ir _helpers.psql
select plan(10);

-- 1) janela_hora
select is(janela_hora('09:00', '08:00', '11:00'), true,  'hora dentro da janela');
select is(janela_hora('12:00', '08:00', '11:00'), false, 'hora fora da janela');
select is(janela_hora('00:30', '22:00', '02:00'), true,  'janela que cruza a meia-noite (00:30)');
select is(janela_hora('03:00', '22:00', '02:00'), false, 'fora da janela que cruza a meia-noite');

-- Pratos de teste
with m as (insert into cardapio (nome, preco) values ('Sem Agenda', 2000) returning id) select testes.def('sem', id) from m;
with m as (insert into cardapio (nome, preco) values ('Aberto Agora', 2000) returning id) select testes.def('aberto', id) from m;
with m as (insert into cardapio (nome, preco) values ('Fechado Hoje', 2000) returning id) select testes.def('fechado', id) from m;
with m as (insert into cardapio (nome, preco) values ('Por Data Hoje', 2000) returning id) select testes.def('data', id) from m;

-- Horário que bate com AGORA (hoje, janela de ±90 min, em hora de Angola)
insert into cardapio_horarios (cardapio_id, dia_semana, hora_inicio, hora_fim)
select testes.u('aberto'), extract(isodow from ts)::int, (ts - interval '90 min')::time, (ts + interval '90 min')::time
  from (select now() at time zone 'Africa/Luanda' as ts) l;
-- Horário só NOUTRO dia da semana (nunca bate hoje)
insert into cardapio_horarios (cardapio_id, dia_semana, hora_inicio, hora_fim)
select testes.u('fechado'), (extract(isodow from ts)::int % 7) + 1, '08:00', '11:00'
  from (select now() at time zone 'Africa/Luanda' as ts) l;
-- Horário por DATA = hoje, janela de ±90 min
insert into cardapio_horarios (cardapio_id, data, hora_inicio, hora_fim)
select testes.u('data'), ts::date, (ts - interval '90 min')::time, (ts + interval '90 min')::time
  from (select now() at time zone 'Africa/Luanda' as ts) l;

-- 2) cardapio_aberto_agora
select is(cardapio_aberto_agora(testes.u('sem')),     true,  'prato sem agenda está sempre disponível');
select is(cardapio_aberto_agora(testes.u('aberto')),  true,  'horário no dia e hora de agora: disponível');
select is(cardapio_aberto_agora(testes.u('fechado')), false, 'horário só noutro dia: indisponível agora');
select is(cardapio_aberto_agora(testes.u('data')),    true,  'horário por data = hoje e hora de agora: disponível');

-- 3) RLS: o cliente só vê os abertos; o gestor vê tudo
select testes.def('ana', testes.cliente('Ana Hor'));
select testes.def('gestor', testes.funcionario('Gestor Hor', array['cozinhas.gerir']));

select testes.entrar(testes.u('ana'));
set local role authenticated;
select is((select count(*)::int from cardapio where id in (testes.u('aberto'), testes.u('fechado'))), 1,
          'o cliente vê o prato aberto mas não o fechado');
reset role; select testes.sair();

select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select is((select count(*)::int from cardapio where id in (testes.u('aberto'), testes.u('fechado'))), 2,
          'o gestor vê os dois (aberto e fechado) para poder gerir');
reset role; select testes.sair();

select * from finish();
rollback;
