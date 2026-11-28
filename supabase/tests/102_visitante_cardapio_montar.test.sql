-- Visitante: o cardápio segue as regras da app com conta (montar, esgotado, «desde»)
begin;
\ir _helpers.psql
select plan(6);

select testes.def('coz', cozinha_padrao());
with m as (insert into cardapio (nome, preco) values ('Muamba', 2500) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco) values ('Arroz de pato', 11000) returning id) select testes.def('pato', id) from m;
with m as (insert into cardapio (nome, preco) values ('Calulu', 3000) returning id) select testes.def('calulu', id) from m;
-- Muamba: base obrigatória (Funge 0 / Arroz 200) e extras opcionais
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('muamba'), 'Base', 1, 1) returning id) select testes.def('g1', id) from g;
insert into opcoes (grupo_id, nome, preco_extra) values (testes.u('g1'), 'Arroz', 200), (testes.u('g1'), 'Funge', 0);
-- Arroz de pato: grupo opcional sem opções disponíveis (não é para montar)
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('pato'), 'Extras', 0, 2) returning id) select testes.def('g2', id) from g;
insert into opcoes (grupo_id, nome, disponivel) values (testes.u('g2'), 'Ovo', false);
-- Calulu: base obrigatória sem opções disponíveis (esgotado)
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('calulu'), 'Base', 1, 1) returning id) select testes.def('g3', id) from g;
insert into opcoes (grupo_id, nome, disponivel) values (testes.u('g3'), 'Pirão', false);
select testes.funcionalidade('pratos_montaveis', true);
grant usage on schema testes to anon; -- só nesta transacção (rollback)

set local role anon;
select testes.def('c', visitante_cardapio(testes.u('coz')));
reset role;

create function pg_temp.p(nome text) returns jsonb language sql as $$
  select x from jsonb_array_elements(testes.v('c')::jsonb -> 'pratos') x where x ->> 'nome' = nome $$;

select is(pg_temp.p('Muamba') -> 'montar', 'true'::jsonb, 'com opções disponíveis: é para montar');
select is((pg_temp.p('Muamba') ->> 'desde')::int, 2500, '«desde»: a base mais barata (Funge, 0 Kz)');
select is(pg_temp.p('Arroz de pato') -> 'montar', 'false'::jsonb, 'grupo sem opções disponíveis: não é para montar');
select is(pg_temp.p('Arroz de pato') -> 'desde', 'null'::jsonb, 'sem grupo obrigatório: sem «desde»');
select is(pg_temp.p('Calulu') -> 'esgotado', 'true'::jsonb, 'grupo obrigatório sem opções: esgotado');
select is(pg_temp.p('Muamba') -> 'esgotado', 'false'::jsonb, 'com opções: não esgotado');

select * from finish();
rollback;
