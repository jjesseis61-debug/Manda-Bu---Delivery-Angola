-- Ecrã "Utilizadores": procurar quem está inscrito (clientes, equipa e contas de login OTP sem
-- perfil) por nome ou por número, e só com a permissão utilizadores.ver.
begin;
\ir _helpers.psql
select plan(7);

select testes.def('viewer', testes.funcionario('Viewer', array['utilizadores.ver']));
select testes.def('operador', testes.funcionario('Operador', array[]::text[]));

-- Cliente "Alegria" com número e um pedido entregue
select testes.def('alegria', testes.cliente('Alegria', 'Particular', '924287222'));
select testes.def('pa', testes.pedido(testes.u('alegria'), testes.ponto('residencial')));
select testes.pagar(testes.u('pa'));

-- Funcionário (equipa) com número
update funcionarios set telefone = '923111222' where id = testes.u('operador');

-- Conta de login (OTP) ainda sem perfil
insert into auth.users (id, phone) values (gen_random_uuid(), '244999888777');

select testes.entrar_funcionario(testes.u('viewer'));
set local role authenticated;

select results_eq(
  $$select tipo, nome from procurar_utilizadores('924287222')$$,
  $$values ('cliente'::text, 'Alegria'::text)$$,
  'procura por número encontra o cliente');

select is((select count(*)::int from procurar_utilizadores('alegria') where tipo = 'cliente'), 1,
  'procura por nome (sem distinguir maiúsculas/acentos) encontra o cliente');

select is((select total_pedidos from procurar_utilizadores('924287222') where tipo = 'cliente'), 1,
  'conta os pedidos entregues do cliente');

select results_eq(
  $$select tipo from procurar_utilizadores('999888777')$$,
  $$values ('login'::text)$$,
  'conta de login (OTP) ainda sem perfil aparece como "login"');

select is((select tipo from procurar_utilizadores('923111222')),
  'equipa', 'procura por número encontra a equipa');

select is((select count(*)::int from procurar_utilizadores('a')), 0,
  'termo com menos de 2 caracteres não procura');

reset role; select testes.sair();

-- Sem a permissão: recusado
select testes.entrar_funcionario(testes.u('operador'));
set local role authenticated;
select throws_ok($$select * from procurar_utilizadores('924287222')$$, '42501', 'sem_permissao',
  'quem não tem utilizadores.ver não pode procurar');
reset role; select testes.sair();

select * from finish();
rollback;
