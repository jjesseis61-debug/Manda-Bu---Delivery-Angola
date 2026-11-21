-- Preço riscado: o preço com campanha que a app mostra é o mesmo que o servidor cobra,
-- só com campanhas verdadeiras, e com o limiar da entrega grátis da zona.
begin;
\ir _helpers.psql
select plan(9);
select testes.funcionalidade('condominios', true);

select testes.def('k', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa, modo_calculo, entrega_gratis_acima) values ('Zona Promo', 'Própria', 1000, 'Fixo', 10000) returning id)
select testes.def('z', id) from z;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Zona Sem', 'Própria', 1000, 'Fixo') returning id)
select testes.def('z2', id) from z;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Muamba P', 4000, testes.u('k')) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Calulu P', 3000, testes.u('k')) returning id) select testes.def('calulu', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Sumo P', 1000, testes.u('k')) returning id) select testes.def('sumo', id) from m;

select testes.def('ana', testes.cliente('Ana Promo', 'Particular', '925000001'));
select testes.def('casa', testes.ponto('residencial', -8.80, 13.30, testes.u('z')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));
select testes.def('casa2', testes.ponto('residencial', -8.90, 13.40, testes.u('z2')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa2'));
select testes.def('alheio', testes.ponto('residencial', -8.95, 13.45, testes.u('z')));

-- 20% na zona para a Muamba e o Calulu; preço especial de 2.000 no Calulu (vale o maior);
-- 50% com mínimo de 20.000 (não aparece no cartão: 1 prato não chega ao mínimo)
insert into campanhas (nome, zona_id, cozinha_id, tipo, valor, cardapio_ids)
values ('Semana da Muamba', testes.u('z'), testes.u('k'), 'percentagem', 20, array[testes.u('muamba'), testes.u('calulu')]);
insert into campanhas (nome, zona_id, tipo, valor, cardapio_ids)
values ('Calulu a 2.000', testes.u('z'), 'preco', 2000, array[testes.u('calulu')]);
insert into campanhas (nome, zona_id, tipo, valor, minimo_pedido)
values ('Metade em grande', testes.u('z'), 'percentagem', 50, 20000);

select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('r', precos_para_mim(testes.u('casa'), testes.u('k'))::text);
select testes.def('r2', precos_para_mim(testes.u('casa2'), testes.u('k'))::text);
select testes.def('r3', precos_para_mim(testes.u('alheio'), testes.u('k'))::text);
reset role;

select is((testes.v('r')::jsonb ->> 'entrega_gratis_acima')::int, 10000, 'entrega grátis a partir de 10.000 nesta zona');
select is(jsonb_array_length(testes.v('r')::jsonb -> 'pratos'), 2, 'só os 2 pratos com campanha (o sumo não)');
select is((select (p ->> 'preco_campanha')::int from jsonb_array_elements(testes.v('r')::jsonb -> 'pratos') p
            where p ->> 'cardapio_id' = testes.v('muamba')), 3200, 'Muamba: 4.000 com 20% = 3.200');
select is((select (p ->> 'preco_campanha')::int from jsonb_array_elements(testes.v('r')::jsonb -> 'pratos') p
            where p ->> 'cardapio_id' = testes.v('calulu')), 2000, 'Calulu: vale a melhor campanha (2.000 em vez de 20% = 2.400)');
select is((select p ->> 'campanha' from jsonb_array_elements(testes.v('r')::jsonb -> 'pratos') p
            where p ->> 'cardapio_id' = testes.v('muamba')), 'Semana da Muamba', 'diz qual é a campanha');
select is(jsonb_array_length(testes.v('r2')::jsonb -> 'pratos'), 0, 'noutra zona não há preço riscado');
select ok(testes.v('r2')::jsonb -> 'entrega_gratis_acima' = 'null'::jsonb, 'zona sem limiar: sem entrega grátis');
select is(jsonb_array_length(testes.v('r3')::jsonb -> 'pratos'), 0, 'morada que não é do cliente: nada');

-- O que a app mostra é o que o servidor cobra
select testes.entrar(testes.u('ana'));
set local role authenticated;
select is((orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)),
                            testes.u('casa'), null, null) ->> 'subtotal')::int, 3200, 'o pedido cobra os mesmos 3.200');
reset role;

select * from finish();
rollback;
