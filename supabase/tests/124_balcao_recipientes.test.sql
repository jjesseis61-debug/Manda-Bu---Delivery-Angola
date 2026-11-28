-- Balcão com recipientes próprios: colunas «recipiente» (grupo e opção) só com valores conhecidos,
-- copiadas para as cozinhas novas, e o teste recomeçado com contagem nova («balcao_recipientes»).
begin;
\ir _helpers.psql
select plan(10);

-- Interruptor novo (herda o estado do antigo) e antigo desligado
select ok(exists (select 1 from funcionalidades where chave = 'teste_balcao_recipientes'), 'interruptor da contagem nova');
select ok(not (select activa from funcionalidades where chave = 'teste_balcao_panelas'), 'o teste antigo fica desligado');

-- Recipiente do grupo e da opção: só os que a app sabe desenhar
with m as (insert into cardapio (nome, preco, minimo_montavel, categoria)
           values ('Serve o teu próprio prato', 0, 500, 'Montável') returning id)
  select testes.def('modelo', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo, ordem, recipiente)
           values (testes.u('modelo'), 'Fritos', 0, 2, 0, 'cartucho') returning id)
  select testes.def('g', id) from g;
insert into opcoes (grupo_id, nome, preco_extra, ordem, recipiente) values (testes.u('g'), 'Pão frito', 100, 0, 'cesto');
insert into opcoes (grupo_id, nome, preco_extra, ordem) values (testes.u('g'), 'Batata frita', 300, 1);
select is((select recipiente from opcoes where nome = 'Batata frita' and grupo_id = testes.u('g')), null, 'sem escolha: null (a app deduz)');
select throws_ok(format($$update opcoes_grupos set recipiente = 'balde' where id = %L$$, testes.u('g')), '23514', null,
                 'recipiente desconhecido no grupo é recusado');
select throws_ok(format($$insert into opcoes (grupo_id, nome, preco_extra, ordem, recipiente) values (%L, 'X', 0, 2, 'prato')$$, testes.u('g')),
                 '23514', null, 'recipiente desconhecido na opção é recusado');

-- O prato modelo copiado para uma cozinha nova leva os recipientes
update parametros set cardapio_modelo_montavel = testes.u('modelo') where unico;
with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Recipientes', 'Ana') returning id)
  select testes.def('nova', id) from k;
select testes.def('clone', (select id from cardapio where cozinha_id = testes.u('nova') and deletado_em is null
                              and nome = 'Serve o teu próprio prato'));
select is((select recipiente from opcoes_grupos where cardapio_id = testes.u('clone')), 'cartucho', 'o grupo copiado leva o recipiente');
select is((select o.recipiente from opcoes o join opcoes_grupos g on g.id = o.grupo_id
            where g.cardapio_id = testes.u('clone') and o.nome = 'Pão frito'), 'cesto', 'a opção copiada leva o recipiente');

-- Contagem nova: conta à parte da antiga
select testes.def('c1', testes.cliente('Teste recipientes'));
select testes.funcionalidade('teste_balcao_recipientes', true);
select testes.entrar(testes.u('c1'));
set local role authenticated;
select testes.def('g1', visita_experiencia('balcao_recipientes'));
select testes.def('antigo', coalesce(visita_experiencia('balcao_panelas'), 'nulo'));
reset role;
select is(testes.v('g1'), variante_experiencia('balcao_recipientes', testes.u('c1')), 'contagem nova devolve o grupo do cliente');
select is(testes.v('antigo'), 'nulo', 'a contagem antiga já não regista (desligada)');
select is((select count(*)::int from experiencia_visitas where experiencia = 'balcao_recipientes'), 1, 'visita registada na contagem nova');

select * from finish();
rollback;
