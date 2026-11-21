-- Visitante: preço riscado das campanhas para todos e do bairro escolhido; nada das de condomínio
-- nem com o interruptor desligado.
begin;
\ir _helpers.psql
select plan(6);
select testes.funcionalidade('campanhas', true);
select testes.def('k', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa, modo_calculo, entrega_gratis_acima) values ('Bairro V', 'Própria', 1000, 'Fixo', 8000) returning id)
select testes.def('z', id) from z;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Outro V', 'Própria', 1000, 'Fixo') returning id)
select testes.def('z2', id) from z;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Choco V', 9000, testes.u('k')) returning id) select testes.def('choco', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Funge V', 3000, testes.u('k')) returning id) select testes.def('funge', id) from m;
insert into campanhas (nome, tipo, valor, cardapio_ids) values ('Semana do choco', 'percentagem', 20, array[testes.u('choco')]);
insert into campanhas (nome, zona_id, tipo, valor, cardapio_ids) values ('Funge no bairro', testes.u('z'), 'preco', 2000, array[testes.u('funge')]);
with c as (insert into condominios (nome, codigo, centro_lat, centro_lng, raio_m, cozinha_id, zona_id)
           values ('Cond V', 'CV01', -8.8, 13.3, 500, testes.u('k'), testes.u('z')) returning id)
insert into campanhas (nome, condominio_id, tipo, valor, cardapio_ids) select 'Só moradores', id, 'preco', 1000, array[testes.u('choco')] from c;
grant usage on schema testes to anon; -- só nesta transacção (rollback)

set local role anon;
select testes.def('sem_bairro', visitante_precos(testes.u('k'))::text);
select testes.def('bairro', visitante_precos(testes.u('k'), testes.u('z'))::text);
select testes.def('outro', visitante_precos(testes.u('k'), testes.u('z2'))::text);
reset role;

select is((select (p ->> 'preco_campanha')::int from jsonb_array_elements(testes.v('sem_bairro')::jsonb -> 'pratos') p
            where p ->> 'cardapio_id' = testes.v('choco')), 7200, 'campanha para todos: 9.000 → 7.200 (a do condomínio não conta)');
select is(jsonb_array_length(testes.v('sem_bairro')::jsonb -> 'pratos'), 1, 'sem bairro: só a campanha para todos');
select is((select (p ->> 'preco_campanha')::int from jsonb_array_elements(testes.v('bairro')::jsonb -> 'pratos') p
            where p ->> 'cardapio_id' = testes.v('funge')), 2000, 'com o bairro: também a campanha do bairro');
select is((testes.v('bairro')::jsonb ->> 'entrega_gratis_acima')::int, 8000, 'entrega grátis do bairro');
select is(jsonb_array_length(testes.v('outro')::jsonb -> 'pratos'), 1, 'noutro bairro: só a campanha para todos');

select testes.funcionalidade('campanhas', false);
set local role anon;
select testes.def('desligado', visitante_precos(testes.u('k'))::text);
reset role;
select is(jsonb_array_length(testes.v('desligado')::jsonb -> 'pratos'), 0, 'interruptor desligado: sem preço riscado');

select * from finish();
rollback;
