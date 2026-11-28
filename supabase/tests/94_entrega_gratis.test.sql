-- Entrega grátis a partir de um valor: conta depois dos descontos; o operador gere por zona
-- (valor geral em parametros; em cada zona: vazio = geral, 0 = nunca, > 0 = valor próprio).
begin;
\ir _helpers.psql
select plan(16);

update parametros set desconto_subtotal_minimo = 0, desconto_indicado = 750, entrega_gratis_acima = 0 where unico;
select testes.funcionalidade('indicacao', true);

with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaGratis', 'Própria', 500, 'Fixo') returning id)
  select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco, do_dia) values ('Prato 1000', 1000, true) returning id)
  select testes.def('prato', id) from m;
select testes.def('rui', testes.cliente('Rui Gratis'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('rui'), testes.u('casa'));

-- Orçamento do Rui com n pratos de 1000 Kz
create function pg_temp.orc(p_cliente uuid, p_ponto uuid, n int) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform testes.entrar(p_cliente);
  set local role authenticated;
  r := orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', n)), p_ponto);
  reset role;
  perform testes.sair();
  return r;
end $$;

-- 1) Desligado (0): paga sempre a entrega
select is((pg_temp.orc(testes.u('rui'), testes.u('casa'), 12) ->> 'taxa_entrega')::int, 500, 'desligado: 12.000 Kz pagam a entrega');
select is(pg_temp.orc(testes.u('rui'), testes.u('casa'), 12) ->> 'falta_entrega_gratis', null, 'desligado: não mostra quanto falta');

-- 2) Ligado a 10.000 Kz
update parametros set entrega_gratis_acima = 10000 where unico;
select results_eq($$select (o ->> 'taxa_entrega')::int, (o ->> 'falta_entrega_gratis')::int, (o ->> 'entrega_gratis')::boolean
                      from (select pg_temp.orc(testes.u('rui'), testes.u('casa'), 9) o) x$$,
                  $$values (500, 1000, false)$$, '9.000 Kz: paga a entrega e faltam 1.000 Kz');
select results_eq($$select (o ->> 'taxa_entrega')::int, (o ->> 'total')::int, (o ->> 'entrega_gratis')::boolean
                      from (select pg_temp.orc(testes.u('rui'), testes.u('casa'), 10) o) x$$,
                  $$values (0, 10000, true)$$, '10.000 Kz: entrega grátis, total sem taxa');

-- O pedido real (como a app) também fica sem taxa
select testes.entrar(testes.u('rui'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('rui'), testes.u('casa'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', 10)))
           returning id)
select testes.def('p10', id) from x;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('rui'), testes.u('casa'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', 9)))
           returning id)
select testes.def('p9', id) from x;
reset role; select testes.sair();
select is((select taxa_entrega::int from pedidos where id = testes.u('p10')), 0, 'pedido de 10.000 Kz gravado sem taxa');
select is((select taxa_entrega::int from pedidos where id = testes.u('p9')), 500, 'pedido de 9.000 Kz gravado com taxa');

-- 3) Conta depois dos descontos: o convidado tem 750 Kz de desconto
select testes.def('ana', testes.cliente('Ana Convida'));
select testes.def('bia', testes.indicado(testes.u('ana'), 'Bia'));
select testes.def('casa_bia', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('bia'), testes.u('casa_bia'));
select results_eq($$select (o ->> 'desconto')::int, (o ->> 'taxa_entrega')::int, (o ->> 'falta_entrega_gratis')::int
                      from (select pg_temp.orc(testes.u('bia'), testes.u('casa_bia'), 10) o) x$$,
                  $$values (750, 500, 750)$$, '10.000 − 750 de desconto = 9.250: paga a entrega, faltam 750');
select results_eq($$select (o ->> 'desconto')::int, (o ->> 'taxa_entrega')::int, (o ->> 'total')::int
                      from (select pg_temp.orc(testes.u('bia'), testes.u('casa_bia'), 11) o) x$$,
                  $$values (750, 0, 10250)$$, '11.000 − 750 = 10.250: entrega grátis e o desconto mantém-se');
select testes.entrar(testes.u('bia'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('bia'), testes.u('casa_bia'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', 11)))
           returning id)
select testes.def('pbia', id) from x;
reset role; select testes.sair();
select results_eq(format($$select taxa_entrega::int, desconto_indicacao::int, (subtotal + taxa_entrega - desconto_indicacao)::int
                             from pedidos where id = %L$$, testes.u('pbia')),
                  $$values (0, 750, 10250)$$, 'pedido da convidada: sem taxa, com desconto, a pagar 10.250');

-- 4) Por zona: 0 = nunca; valor próprio
update zonas set entrega_gratis_acima = 0 where id = testes.u('zona');
select is((pg_temp.orc(testes.u('rui'), testes.u('casa'), 20) ->> 'taxa_entrega')::int, 500, 'zona com 0: nunca tem entrega grátis');
select is(pg_temp.orc(testes.u('rui'), testes.u('casa'), 20) ->> 'entrega_gratis_acima', null, 'zona com 0: sem limiar');
update zonas set entrega_gratis_acima = 5000 where id = testes.u('zona');
select is((pg_temp.orc(testes.u('rui'), testes.u('casa'), 5) ->> 'taxa_entrega')::int, 0, 'zona com 5.000 próprio: 5.000 Kz já é grátis');
select is((pg_temp.orc(testes.u('rui'), testes.u('casa'), 4) ->> 'falta_entrega_gratis')::int, 1000, 'zona com 5.000: a 4.000 faltam 1.000');
update zonas set entrega_gratis_acima = null where id = testes.u('zona');
select is((pg_temp.orc(testes.u('rui'), testes.u('casa'), 5) ->> 'taxa_entrega')::int, 500, 'zona vazia volta ao valor geral (10.000)');

-- 5) O selo de frete grátis não se gasta num pedido que já é grátis
update parametros set selos_necessarios = 1 where unico;
select testes.funcionalidade('selos', true);
select testes.pagar(testes.u('p9'));
select testes.entrar(testes.u('rui'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('rui'), testes.u('casa'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', 12)))
           returning id)
select testes.def('pselo', id) from x;
reset role; select testes.sair();
select results_eq(format($$select taxa_entrega::int, selo_premio from pedidos where id = %L$$, testes.u('pselo')),
                  $$values (0, false)$$, 'pedido já grátis pelo valor: o selo fica guardado');

-- 6) A função interna não está aberta às apps
select is(has_function_privilege('authenticated', 'limiar_entrega_gratis(uuid)', 'execute'), false,
          'limiar_entrega_gratis é interna');

select * from finish();
rollback;
