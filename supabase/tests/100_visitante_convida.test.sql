-- Visitante: as regras do «Convida e ganha» sem conta (só montantes; sem código nem dados de ninguém)
begin;
\ir _helpers.psql
select plan(5);

select testes.funcionalidade('indicacao', false);
grant usage on schema testes to anon; -- só nesta transacção (rollback)
set local role anon;
select testes.def('desligado', coalesce(visitante_convida()::text, 'null'));
reset role;
select is(testes.v('desligado'), 'null', 'programa desligado: nada para mostrar');

select testes.funcionalidade('indicacao', true);
set local role anon;
select testes.def('r', visitante_convida());
reset role;
select is((testes.v('r')::jsonb ->> 'desconto_indicado')::int, (select desconto_indicado from parametros where unico)::int,
          'o desconto do amigo (o mesmo dos parâmetros)');
select is((testes.v('r')::jsonb ->> 'ganho_por_pedido')::int, (select ganho_por_pedido from parametros where unico)::int,
          'quanto ganha por pedido');
select ok(testes.v('r')::jsonb ? 'limiar_embaixador', 'com os níveis de embaixador');
select is((select count(*)::int from jsonb_object_keys(testes.v('r')::jsonb) k where k ~ 'cliente|telefone|nome|codigo|disponivel'), 0,
          'só regras: nada de clientes, telefones, nomes, códigos ou saldos de ninguém');

select * from finish();
rollback;
