-- Zonas de entrega: geridas com plataforma.parametros; pontos do cliente sempre com zona
begin;
\ir _helpers.psql
select plan(8);

select testes.def('gestor', testes.funcionario('Gestor', array['plataforma.parametros']));
select testes.def('caixa_f', testes.funcionario('Caixa', array['vendas.registar']));
select testes.def('ana', testes.cliente('Ana Sousa'));

select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('cria', testes.erro($$insert into zonas (nome, tipo, taxa, modo_calculo) values ('Talatona', 'Própria', 500, 'Fixo')$$));
select testes.def('edita', testes.erro($$update zonas set taxa = 600 where nome = 'Talatona'$$));
reset role;
select is(testes.v('cria'), 'sem_erro', 'plataforma.parametros cria uma zona');
select is((select taxa::int from zonas where nome = 'Talatona'), 600, 'e altera a taxa');
select ok(exists (select 1 from auditoria where ref_tipo = 'zonas'), 'alterações das zonas ficam na auditoria');
select testes.def('zona', (select id from zonas where nome = 'Talatona'));

select testes.entrar_funcionario(testes.u('caixa_f'));
set local role authenticated;
select testes.def('e_caixa', testes.erro($$insert into zonas (nome, taxa) values ('Kilamba', 400)$$));
reset role;
select ok(testes.v('e_caixa') like '42501:%', 'sem plataforma.parametros não cria zonas');

select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_cliente', testes.erro($$insert into zonas (nome, taxa) values ('Maianga', 350)$$));
select testes.def('e_sem_zona', testes.erro($$insert into pontos_entrega (tipo, lat, lng) values ('residencial', -8.91, 13.18)$$));
select testes.def('com_zona', testes.erro(format($$insert into pontos_entrega (tipo, lat, lng, zona_id) values ('residencial', -8.91, 13.18, %L)$$, testes.v('zona'))));
reset role;
select ok(testes.v('e_cliente') like '42501:%', 'o cliente não cria zonas');
select ok(testes.v('e_sem_zona') like '42501:%', 'o cliente não cria pontos de entrega sem zona');
select is(testes.v('com_zona'), 'sem_erro', 'o cliente cria o ponto de entrega com zona');

update zonas set deletado_em = now() where id = testes.u('zona');
set local role authenticated;
select testes.def('visiveis', (select count(*) from zonas where nome = 'Talatona'));
reset role;
select is(testes.v('visiveis')::int, 0, 'zona apagada deixa de aparecer ao cliente');

select * from finish();
rollback;
