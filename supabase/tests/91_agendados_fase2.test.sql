-- Agendados Fase 2: alertas (horário, doses, hora cheia), reagendar e indicadores
begin;
\ir _helpers.psql
select plan(13);
update parametros set agendados_por_hora_max = 2 where unico;

with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Agenda', 'Rita') returning id)
  select testes.def('k', id) from k;
with k as (insert into cozinhas (nome, responsavel) values ('Outra Agenda', 'Olga') returning id)
  select testes.def('outra', id) from k;
-- Calulu: 2 doses por dia; Funge: só de manhã (08–11) às quartas… e a qualquer dia com horário
with m as (insert into cardapio (cozinha_id, nome, preco, doses_dia) values (testes.u('k'), 'Calulu', 2000, 2) returning id)
  select testes.def('calulu', id) from m;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Funge', 1500) returning id)
  select testes.def('funge', id) from m;
insert into cardapio_horarios (cardapio_id, data, hora_inicio, hora_fim)
values (testes.u('funge'), testes.hoje() + 1, '08:00', '11:00');

select testes.def('gestor', testes.funcionario('Gestor Agenda', array['pedidos.gerir', 'relatorios.exportar']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gestor'), testes.u('k'));
select testes.def('alheio', testes.funcionario('Gestor Alheio', array['pedidos.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('alheio'), testes.u('outra'));
select testes.def('cli', testes.cliente('Carla Agenda'));
select testes.def('casa', testes.ponto('residencial'));

create function testes.agendar(p_prato uuid, p_qtd int, p_hora time) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, dispositivo_id, subtotal, agendado_para, itens)
  values (testes.u('cli'), testes.u('casa'), testes.u('k'), 'servidor', 2000 * p_qtd,
          ((testes.hoje() + 1) + p_hora) at time zone 'Africa/Luanda',
          jsonb_build_array(jsonb_build_object('cardapio_id', p_prato, 'nome', 'x', 'qtd', p_qtd, 'preco_unitario', 2000)))
  returning id into v;
  return v;
end $$;
select testes.def('a1', testes.agendar(testes.u('calulu'), 2, '12:10'));
select testes.def('a2', testes.agendar(testes.u('calulu'), 1, '12:40'));
select testes.def('a3', testes.agendar(testes.u('funge'), 1, '15:00'));

-- 1) Alertas
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
create temp table al as select * from alertas_agendados(testes.hoje() + 1, testes.hoje() + 1, testes.u('k'));
reset role;
select ok(exists (select 1 from al where pedido_id = testes.u('a3') and tipo = 'fora_de_horario' and detalhe = 'Funge'),
          'Funge às 15h está fora do horário (só 08–11)');
select is((select count(*)::int from al where tipo = 'doses'), 2, '3 Calulus agendados para 2 doses: alerta nos dois pedidos');
select ok((select detalhe from al where tipo = 'doses' limit 1) like 'Calulu: 3 agendados para 2 doses',
          'diz quantos e quantas doses');
select is((select count(*)::int from al where tipo = 'hora_cheia'), 2, '2 agendados das 12h às 13h (limite 2)');
select ok(not exists (select 1 from al where pedido_id = testes.u('a3') and tipo = 'hora_cheia'), 'às 15h não está cheio');

-- 2) Reagendar
set local role authenticated;
select throws_ok(format('select reagendar_pedido(%L, now() + interval ''5 minutes'')', testes.u('a3')),
                 'P0001', 'agendamento_invalido', 'não se reagenda para daqui a 5 minutos');
select lives_ok(format('select reagendar_pedido(%L, %L, %L)', testes.u('a3'),
                       ((testes.hoje() + 1) + time '09:30') at time zone 'Africa/Luanda', 'Cliente pediu mais cedo'),
                'reagenda para as 9h30');
reset role; select testes.sair();
select is((select hora_prometida from pedidos where id = testes.u('a3')),
          ((testes.hoje() + 1) + time '09:30') at time zone 'Africa/Luanda', 'a hora prometida acompanha');
select ok(exists (select 1 from notificacoes_fila where cliente_id = testes.u('cli') and codigo = 'N31'
                   and dados ->> 'titulo' = 'Pedido reagendado'), 'o cliente é avisado');
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
create temp table al2 as select * from alertas_agendados(testes.hoje() + 1, testes.hoje() + 1, testes.u('k'));
reset role; select testes.sair();
select ok(not exists (select 1 from al2 where pedido_id = testes.u('a3') and tipo = 'fora_de_horario'),
          'às 9h30 o Funge já está no horário');

select testes.entrar_funcionario(testes.u('alheio'));
set local role authenticated;
select throws_ok(format('select reagendar_pedido(%L, now() + interval ''2 days'')', testes.u('a1')), '42501', null,
                 'gestor de outra cozinha não reagenda');
reset role; select testes.sair();

-- 3) Indicadores
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
create temp table ind as select indicadores_agendados(testes.u('k'), testes.hoje(), testes.hoje() + 2) as j;
reset role; select testes.sair();
select is((select (j ->> 'pedidos')::int from ind), 3, 'conta os agendados do período');
select is((select j -> 'horas' -> 0 ->> 'hora' from ind), '12', 'a hora mais pedida');

select * from finish();
rollback;
