-- Gestão de permissões e cozinhas do pessoal (só administrador principal):
-- definir permissões (objeto do catálogo), ligar a cozinhas (equipa fixa) e as barreiras.
begin;
\ir _helpers.psql
select plan(10);

select testes.def('admin', testes.funcionario('Dona Admin', array[]::text[]));
update funcionarios set administrador_principal = true where id = testes.u('admin');
select testes.def('gestor', testes.funcionario('Gestor Cozinha', array[]::text[]));
select testes.def('coz', (select cozinha_padrao()));

-- Catálogo visível ao admin
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('n_cat', (select count(*)::int from permissoes_catalogo())::text);
-- Define permissões (ignora chaves fora do catálogo)
select definir_permissoes_funcionario(testes.u('gestor'), '{"pedidos.gerir": true, "xpto.nao_existe": true}'::jsonb);
reset role;
select testes.sair();

select cmp_ok(testes.v('n_cat')::int, '>=', 20, 'permissoes_catalogo lista o catálogo ao admin');
select ok(tem_permissao_de(testes.u('gestor'), 'pedidos.gerir'), 'definir_permissoes atribui pedidos.gerir');
select ok(not tem_permissao_de(testes.u('gestor'), 'xpto.nao_existe'), 'chave fora do catálogo é ignorada');

-- Ligar o gestor à cozinha (equipa fixa) e confirmar que passa a gerir essa cozinha
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select definir_cozinhas_funcionario(testes.u('gestor'), array[testes.u('coz')]);
reset role;
select testes.sair();

select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('pode_antes', pode_na_cozinha('pedidos.gerir', testes.u('coz'))::text);
reset role;
select testes.sair();
select is(testes.v('pode_antes'), 'true', 'com permissão + cozinha, pode gerir os pedidos dessa cozinha');

-- Tirar a cozinha remove a pertença
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select definir_cozinhas_funcionario(testes.u('gestor'), array[]::uuid[]);
reset role;
select testes.sair();

select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('pode_depois', pode_na_cozinha('pedidos.gerir', testes.u('coz'))::text);
reset role;
select testes.sair();
select is(testes.v('pode_depois'), 'false', 'sem cozinha, já não gere os pedidos dessa cozinha');

-- Definir permissões substitui o conjunto (não acumula)
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select definir_permissoes_funcionario(testes.u('gestor'), '{"vendas.registar": true}'::jsonb);
reset role;
select testes.sair();
select ok(tem_permissao_de(testes.u('gestor'), 'vendas.registar'), 'nova permissão fica');
select ok(not tem_permissao_de(testes.u('gestor'), 'pedidos.gerir'), 'a permissão anterior sai (substitui, não acumula)');

-- Barreiras
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('e_nao_admin', testes.erro(format($$select definir_permissoes_funcionario(%L, '{}'::jsonb)$$, testes.u('gestor'))));
select testes.def('e_cat', testes.erro($$select * from permissoes_catalogo()$$));
reset role;
select testes.sair();
select matches(testes.v('e_nao_admin'), '^42501', 'só o admin principal define permissões');
select matches(testes.v('e_cat'), '^42501', 'só o admin principal vê o catálogo');

-- O admin principal não tem permissões individuais (tem tudo)
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('e_admin', testes.erro(format($$select definir_permissoes_funcionario(%L, '{}'::jsonb)$$, testes.u('admin'))));
reset role;
select testes.sair();
select matches(testes.v('e_admin'), '^P0001', 'não se definem permissões ao admin principal (já tem tudo)');

select * from finish();
rollback;
