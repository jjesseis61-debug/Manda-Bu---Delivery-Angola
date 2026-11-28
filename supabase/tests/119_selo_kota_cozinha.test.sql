-- Selo «Kota da Cozinha»: começa desligado, o operador liga-o, o cliente vê-o no perfil público e não o muda.
begin;
\ir _helpers.psql
select plan(4);

with c as (insert into cozinhas (nome, responsavel) values ('Dona Teresa K', 'Teresa') returning id) select testes.def('coz', id) from c;
update cozinhas set estado = 'activa', consentimento_publico = true where id = testes.u('coz');
select is((select selo_kota from cozinhas where id = testes.u('coz')), false, 'o selo começa desligado');

select testes.def('op', testes.funcionario('Olga Kota', array['cozinhas.gerir']));
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
update cozinhas set selo_kota = true where id = testes.u('coz');
reset role;
select is((select selo_kota from cozinhas where id = testes.u('coz')), true, 'o operador liga o selo');

select testes.def('cli', testes.cliente('Clara Kota'));
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('visto', (select selo_kota::text from cozinhas where id = testes.u('coz')));
update cozinhas set selo_kota = false where id = testes.u('coz');
reset role;
select is(testes.v('visto'), 'true', 'o cliente vê o selo no perfil público');
select is((select selo_kota from cozinhas where id = testes.u('coz')), true, 'o cliente não muda o selo');

select * from finish();
rollback;
