-- Prato montável padrão nas cozinhas novas, lista de agendados do operador e alerta N41.
begin;
\ir _helpers.psql
select plan(21);

select testes.def('gestor', testes.funcionario('Gestor Cozinhas', array['cozinhas.gerir', 'pedidos.gerir']));
select testes.def('cozinheiro', testes.funcionario('Sem Permissão', array['cardapio.ver']));

-- Modelo: um "Serve o teu próprio prato" com 2 grupos e 3 opções
with m as (insert into cardapio (nome, preco, minimo_montavel, categoria)
           values ('Serve o teu próprio prato', 0, 500, 'Montável') returning id)
  select testes.def('modelo', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo, ordem)
           values (testes.u('modelo'), 'Base', 1, 1, 0) returning id)
  select testes.def('g_base', id) from g;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo, ordem)
           values (testes.u('modelo'), 'Acompanhamentos', 0, 3, 1) returning id)
  select testes.def('g_acomp', id) from g;
insert into opcoes (grupo_id, nome, preco_extra, ordem) values
  (testes.u('g_base'), 'Arroz', 700, 0), (testes.u('g_base'), 'Funge', 600, 1),
  (testes.u('g_acomp'), 'Salada', 300, 0);
-- uma opção apagada não é copiada
insert into opcoes (grupo_id, nome, preco_extra, ordem, deletado_em)
  values (testes.u('g_acomp'), 'Apagada', 100, 9, now());
update parametros set cardapio_modelo_montavel = null where unico;

-- 1) Modelo por defeito: o "Serve o teu..." (o mais antigo com grupos)
select ok(modelo_montavel() is not null, 'há modelo por defeito');

-- 2) Cozinha nova recebe o prato, desactivado, com grupos e opções
with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Nova', 'Ana') returning id)
  select testes.def('nova', id) from k;
select testes.def('clone', (select id from cardapio where cozinha_id = testes.u('nova')
                              and nome = 'Serve o teu próprio prato' and deletado_em is null));
select isnt(testes.u('clone'), null, 'a cozinha nova recebeu o prato montável');
select is((select disponivel from cardapio where id = testes.u('clone')), false, 'o clone nasce desactivado');
select is((select minimo_montavel from cardapio where id = testes.u('clone')),
          (select minimo_montavel from cardapio where id = modelo_montavel()), 'copia o valor mínimo');
select is((select count(*)::int from opcoes_grupos where cardapio_id = testes.u('clone')),
          (select count(*)::int from opcoes_grupos where cardapio_id = modelo_montavel() and deletado_em is null),
          'copia os grupos');
select is((select count(*)::int from opcoes o join opcoes_grupos g on g.id = o.grupo_id
            where g.cardapio_id = testes.u('clone') and o.nome = 'Apagada'), 0, 'não copia opções apagadas');
select is((select count(*)::int from auditoria where acao = 'montavel_clonado' and ref_id = testes.u('clone')),
          1, 'regista na auditoria');

-- 3) Não duplica
select is(clonar_montavel(testes.u('nova')), null, 'não duplica se a cozinha já tem o prato');

-- 4) O modelo escolhido pelo admin e o "modelo inválido"
update parametros set cardapio_modelo_montavel = testes.u('modelo') where unico;
select is(modelo_montavel(), testes.u('modelo'), 'usa o modelo escolhido pelo admin');
with k as (insert into cozinhas (nome, responsavel) values ('Outra', 'Bia') returning id)
  select testes.def('outra', id) from k;
select is((select count(*)::int from opcoes o join opcoes_grupos g on g.id = o.grupo_id
            join cardapio c on c.id = g.cardapio_id where c.cozinha_id = testes.u('outra')),
          3, 'a cópia do modelo escolhido tem as 3 opções activas');
with m as (insert into cardapio (nome, preco) values ('Prato simples', 2000) returning id)
  select testes.def('simples', id) from m;
