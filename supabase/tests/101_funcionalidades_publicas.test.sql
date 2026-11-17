-- App aberta: o visitante sabe que funcionalidades estão ligadas (só chave e estado)
begin;
\ir _helpers.psql
select plan(3);

select testes.funcionalidade('multi_cozinha', true);
select testes.funcionalidade('selos', false);
grant usage on schema testes to anon; -- só nesta transacção (rollback)
set local role anon;
select testes.def('f', funcionalidades_publicas());
reset role;
select is(testes.v('f')::jsonb -> 'multi_cozinha', 'true'::jsonb, 'ligada aparece ligada');
select is(testes.v('f')::jsonb -> 'selos', 'false'::jsonb, 'desligada aparece desligada');
select is((select count(*)::int from jsonb_object_keys(testes.v('f')::jsonb)), (select count(*)::int from funcionalidades), 'todos os interruptores, só chave e estado');

select * from finish();
rollback;
