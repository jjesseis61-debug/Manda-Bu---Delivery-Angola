-- Visitante pela porta da frente: bairros e cozinhas que lhe servem, da mais perto para a mais longe
begin;
\ir _helpers.psql
select plan(9);

select testes.def('coz', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa, centro_lat, centro_lng) values (' Talatona', 'Própria', 300, -8.92, 13.18) returning id)
select testes.def('talatona', id) from z;
with z as (insert into zonas (nome, tipo, taxa) values ('Zango', 'Própria', 500) returning id) select testes.def('zango', id) from z;
with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Talatona', 'Rosa') returning id) select testes.def('perto', id) from k;
with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Sem Pratos', 'Joana') returning id) select testes.def('vazia', id) from k;
insert into cozinhas_localizacao (cozinha_id, lat, lng) values (testes.u('perto'), -8.921, 13.181), (testes.u('coz'), -8.83, 13.23);
insert into cardapio (nome, preco, cozinha_id) values ('Muamba', 2500, testes.u('coz')), ('Calulu', 3000, testes.u('perto'));
select testes.funcionalidade('multi_cozinha', true);
grant usage on schema testes to anon; -- só nesta transacção (rollback)

set local role anon;
select testes.def('zonas', visitante_zonas());
select testes.def('perto_de_talatona', visitante_cozinhas(testes.u('talatona')));
select testes.def('sem_centro', visitante_cozinhas(testes.u('zango')));
select testes.def('sem_zona', visitante_cozinhas());
reset role;

select is((select (x ->> 'taxa')::int from jsonb_array_elements(testes.v('zonas')::jsonb) x where x ->> 'nome' = 'Zango'), 500,
          'cada bairro com a taxa de entrega');
select is((select x -> 'entrega_gratis_acima' from jsonb_array_elements(testes.v('zonas')::jsonb) x where x ->> 'nome' = 'Zango'), 'null'::jsonb,
          'sem entrega grátis configurada: null');
select ok((select bool_or(x ->> 'nome' = 'Talatona') from jsonb_array_elements(testes.v('zonas')::jsonb) x), 'bairros para escolher (nome sem espaços)');
select is(testes.v('perto_de_talatona')::jsonb #>> '{0,nome}', 'Cozinha Talatona', 'bairro com centro: a cozinha mais perto primeiro');
select ok((testes.v('perto_de_talatona')::jsonb #>> '{0,distancia_km}')::numeric < 1, 'com a distância');
select is(testes.v('sem_centro')::jsonb #>> '{0,id}', testes.v('coz'), 'bairro sem centro: a cozinha principal primeiro');
select ok(not exists (select 1 from jsonb_array_elements(testes.v('sem_zona')::jsonb) x where x ->> 'id' = testes.v('vazia')),
          'cozinha sem pratos na app não aparece');

update cozinhas set estado = 'pausada' where id = testes.u('perto');
set local role anon;
select testes.def('pausada', visitante_cozinhas(testes.u('talatona')));
reset role;
select ok(not exists (select 1 from jsonb_array_elements(testes.v('pausada')::jsonb) x where x ->> 'id' = testes.v('perto')),
          'cozinha pausada não aparece');
select is((select count(*)::int from jsonb_array_elements(testes.v('pausada')::jsonb) x where x ? 'telefone_publico' or x ? 'morada'), 0,
          'sem contactos nem moradas');

select * from finish();
rollback;
