-- Cardápio: doses do dia (lançar, gastar, devolver no cancelamento, esgotar, não pedir mais do que restam, só no dia)
-- e categorias limpas (espaços, maiúscula, mesma grafia que a cozinha já usa)
begin;
\ir _helpers.psql
select plan(9);

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
select testes.def('cz', cozinha_padrao());
with m as (insert into cardapio (nome, preco, categoria) values ('Cachupa', 3000, 'Composto') returning id) select testes.def('cachupa', id) from m;
with m as (insert into cardapio (nome, preco, categoria) values ('Muamba', 3500, '  composto  ') returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco, categoria) values ('Sumo', 500, 'bebidas   frescas') returning id) select testes.def('sumo', id) from m;
with m as (insert into cardapio (nome, preco, categoria) values ('Água', 300, '   ') returning id) select testes.def('agua', id) from m;
select ok((select categoria from cardapio where id = testes.u('muamba')) = 'Composto'
          and (select categoria from cardapio where id = testes.u('sumo')) = 'Bebidas frescas'
          and (select categoria from cardapio where id = testes.u('agua')) is null,
          'categorias limpas: sem espaços a mais, primeira letra maiúscula, a mesma grafia que a cozinha já usa; vazia fica sem categoria');

select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('bia', testes.cliente('Bia Neto'));
select testes.def('casa_a', testes.ponto('residencial', null, null, testes.u('zona')));
select testes.def('casa_b', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa_a')), (testes.u('bia'), testes.u('casa_b'));
create function pg_temp.pedir(p_cliente text, p_ponto text, p_prato text, p_qtd int) returns text language plpgsql as $$
declare v uuid;
begin
  perform testes.entrar(testes.u(p_cliente));
  set local role authenticated;
  insert into pedidos (cliente_id, ponto_entrega_id, itens)
  values (testes.u(p_cliente), testes.u(p_ponto), jsonb_build_array(jsonb_build_object('cardapio_id', testes.v(p_prato), 'qtd', p_qtd)))
  returning id into v;
  reset role;
  perform testes.sair();
  return v::text;
exception when others then
  reset role;
  perform testes.sair();
  return sqlstate || ':' || sqlerrm;
end $$;

-- Sem limite: pede-se à vontade
select ok(pg_temp.pedir('ana', 'casa_a', 'cachupa', 30) ~ '^[0-9a-f-]{36}$' and doses_restantes(testes.u('cachupa')) is null,
          'sem doses lançadas não há limite');

-- A cozinha lança 5 doses de muamba
select testes.def('chefe', testes.funcionario('Chefe', array['cozinhas.gerir']));
select testes.entrar_funcionario(testes.u('chefe'));
set local role authenticated;
update cardapio set doses_dia = 5 where id = testes.u('muamba');
select testes.def('lista', (select jsonb_agg(to_jsonb(d)) from doses_cardapio(testes.u('cz')) d));
reset role;
select testes.sair();
select ok((select doses_definidas_em is not null from cardapio where id = testes.u('muamba'))
          and testes.v('lista')::jsonb @> jsonb_build_array(jsonb_build_object('cardapio_id', testes.v('muamba'), 'restantes', 5, 'lancadas', 5)),
          'ao lançar as doses fica registado quando, e as apps vêem que restam 5');

select testes.def('p_ana', pg_temp.pedir('ana', 'casa_a', 'muamba', 3));
select is(doses_restantes(testes.u('muamba')), 2, 'cada pedido gasta doses: 5 − 3 = 2');
select testes.def('e_bia', pg_temp.pedir('bia', 'casa_b', 'muamba', 3));
select is(testes.v('e_bia'), 'P0001:doses_esgotadas', 'não se pede mais do que as doses que restam');
select testes.entrar(testes.u('bia'));
set local role authenticated;
select testes.def('e_orc', testes.erro(format($$select orcamento_pedido(%L, %L)$$,
         jsonb_build_array(jsonb_build_object('cardapio_id', testes.v('muamba'), 'qtd', 3)), testes.v('casa_b'))));
reset role;
select testes.sair();
select is(testes.v('e_orc'), 'P0001:doses_esgotadas', 'o orçamento do carrinho já avisa');

update pedidos set estado = 'cancelado', motivo_cancelamento = 'Desistiu' where id = testes.u('p_ana');
select is(doses_restantes(testes.u('muamba')), 5, 'um pedido cancelado devolve as doses');
select testes.def('p_bia', pg_temp.pedir('bia', 'casa_b', 'muamba', 5));
select ok(doses_restantes(testes.u('muamba')) = 0 and pg_temp.pedir('ana', 'casa_a', 'muamba', 1) = 'P0001:doses_esgotadas',
          'com 0 doses o prato fica esgotado');

-- Relançar: conta só a partir de agora; no dia seguinte o limite deixa de valer
update cardapio set doses_dia = 10 where id = testes.u('muamba');
-- (no teste tudo acontece no mesmo instante: o relançamento passa a ser um segundo depois dos pedidos anteriores)
update cardapio set doses_definidas_em = now() + interval '1 second' where id = testes.u('muamba');
select testes.def('r_relancar', doses_restantes(testes.u('muamba')));
update cardapio set doses_definidas_em = now() - interval '1 day' where id = testes.u('muamba');
select ok(testes.v('r_relancar') = '10' and doses_restantes(testes.u('muamba')) is null
          and not has_function_privilege('authenticated', 'doses_restantes(uuid)', 'execute'),
          'relançar conta a partir desse momento; as doses de ontem já não limitam');

select * from finish();
rollback;
