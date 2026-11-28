-- O que se compra em cada zona: relatório da cozinha, visão do administrador e "mais pedido na tua zona"
begin;
\ir _helpers.psql
select plan(12);
update parametros set limiar_pediram = 2 where unico;
select testes.funcionalidade('multi_cozinha', true);

with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Zonas', 'Rita') returning id) select testes.def('k', id) from k;
with k as (insert into cozinhas (nome, responsavel) values ('Outra Zonas', 'Olga') returning id) select testes.def('outra', id) from k;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Calulu', 2000) returning id) select testes.def('calulu', id) from m;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Monta', 1000) returning id) select testes.def('monta', id) from m;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('outra'), 'Cachupa', 3000) returning id) select testes.def('cachupa', id) from m;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaNorte', 'Própria', 500, 'Fixo') returning id) select testes.def('norte', id) from z;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaSul', 'Própria', 500, 'Fixo') returning id) select testes.def('sul', id) from z;
select testes.def('casa_n', testes.ponto('residencial', null, null, testes.u('norte')));
select testes.def('casa_s', testes.ponto('residencial', null, null, testes.u('sul')));
select testes.def('cli', testes.cliente('Cliente Zonas'));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('cli'), testes.u('casa_n'));
select testes.def('caixa', testes.caixa(testes.u('k')));
select testes.def('caixa2', testes.caixa(testes.u('outra')));

create function testes.vendido(p_coz uuid, p_ponto uuid, p_itens jsonb, p_quando timestamptz default now()) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, dispositivo_id, itens, subtotal, taxa_entrega)
  values (testes.u('cli'), p_ponto, p_coz, 'servidor', p_itens,
          (select sum((i ->> 'qtd')::int * (i ->> 'preco_unitario')::int) from jsonb_array_elements(p_itens) i), 500)
  returning id into v;
  update pedidos set estado = 'entregue_pago', entregue_em = p_quando,
         caixa_id = case when p_coz = testes.u('k') then testes.u('caixa') else testes.u('caixa2') end,
         parcelas = jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', subtotal + taxa_entrega))
   where id = v;
  return v;
end $$;
create function testes.it(p_prato uuid, p_nome text, p_qtd int, p_preco int, p_opcoes jsonb default null) returns jsonb
language sql as $$ select jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('cardapio_id', p_prato, 'nome', p_nome, 'qtd', p_qtd,
                                                                                 'preco_unitario', p_preco, 'opcoes', p_opcoes))) $$;

-- Norte: 3 pedidos de Calulu (5 doses) + 1 montado com Arroz; Sul: 2 montados com Funge; Outra cozinha: Cachupa no Norte
select testes.vendido(testes.u('k'), testes.u('casa_n'), testes.it(testes.u('calulu'), 'Calulu', 2, 2000));
select testes.vendido(testes.u('k'), testes.u('casa_n'), testes.it(testes.u('calulu'), 'Calulu', 2, 2000));
select testes.vendido(testes.u('k'), testes.u('casa_n'), testes.it(testes.u('calulu'), 'Calulu', 1, 2000));
select testes.vendido(testes.u('k'), testes.u('casa_n'), testes.it(testes.u('monta'), 'Monta (Arroz)', 1, 1500, '[{"nome":"Arroz","preco_extra":500}]'));
select testes.vendido(testes.u('k'), testes.u('casa_s'), testes.it(testes.u('monta'), 'Monta (Funge)', 1, 1400, '[{"nome":"Funge","preco_extra":400}]'));
select testes.vendido(testes.u('k'), testes.u('casa_s'), testes.it(testes.u('monta'), 'Monta (Funge)', 1, 1400, '[{"nome":"Funge","preco_extra":400}]'));
select testes.vendido(testes.u('outra'), testes.u('casa_n'), testes.it(testes.u('cachupa'), 'Cachupa', 1, 3000));
-- Período anterior: 1 Calulu no Norte
select testes.vendido(testes.u('k'), testes.u('casa_n'), testes.it(testes.u('calulu'), 'Calulu', 1, 2000), now() - interval '10 days');

