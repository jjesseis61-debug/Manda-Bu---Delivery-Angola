-- Fase 3: cozinhas_perto ordena os balcões pela distância ao ponto de entrega do cliente.
-- Balcões com GPS vêm por ordem de distância; os sem localização vão para o fim.
begin;
\ir _helpers.psql
select plan(5);

select testes.funcionalidade('multi_cozinha', true);

-- A cozinha-padrão (seed) fica em Luanda; damos-lhe GPS. Mais duas: uma perto, outra longe, e uma sem GPS.
select testes.def('padrao', cozinha_padrao());
insert into cozinhas_localizacao (cozinha_id, lat, lng) values (testes.u('padrao'), -8.90, 13.20);

insert into cozinhas (nome, responsavel) values ('Perto', 'P');
select testes.def('perto', (select id from cozinhas where nome = 'Perto'));
insert into cozinhas_localizacao (cozinha_id, lat, lng) values (testes.u('perto'), -8.902, 13.202);

insert into cozinhas (nome, responsavel) values ('Longe', 'L');
select testes.def('longe', (select id from cozinhas where nome = 'Longe'));
insert into cozinhas_localizacao (cozinha_id, lat, lng) values (testes.u('longe'), -8.98, 13.30);

insert into cozinhas (nome, responsavel) values ('Sem GPS', 'S');
select testes.def('sem', (select id from cozinhas where nome = 'Sem GPS'));

-- Um cliente com um ponto de entrega mesmo ao lado de "Perto".
select testes.def('ana', testes.cliente('Ana'));
select testes.def('casa', testes.ponto('residencial', -8.9015, 13.2015));

select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('ordem', (select string_agg(nome, ',' order by ord) from (
         select nome, row_number() over () as ord from cozinhas_perto(testes.u('casa'))) s));
select testes.def('d_perto', (select distancia_km from cozinhas_perto(testes.u('casa')) where nome = 'Perto'));
select testes.def('d_sem', (select distancia_km from cozinhas_perto(testes.u('casa')) where nome = 'Sem GPS'));
select testes.def('primeiro', (select nome from cozinhas_perto(testes.u('casa')) limit 1));
select testes.def('ultimo', (select nome from (select nome, row_number() over () r from cozinhas_perto(testes.u('casa'))) s order by r desc limit 1));
reset role; select testes.sair();

select is(testes.v('primeiro'), 'Perto', 'o balcão mais perto do cliente vem primeiro');
select ok(testes.v('d_perto')::numeric < 1, 'a distância ao balcão ao lado é menos de 1 km');
select is(testes.v('d_sem'), null, 'um balcão sem localização não tem distância');
select is(testes.v('ultimo'), 'Sem GPS', 'o balcão sem GPS fica no fim da lista');
select is(testes.v('ordem'), 'Perto,Cozinha da Alexandra,Longe,Sem GPS', 'ordem completa: por distância, sem-GPS no fim');

select * from finish();
rollback;
