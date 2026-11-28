-- Bloquear/desbloquear um número: só o administrador principal; reflete em auth.users.banned_until,
-- impede o registo e ignora o formato do número.
begin;
\ir _helpers.psql
select plan(7);

select testes.def('admin', testes.funcionario('Admin', array[]::text[]));
update funcionarios set administrador_principal = true where id = testes.u('admin');
select testes.def('operador', testes.funcionario('Operador', array['utilizadores.ver']));

-- Conta de login (OTP) sem perfil, com um número
insert into auth.users (id, phone) values ('00000000-0000-0000-0000-00000000bbbb', '244924222333');

-- 1) Não-admin não pode bloquear
select testes.entrar_funcionario(testes.u('operador'));
set local role authenticated;
select testes.def('e_op', testes.erro($$select bloquear_utilizador('924222333', 'x')$$));
reset role; select testes.sair();
select matches(testes.v('e_op'), '^42501', 'operador normal não pode bloquear');

-- 2) Admin bloqueia (com indicativo, para testar a normalização)
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select lives_ok($$select bloquear_utilizador('+244 924 222 333', 'spam')$$, 'admin bloqueia o número');
reset role; select testes.sair();

select is(telefone_bloqueado('924222333'), true, 'o número fica na lista de bloqueados');
select isnt((select banned_until from auth.users where id = '00000000-0000-0000-0000-00000000bbbb'), null,
  'a conta de login existente fica com banned_until');

-- 3) O registo recusa um número bloqueado (sessão dessa conta de login)
select set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-00000000bbbb', 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('e_reg', testes.erro($$select registar_cliente('Tentativa')$$));
reset role; select testes.sair();
select matches(testes.v('e_reg'), '^42501', 'o registo recusa um número bloqueado');

-- 4) Admin desbloqueia
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select lives_ok($$select desbloquear_utilizador('924222333')$$, 'admin desbloqueia o número');
reset role; select testes.sair();
select is(telefone_bloqueado('924222333'), false, 'o número sai da lista de bloqueados');

select * from finish();
rollback;
