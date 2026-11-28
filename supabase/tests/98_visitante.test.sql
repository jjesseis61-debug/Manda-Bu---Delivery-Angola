-- Visitante (link partilhado sem conta): vê o prato e o cardápio da cozinha, sem dados a mais
begin;
\ir _helpers.psql
select plan(12);

with m as (insert into cardapio (nome, preco) values ('Muamba ', 2500) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco, visivel_online) values ('Só no balcão', 1000, false) returning id) select testes.def('balcao', id) from m;
with m as (insert into cardapio (nome, preco, disponivel) values ('Acabou', 1000, false) returning id) select testes.def('acabou', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('muamba'), 'Base', 1, 1) returning id)
select testes.def('g', id) from g;
insert into opcoes (grupo_id, nome, ordem) values (testes.u('g'), 'Funge', 1);
insert into opcoes (grupo_id, nome, disponivel) values (testes.u('g'), 'Arroz', false);
select testes.def('ana', testes.cliente('Ana Convida'));
select testes.funcionalidade('indicacao', true);
select testes.def('codigo', testes.codigo(testes.u('ana')));
select testes.def('coz', cozinha_padrao());
grant usage on schema testes to anon; -- só nesta transacção (rollback)

set local role anon;
select testes.def('p', visitante_prato(testes.u('muamba'), testes.v('codigo')));
select testes.def('p_sem', visitante_prato(testes.u('muamba'), 'MB-0000'));
select testes.def('p_balcao', coalesce(visitante_prato(testes.u('balcao'))::text, 'null'));
select testes.def('p_acabou', coalesce(visitante_prato(testes.u('acabou'))::text, 'null'));
select testes.def('c', visitante_cardapio(testes.u('coz')));
select testes.def('e_tabela', testes.erro('select count(*) from cardapio'));
reset role;

select is(testes.v('p')::jsonb #>> '{prato,nome}', 'Muamba', 'anon vê o prato partilhado (nome sem espaços)');
select is(testes.v('p')::jsonb #>> '{cozinha,id}', cozinha_padrao()::text, 'com a cozinha');
select is(jsonb_array_length(testes.v('p')::jsonb -> 'grupos'), 0, 'montáveis desligado: sem opções');
select is((testes.v('p')::jsonb #>> '{convite,desconto}')::int, 500, 'código válido: mostra o desconto do 1.º pedido');
select is(testes.v('p_sem')::jsonb -> 'convite', 'null'::jsonb, 'código inexistente: sem desconto');
select is(testes.v('p_balcao'), 'null', 'prato fora da app: não aparece');
select is(testes.v('p_acabou'), 'null', 'prato indisponível: não aparece');
select is((select array_agg(x ->> 'nome') from jsonb_array_elements(testes.v('c')::jsonb -> 'pratos') x), array['Muamba'],
          'cardápio do visitante: só os pratos visíveis na app');
select isnt(testes.v('e_tabela'), 'sem_erro', 'anon continua sem ler as tabelas');

select testes.funcionalidade('pratos_montaveis', true);
set local role anon;
select testes.def('p2', visitante_prato(testes.u('muamba')));
select testes.def('c2', visitante_cardapio(testes.u('coz')));
reset role;
select is((select array_agg(o ->> 'nome') from jsonb_array_elements(testes.v('p2')::jsonb #> '{grupos,0,opcoes}') o), array['Funge'],
          'montáveis ligado: opções disponíveis do prato');
select is(testes.v('c2')::jsonb #> '{pratos,0,montar}', 'true'::jsonb, 'prato com opções abre o ecrã de montar');

update cozinhas set estado = 'pausada' where id = testes.u('coz');
set local role anon;
select testes.def('p3', coalesce(visitante_prato(testes.u('muamba'))::text, 'null'));
reset role;
select is(testes.v('p3'), 'null', 'cozinha pausada: o prato não aparece');

select * from finish();
rollback;
