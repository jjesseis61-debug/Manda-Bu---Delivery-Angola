-- Código de convite sem hífen (MB4812): todas as formas escritas ligam ao mesmo código
begin;
\ir _helpers.psql
select plan(9);

select is(normalizar_codigo_convite('MB4812'), 'MB4812', 'MB4812');
select is(normalizar_codigo_convite('mb-4812'), 'MB4812', 'mb-4812 (links antigos)');
select is(normalizar_codigo_convite(' MB 4812 '), 'MB4812', 'MB 4812 com espaços');
select is(normalizar_codigo_convite('4812'), 'MB4812', 'só os números');
select is(normalizar_codigo_convite('123'), null, 'curto demais: não é código');

select testes.funcionalidade('indicacao', true);
select testes.def('ana', testes.cliente('Ana Convida'));
select testes.def('cod', testes.codigo(testes.u('ana')));
select matches(testes.v('cod'), '^MB[0-9]{4,5}$', 'códigos novos nascem sem hífen');

select testes.def('rui', testes.cliente('Rui Novo'));
select testes.entrar(testes.u('rui'));
select is(ligar_indicacao(substr(testes.v('cod'), 3)), 'ok', 'ligar escrevendo só os números');
select testes.sair();

select testes.def('eva', testes.cliente('Eva Nova'));
select testes.entrar(testes.u('eva'));
select is(ligar_indicacao('MB-' || substr(testes.v('cod'), 3)), 'ok', 'ligar com o formato antigo (MB-…)');
select testes.sair();

select throws_ok($$update codigos_indicacao set codigo = 'MB-1234' where cliente_id = testes.u('ana')$$,
                 '23514', null, 'a base de dados só aceita o formato novo');

select * from finish();
rollback;
