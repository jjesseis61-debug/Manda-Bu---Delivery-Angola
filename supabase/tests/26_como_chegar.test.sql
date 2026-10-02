-- I10 · "Como chegar": localização da cozinha, só pública com autorização e com o interruptor
begin;
\ir _helpers.psql
select plan(9);

select testes.def('alexandra', cozinha_padrao());
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('chefe', testes.funcionario('Chefe', array['cozinhas.gerir']));
select testes.def('caixa', testes.funcionario('Caixa', array['vendas.registar']));

-- Quem gere as cozinhas grava a localização; o cliente não
select testes.entrar_funcionario(testes.u('chefe'));
set local role authenticated;
select testes.def('e_chefe', testes.erro(format(
  $$insert into cozinhas_localizacao (cozinha_id, morada, horario, lat, lng) values (%L, 'Rua 12, Talatona', 'Seg–Sex 10h–15h', -8.9170, 13.1860)$$,
  testes.v('alexandra'))));
reset role;
select is(testes.v('e_chefe'), 'sem_erro', 'cozinhas.gerir grava a localização da cozinha');

select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_ana', testes.erro(format($$insert into cozinhas_localizacao (cozinha_id, lat, lng) values (%L, 1, 1)$$, testes.v('alexandra'))));
select testes.def('ana_tabela', (select count(*) from cozinhas_localizacao));
select testes.def('off', (select count(*) from localizacao_cozinha(testes.u('alexandra'))));
reset role;
select ok(testes.v('e_ana') like '42501:%', 'o cliente não grava localizações');
select is(testes.v('ana_tabela')::int, 0, 'o cliente não lê a tabela directamente');
select is(testes.v('off')::int, 0, 'como_chegar desligado: a localização não aparece');

select testes.funcionalidade('como_chegar', true);
set local role authenticated;
select testes.def('privada', (select count(*) from localizacao_cozinha(testes.u('alexandra'))));
reset role;
select is(testes.v('privada')::int, 0, 'sem autorização da responsável (publica = false) não aparece');

update cozinhas_localizacao set publica = true where cozinha_id = testes.u('alexandra');
set local role authenticated;
select testes.def('publica', (select morada || '|' || horario || '|' || lat from localizacao_cozinha(testes.u('alexandra'))));
reset role;
select is(testes.v('publica'), 'Rua 12, Talatona|Seg–Sex 10h–15h|-8.917', 'pública e com o interruptor: o cliente vê morada, horário e ponto');

update cozinhas set estado = 'pausada' where id = testes.u('alexandra');
set local role authenticated;
select testes.def('pausada', (select count(*) from localizacao_cozinha(testes.u('alexandra'))));
reset role;
select is(testes.v('pausada')::int, 0, 'cozinha pausada não aparece');

select testes.entrar_funcionario(testes.u('caixa'));
set local role authenticated;
select testes.def('caixa_le', (select count(*) from cozinhas_localizacao));
select testes.def('e_caixa', testes.erro(format($$update cozinhas_localizacao set publica = false where cozinha_id = %L$$, testes.v('alexandra'))));
reset role;
select is(testes.v('caixa_le')::int, 1, 'a equipa lê a localização');
select is((select publica from cozinhas_localizacao where cozinha_id = testes.u('alexandra')), true,
          'sem cozinhas.gerir não se altera a localização');

select * from finish();
rollback;
