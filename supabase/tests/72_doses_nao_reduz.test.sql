-- Doses: o operador normal só acrescenta (não reduz); só o admin principal reduz; o pico do dia
-- fecha o truque de ir a "sem limite" e voltar a um número menor; num dia novo a trava reinicia.
begin;
\ir _helpers.psql
select plan(6);

select testes.def('cz', cozinha_padrao());
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Choco frito', 9000, testes.u('cz')) returning id)
  select testes.def('p', id) from m;

select testes.def('gerente', testes.funcionario('Gerente', array['cardapio.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('cz'));
select testes.def('admin', testes.funcionario('Admin', array['cozinhas.gerir']));
update funcionarios set administrador_principal = true where id = testes.u('admin');

-- Gerente lança 5 e acrescenta para 7; depois tenta reduzir para 6 (bloqueado)
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
update cardapio set doses_dia = 5 where id = testes.u('p');
update cardapio set doses_dia = 7 where id = testes.u('p');
select testes.def('e_reduz', testes.erro(format($$update cardapio set doses_dia = 6 where id = %L$$, testes.v('p')::uuid)));
reset role; select testes.sair();
select is((select doses_dia from cardapio where id = testes.u('p'))::int, 7, 'acrescentar fica (7); reduzir para 6 foi bloqueado');
select matches(testes.v('e_reduz'), '^42501', 'operador normal não pode reduzir doses lançadas hoje');

-- Truque: 7 -> sem limite -> 6 (bloqueado pelo pico do dia)
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
update cardapio set doses_dia = null where id = testes.u('p');
select testes.def('e_semlim', testes.erro(format($$update cardapio set doses_dia = 6 where id = %L$$, testes.v('p')::uuid)));
reset role; select testes.sair();
select matches(testes.v('e_semlim'), '^42501', 'ir a sem limite e voltar a um número menor continua bloqueado (pico do dia)');

-- Admin principal pode reduzir/corrigir
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
update cardapio set doses_dia = 4 where id = testes.u('p');
reset role; select testes.sair();
select is((select doses_dia from cardapio where id = testes.u('p'))::int, 4, 'admin principal pode reduzir doses');

-- Dia novo: o pico de ontem não trava o lançamento de hoje
update cardapio set doses_pico_data = current_date - 1 where id = testes.u('p');
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('e_dianovo', testes.erro(format($$update cardapio set doses_dia = 2 where id = %L$$, testes.v('p')::uuid)));
reset role; select testes.sair();
select is(testes.v('e_dianovo'), 'sem_erro', 'dia novo: o operador lança doses sem ser travado pelo pico de ontem');
select is((select doses_dia from cardapio where id = testes.u('p'))::int, 2, 'o lançamento do dia novo ficou (2)');

select * from finish();
rollback;