-- 1) Relatório da cozinha: por zona
select testes.def('gerente', testes.funcionario('Gerente Zonas', array['relatorios.exportar']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('k'));
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
create temp table r as select pratos_por_zona_cozinha(testes.u('k'), testes.hoje() - 6, testes.hoje()) as j;
select throws_ok(format('select pratos_por_zona_cozinha(%L, %L, %L)', testes.u('outra'), testes.hoje() - 6, testes.hoje()),
                 '42501', null, 'o gerente não vê o relatório de outra cozinha');
reset role; select testes.sair();
select is((select jsonb_array_length(j) from r), 2, 'duas zonas com vendas (só desta cozinha)');
select results_eq($$select z ->> 'zona', (z ->> 'pedidos')::int from r, jsonb_array_elements(j) z$$,
                  $$values ('ZonaNorte', 4), ('ZonaSul', 2)$$, 'zonas por vendas, com o nº de pedidos');
select results_eq($$select p ->> 'nome', (p ->> 'qtd')::int, (p ->> 'qtd_anterior')::int
                      from r, jsonb_array_elements(j) z, jsonb_array_elements(z -> 'pratos') p where z ->> 'zona' = 'ZonaNorte'$$,
                  $$values ('Calulu', 5, 1), ('Monta', 1, 0)$$, 'Norte: Calulu (5, antes 1) e o montado');
select is((select z -> 'opcoes' -> 0 ->> 'nome' from r, jsonb_array_elements(j) z where z ->> 'zona' = 'ZonaSul'), 'Funge',
          'Sul: a opção mais escolhida nos montados');
select ok((select j::text not like '%Cachupa%' from r), 'não mistura pratos de outra cozinha');

-- 2) Visão do administrador
select testes.def('admin', testes.funcionario('Admin Zonas', array['relatorios.exportar', 'cozinhas.gerir']));
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
create temp table a as select vendas_por_zona(testes.hoje() - 6, testes.hoje()) as j;
reset role; select testes.sair();
select results_eq($$select p ->> 'nome', (p ->> 'qtd')::int, p ->> 'cozinha_top'
                      from a, jsonb_array_elements(j -> 'zonas') z, jsonb_array_elements(z -> 'pratos') p where z ->> 'zona' = 'ZonaNorte'$$,
                  $$values ('Calulu', 5, 'Cozinha Zonas'), ('Cachupa', 1, 'Outra Zonas'), ('Monta', 1, 'Cozinha Zonas')$$,
                  'Norte, todas as cozinhas: cada prato com a cozinha que mais o vende');
select is((select (z ->> 'cozinhas')::int from a, jsonb_array_elements(j -> 'zonas') z where z ->> 'zona' = 'ZonaNorte'), 2,
          'quantas cozinhas entregam na zona');
select is((select z -> 'a_crescer' -> 0 ->> 'nome' from a, jsonb_array_elements(j -> 'zonas') z where z ->> 'zona' = 'ZonaNorte'),
          'Calulu', 'a crescer: Calulu (5 contra 1)');
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select throws_ok(format('select vendas_por_zona(%L, %L)', testes.hoje() - 6, testes.hoje()), '42501', null,
                 'o gerente de uma cozinha não vê todas as zonas');
reset role; select testes.sair();

-- 3) Cliente: o mais pedido na zona (limiar 2 pedidos)
select testes.entrar(testes.u('cli'));
set local role authenticated;
select results_eq(format('select nome, pedidos from mais_pedidos_na_zona(%L)', testes.u('casa_n')),
                  $$values ('Calulu', 4)$$, 'Norte: só o Calulu chega ao limiar (Cachupa e montado têm 1 pedido)');
select is((select count(*)::int from mais_pedidos_na_zona(testes.u('casa_s'))), 0,
          'não responde para uma morada que não é do cliente');
reset role; select testes.sair();

select * from finish();
rollback;
