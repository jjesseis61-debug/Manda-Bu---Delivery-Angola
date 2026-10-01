-- Políticas RLS das tabelas base: acesso por permissão do organograma e por
-- cozinha; clientes sem acesso directo; append-only onde o modelo o pede
begin;
\ir _helpers.psql
select plan(26);

select testes.def('alexandra', cozinha_padrao());
insert into cozinhas (nome, responsavel) values ('Cozinha do Kilamba', 'Joana');
select testes.def('kilamba', (select id from cozinhas where nome = 'Cozinha do Kilamba'));

select testes.def('caixa_alex', testes.funcionario('Caixa Alexandra', array['vendas.registar']));
select testes.def('stock_alex', testes.funcionario('Stock Alexandra', array['stock.gerir']));
select testes.def('financas', testes.funcionario('Financeira', array['financas.gerir']));
select testes.def('balcao', testes.funcionario('Balcão', array['clientes.gerir', 'vendas.registar']));
select testes.def('admin', testes.funcionario('Admin', array[]::text[]));
update funcionarios set administrador_principal = true where id = testes.u('admin');
insert into turnos (funcionario_id, data, hora_inicio, hora_fim, periodo, cozinha_id) values
  (testes.u('caixa_alex'), current_date, '08:00', '14:00', 'manha', testes.u('alexandra')),
  (testes.u('stock_alex'), current_date, '08:00', '14:00', 'manha', testes.u('alexandra')),
  (testes.u('balcao'),     current_date, '08:00', '14:00', 'manha', testes.u('alexandra'));

insert into vendas (produto, qtd, valor_total, cozinha_id, origem) values
  ('Muamba', 1, 2500, testes.u('alexandra'), 'Venda direta'),
  ('Mufete', 1, 3500, testes.u('kilamba'), 'Venda direta');
insert into estoque_diario (produto, qtd_comprada, custo_total, data, cozinha_id) values
  ('Peixe', 10, 20000, current_date, testes.u('alexandra')),
  ('Galinha', 5, 15000, current_date, testes.u('kilamba'));
insert into custos (categoria, descricao, valor, data) values ('Renda', 'Outubro', 100000, current_date);
select testes.def('ana', testes.cliente('Ana Sousa'));

-- ---------------------------------------------------------------------------
-- 1. Cliente: sem acesso directo às tabelas base
-- ---------------------------------------------------------------------------
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('c_vendas', (select count(*) from vendas));
select testes.def('c_func', (select count(*) from funcionarios));
select testes.def('c_venda', testes.erro($$insert into vendas (produto, qtd, valor_total, origem) values ('x', 1, 1, 'Venda direta')$$));
reset role;
select is(testes.v('c_vendas')::int, 0, 'cliente não lê vendas');
select is(testes.v('c_func')::int, 0, 'cliente não lê funcionários');
select ok(testes.v('c_venda') like '42501:%', 'cliente não regista vendas');

-- ---------------------------------------------------------------------------
-- 2. Vendas: por cozinha, append-only, as da app só do servidor
-- ---------------------------------------------------------------------------
select testes.entrar_funcionario(testes.u('caixa_alex'));
set local role authenticated;
select testes.def('v_lista', (select string_agg(produto, ',' order by produto) from vendas));
select testes.def('v_alex', testes.erro(format($$insert into vendas (produto, qtd, valor_total, cozinha_id, origem)
                                                values ('Calulu', 1, 3000, %L, 'Venda direta')$$, testes.v('alexandra'))));
select testes.def('v_kil', testes.erro(format($$insert into vendas (produto, qtd, valor_total, cozinha_id, origem)
                                               values ('Calulu', 1, 3000, %L, 'Venda direta')$$, testes.v('kilamba'))));
select testes.def('v_app', testes.erro(format($$insert into vendas (produto, qtd, valor_total, cozinha_id, origem)
                                               values ('Calulu', 1, 3000, %L, 'App cliente')$$, testes.v('alexandra'))));
with u as (update vendas set valor_total = 1 where produto = 'Muamba' returning 1)
select testes.def('v_upd', (select count(*) from u));
select testes.def('v_stock', (select count(*) from estoque_diario));
select testes.def('v_custos', (select count(*) from custos));
reset role;
select is(testes.v('v_lista'), 'Muamba', 'caixa só vê as vendas da sua cozinha');
select is(testes.v('v_alex'), 'sem_erro', 'caixa regista vendas na sua cozinha');
select ok(testes.v('v_kil') like '42501:%', 'caixa não regista vendas noutra cozinha');
select ok(testes.v('v_app') like '42501:%', 'vendas App cliente são só do servidor');
select is(testes.v('v_upd')::int, 0, 'vendas são append-only: o caixa não as altera');
select is(testes.v('v_stock')::int, 0, 'sem stock.gerir: não vê o stock');
select is(testes.v('v_custos')::int, 0, 'sem financas.gerir: não vê os custos');

