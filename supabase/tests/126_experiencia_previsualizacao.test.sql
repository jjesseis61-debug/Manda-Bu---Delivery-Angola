-- Pré-visualização: o cliente que também é funcionário vê sempre o grupo B e não conta no teste.
begin;
\ir _helpers.psql
select plan(4);

select testes.funcionalidade('teste_balcao_recipientes', true);
select testes.def('func', testes.funcionario('Ana Equipa', array['cardapio.ver']));
-- A mesma pessoa tem conta de cliente (mesmo utilizador)
with c as (insert into clientes (nome, tipo, auth_user_id)
           values ('Ana Equipa', 'Particular', (select auth_user_id from funcionarios where id = testes.u('func'))) returning id)
select testes.def('ana', id) from c;
select testes.def('cli', testes.cliente('Cliente Normal'));

select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('v_ana', visita_experiencia('balcao_recipientes'));
select visita_experiencia('balcao_recipientes', 20);
reset role;
select is(testes.v('v_ana'), 'B', 'quem trabalha na plataforma vê o desenho novo');
select is((select count(*)::int from experiencia_visitas where cliente_id = testes.u('ana')), 0, 'e não entra na contagem');

select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('v_cli', visita_experiencia('balcao_recipientes'));
reset role;
select is(testes.v('v_cli'), variante_experiencia('balcao_recipientes', testes.u('cli')), 'os outros clientes ficam no grupo sorteado');
select is((select count(*)::int from experiencia_visitas where cliente_id = testes.u('cli')), 1, 'e contam');

select * from finish();
rollback;