select throws_ok(format('select clonar_montavel(%L, %L)', testes.u('outra'), testes.u('simples')),
                 'P0001', 'modelo_invalido', 'um prato sem grupos não serve de modelo');

-- 5) Sem modelo nenhum, criar a cozinha não falha
update opcoes_grupos set deletado_em = now() where cardapio_id in (select id from cardapio where nome ilike 'serve o teu%');
select is(modelo_montavel(), null, 'sem montáveis, não há modelo');
select lives_ok($$insert into cozinhas (nome, responsavel) values ('Sem Modelo', 'Caro')$$,
                'sem modelo, a cozinha cria-se na mesma');
update opcoes_grupos set deletado_em = null where cardapio_id = testes.u('modelo');

-- 6) Wrapper: permissão e "já existe"
with k as (insert into cozinhas (nome, responsavel, estado) values ('Antiga', 'Dina', 'activa') returning id)
  select testes.def('antiga', id) from k;
delete from opcoes where grupo_id in (select g.id from opcoes_grupos g join cardapio c on c.id = g.cardapio_id
                                       where c.cozinha_id = testes.u('antiga'));
delete from opcoes_grupos where cardapio_id in (select id from cardapio where cozinha_id = testes.u('antiga'));
delete from cardapio where cozinha_id = testes.u('antiga');

select testes.entrar_funcionario(testes.u('cozinheiro'));
set local role authenticated;
select throws_ok(format('select criar_montavel_do_modelo(%L)', testes.u('antiga')),
                 '42501', null, 'sem cozinhas.gerir não cria');
select throws_ok(format('select clonar_montavel(%L)', testes.u('antiga')),
                 '42501', null, 'clonar_montavel não é chamável pelas apps');
reset role; select testes.sair();

select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select isnt(criar_montavel_do_modelo(testes.u('antiga')), null, 'o gestor cria o montável numa cozinha existente');
select throws_ok(format('select criar_montavel_do_modelo(%L)', testes.u('antiga')),
                 'P0001', 'montavel_ja_existe', 'a segunda vez diz que já existe');
reset role; select testes.sair();

-- 7) Hora do alerta: 3 h antes; antes do turno -> início do turno
update parametros set alerta_agendado_horas = 3, turno_hora_inicio = 9, turno_hora_fim = 23 where unico;
select is(momento_alerta_agendado(((testes.hoje() + 1) + time '14:00') at time zone 'Africa/Luanda'),
          ((testes.hoje() + 1) + time '11:00') at time zone 'Africa/Luanda', 'entrega às 14h -> aviso às 11h');
select is(momento_alerta_agendado(((testes.hoje() + 1) + time '10:00') at time zone 'Africa/Luanda'),
          ((testes.hoje() + 1) + time '09:00') at time zone 'Africa/Luanda', 'entrega às 10h -> aviso às 9h (início do turno)');

-- 8) agendados_operador: devolve o agendado de amanhã, com o estado e "na fila"
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaAgd', 'Própria', 700, 'Fixo') returning id)
  select testes.def('zona', id) from z;
select testes.def('cli', testes.cliente('Carla Agenda', 'Particular', '923000111'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, subtotal, agendado_para, observacoes, dispositivo_id)
values (testes.u('cli'), testes.u('casa'), testes.u('nova'), 2500,
        ((testes.hoje() + 1) + time '12:00') at time zone 'Africa/Luanda', 'Sem cebola', 'servidor');

select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select is((select count(*)::int from agendados_operador(testes.hoje() + 1, testes.hoje() + 1, testes.u('nova'))),
          1, 'o gestor vê o agendado de amanhã da cozinha');
reset role; select testes.sair();

select testes.entrar_funcionario(testes.u('cozinheiro'));
set local role authenticated;
select throws_ok('select * from agendados_operador()', '42501', null, 'sem permissão não vê agendados');
reset role; select testes.sair();

select * from finish();
rollback;
