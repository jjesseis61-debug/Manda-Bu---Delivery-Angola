-- Permissão por-cozinha do cardápio: quem tem "cardapio.gerir" edita só a(s) cozinha(s) de que é
-- membro; não mexe nas outras; o admin (cozinhas.gerir) continua a poder tudo e só ele cria cozinhas.
begin;
\ir _helpers.psql
select plan(9);

select testes.def('cz_a', cozinha_padrao());
insert into cozinhas (nome, responsavel) values ('Cozinha B', 'Bruno');
select testes.def('cz_b', (select id from cozinhas where nome = 'Cozinha B'));

with m as (insert into cardapio (nome, preco, cozinha_id) values ('Prato A', 2000, testes.u('cz_a')) returning id)
  select testes.def('prato_a', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Prato B', 3000, testes.u('cz_b')) returning id)
  select testes.def('prato_b', id) from m;

select testes.def('gerente', testes.funcionario('Gerente A', array['cardapio.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('cz_a'));
select testes.def('admin', testes.funcionario('Admin', array['cozinhas.gerir']));

-- Gerente da cozinha A: edita o cardápio da SUA cozinha
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('e_edita_a', testes.erro(format($$update cardapio set preco = 2500 where id = %L$$, testes.v('prato_a')::uuid)));
select testes.def('e_cria_a', testes.erro(format($$insert into cardapio (nome, preco, cozinha_id) values ('Novo A', 1500, %L)$$, testes.u('cz_a'))));
select testes.def('e_cria_b', testes.erro(format($$insert into cardapio (nome, preco, cozinha_id) values ('Intruso', 1500, %L)$$, testes.u('cz_b'))));
update cardapio set preco = 1 where id = testes.u('prato_b'); -- RLS filtra: 0 linhas, sem erro
select testes.def('e_cria_cozinha', testes.erro($$insert into cozinhas (nome, responsavel) values ('Pirata', 'X')$$));
select testes.def('e_perfil_a', testes.erro(format($$update cozinhas set historia = 'nova' where id = %L$$, testes.u('cz_a'))));
update cozinhas set historia = 'intruso' where id = testes.u('cz_b'); -- RLS filtra
reset role; select testes.sair();

select is((select preco from cardapio where id = testes.u('prato_a'))::int, 2500, 'gerente edita o preço de um prato da SUA cozinha');
select is(testes.v('e_edita_a'), 'sem_erro', 'editar prato da própria cozinha não dá erro');
select is(testes.v('e_cria_a'), 'sem_erro', 'gerente cria prato na própria cozinha');
select matches(testes.v('e_cria_b'), '^42501', 'gerente NÃO cria prato noutra cozinha');
select is((select preco from cardapio where id = testes.u('prato_b'))::int, 3000, 'editar prato de outra cozinha não muda nada (RLS filtra)');
select matches(testes.v('e_cria_cozinha'), '^42501', 'gerente de cardápio NÃO cria cozinhas novas');
select is(testes.v('e_perfil_a'), 'sem_erro', 'gerente edita o perfil da própria cozinha');
select is((select historia from cozinhas where id = testes.u('cz_b')), null, 'editar o perfil de outra cozinha não muda nada');

-- O admin (cozinhas.gerir) continua a poder tudo
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
update cardapio set preco = 9999 where id = testes.u('prato_b');
reset role; select testes.sair();
select is((select preco from cardapio where id = testes.u('prato_b'))::int, 9999, 'o admin (cozinhas.gerir) edita o cardápio de qualquer cozinha');

select * from finish();
rollback;