-- ---------------------------------------------------------------------------
-- 3. Stock por cozinha; distribuições só avançam recebimento/devolução/quebra
-- ---------------------------------------------------------------------------
insert into distribuicoes (descricao, quantidade, status, cozinha_id) values ('Arroz', 10, 'enviada', testes.u('alexandra'));
select testes.entrar_funcionario(testes.u('stock_alex'));
set local role authenticated;
select testes.def('s_lista', (select string_agg(produto, ',') from estoque_diario));
select testes.def('s_recebe', testes.erro($$update distribuicoes set status = 'recebida', quantidade_quebra = 1$$));
select testes.def('s_muda', testes.erro($$update distribuicoes set quantidade = 99$$));
reset role;
select is(testes.v('s_lista'), 'Peixe', 'stock: só os movimentos da sua cozinha');
select is(testes.v('s_recebe'), 'sem_erro', 'distribuição: regista recebimento e quebra');
select ok(testes.v('s_muda') like '42501:%', 'distribuição: a quantidade enviada não muda');
select is((select quantidade::int || ':' || status from distribuicoes), '10:recebida', 'distribuição guardada como esperado');

-- ---------------------------------------------------------------------------
-- 4. Clientes: balcão regista; crédito e desconto só finanças; conta só servidor
-- ---------------------------------------------------------------------------
select testes.entrar_funcionario(testes.u('balcao'));
set local role authenticated;
select testes.def('b_cria', testes.erro($$insert into clientes (nome, tipo, telefone) values ('Empresa X', 'Empresa', '923000111')$$));
select testes.def('b_credito', testes.erro($$update clientes set limite_credito = 50000 where nome = 'Empresa X'$$));
select testes.def('b_nome', testes.erro($$update clientes set pessoa_contacto = 'Rui' where nome = 'Empresa X'$$));
select testes.def('b_conta', testes.erro(format($$update clientes set auth_user_id = %L where nome = 'Empresa X'$$,
                                                (select auth_user_id from clientes where id = testes.u('ana')))));
reset role;
select is(testes.v('b_cria'), 'sem_erro', 'balcão regista um cliente');
select is(testes.v('b_credito'), '42501:sem_permissao', 'balcão não altera o limite de crédito');
select is(testes.v('b_nome'), 'sem_erro', 'balcão edita os dados do cliente');
select is(testes.v('b_conta'), '42501:campo_reservado', 'a ligação à conta da app não se altera pelo balcão');

select testes.entrar_funcionario(testes.u('financas'));
set local role authenticated;
select testes.def('f_credito', testes.erro($$update clientes set limite_credito = 50000 where nome = 'Empresa X'$$));
select testes.def('f_nome', testes.erro($$update clientes set nome = 'Empresa Y' where nome = 'Empresa X'$$));
select testes.def('f_custos', (select count(*) from custos));
reset role;
select is(testes.v('f_credito'), 'sem_erro', 'finanças altera o limite de crédito');
select is(testes.v('f_nome'), '42501:sem_permissao', 'finanças sem clientes.gerir não muda o nome');
select is(testes.v('f_custos')::int, 1, 'finanças vê os custos');

-- ---------------------------------------------------------------------------
-- 5. Organograma e auditoria
-- ---------------------------------------------------------------------------
select testes.entrar_funcionario(testes.u('caixa_alex'));
set local role authenticated;
select testes.def('o_func', (select string_agg(nome, ',') from funcionarios));
select testes.def('o_promove', testes.erro($$update funcionarios set administrador_principal = true$$));
select testes.def('o_aud', testes.erro(format($$insert into auditoria (funcionario_id, acao) values (%L, 'abrir_caixa')$$, testes.v('caixa_alex'))));
select testes.def('o_aud_outro', testes.erro(format($$insert into auditoria (funcionario_id, acao) values (%L, 'abrir_caixa')$$, testes.v('admin'))));
reset role;
select is(testes.v('o_func'), 'Caixa Alexandra', 'funcionário só lê a sua ficha');
select is((select count(*)::int from funcionarios where administrador_principal), 1, 'funcionário não se promove a administrador');
select is(testes.v('o_aud'), 'sem_erro', 'funcionário regista as suas acções na auditoria');
select ok(testes.v('o_aud_outro') like '42501:%', 'não regista acções em nome de outro funcionário');

select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('a_func', (select count(*) from funcionarios));
reset role;
select ok(testes.v('a_func')::int >= 5, 'administrador lê toda a equipa');

select * from finish();
rollback;
