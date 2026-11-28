-- Código de convite sem hífen (MB4812): todas as formas escritas ligam ao mesmo código
begin;
\ir _helpers.psql
select plan(15);

select is(normalizar_codigo_convite('MB4812'), 'MB4812', 'MB4812');
select is(normalizar_codigo_convite('mb-4812'), 'MB4812', 'mb-4812 (links antigos)');
select is(normalizar_codigo_convite(' MB 4812 '), 'MB4812', 'MB 4812 com espaços');
select is(normalizar_codigo_convite('4812'), 'MB4812', 'só os números');
select is(normalizar_codigo_convite('123'), null, 'curto demais: não é código');
select is(normalizar_codigo_convite('482100'), 'MB482100', 'até 6 dígitos');
select is(normalizar_codigo_convite('1234567'), null, '7 dígitos: não é código');

select testes.funcionalidade('indicacao', true);
select testes.def('ana', testes.cliente('Ana Convida'));
select testes.def('cod', testes.codigo(testes.u('ana')));
select matches(testes.v('cod'), '^MB[1-9][0-9]{3}$', 'códigos novos: sem hífen, 4 dígitos e sem zero à esquerda');

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
select lives_ok($$update codigos_indicacao set codigo = 'MB123456' where cliente_id = testes.u('ana')$$,
                'cabem códigos de 6 dígitos');

-- Dois registos no mesmo instante com o mesmo número sorteado: o segundo sorteia outro, sem erro.
-- Simula a corrida: o gerador devolve primeiro um código já ocupado e depois um livre.
-- (sequência: como o sorteio verdadeiro, não volta atrás quando a tentativa falha)
create temp sequence sorteios;
create or replace function gerar_codigo_indicacao() returns text language plpgsql as $f$
begin
  return case when nextval('sorteios') % 2 = 1 then 'MB123456' else 'MB654321' end;
end $f$;
select testes.def('leo', testes.cliente('Leo Corrida'));
delete from codigos_indicacao where cliente_id = testes.u('leo');
select setval('sorteios', 2);
select lives_ok($$select preparar_cliente_programa(testes.u('leo'))$$, 'código ocupado no sorteio: sem erro no registo');
select is((select codigo from codigos_indicacao where cliente_id = testes.u('leo')), 'MB654321', 'fica com o código seguinte, livre');
select is(currval('sorteios'), 4::bigint, 'sorteou duas vezes');

select * from finish();
rollback;
