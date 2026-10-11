-- Pratos montáveis (regras de negócio 1 e 2): o cliente tira ingredientes da receita por escolha e não paga o que
-- tirou; valor de cada ingrediente = custo × margem × IVA, proporcional à quantidade; validação; sem ajustes de
-- quantidade vindos da app; prato a 0 Kz só com opções; o stock não desconta o que foi tirado
begin;
\ir _helpers.psql
select plan(12);

select testes.funcionalidade('pratos_montaveis', true);
with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
-- Frango: 3000 Kz/kg, margem 20%, IVA 14% -> 4104 Kz/kg -> 250 g = 1026
with p as (insert into produtos (nome, tipo_estoque, categoria_medida, unidade_compra, custo, margem, iva_aplicavel, iva)
           values ('Frango', 'Longo Prazo', 'Peso', 'kg', 3000, 20, true, 14) returning id) select testes.def('frango', id) from p;
-- Cebola: 500 Kz/kg, sem margem nem IVA -> 50 g = 25
with p as (insert into produtos (nome, tipo_estoque, categoria_medida, unidade_compra, custo, margem)
           values ('Cebola', 'Longo Prazo', 'Peso', 'kg', 500, 0) returning id) select testes.def('cebola', id) from p;
-- Jindungo: 50 Kz a unidade, margem 100% -> 2 un = 200
with p as (insert into produtos (nome, tipo_estoque, categoria_medida, unidade_compra, custo, margem)
           values ('Jindungo', 'Longo Prazo', 'Unidade', 'un', 50, 100) returning id) select testes.def('jindungo', id) from p;
-- Sal: sem custo -> vale 0
with p as (insert into produtos (nome, tipo_estoque, categoria_medida, unidade_compra)
           values ('Sal', 'Longo Prazo', 'Peso', 'kg') returning id) select testes.def('sal', id) from p;
with p as (insert into produtos (nome, tipo_estoque, categoria_medida, unidade_compra, custo)
           values ('Batata', 'Longo Prazo', 'Peso', 'kg', 400) returning id) select testes.def('batata', id) from p;
with b as (insert into pratos_base (nome, componentes) values ('Muamba', jsonb_build_array(
             jsonb_build_object('produto_id', testes.v('frango'), 'quantidade', 250, 'unidade', 'g'),
             jsonb_build_object('produto_id', testes.v('cebola'), 'quantidade', 50, 'unidade', 'g'),
             jsonb_build_object('produto_id', testes.v('jindungo'), 'quantidade', 2, 'unidade', 'un'),
             jsonb_build_object('produto_id', testes.v('sal'), 'quantidade', 5, 'unidade', 'g'))) returning id)
select testes.def('base_muamba', id) from b;
with m as (insert into cardapio (nome, preco, prato_base_id) values ('Muamba', 4000, testes.u('base_muamba')) returning id)
select testes.def('muamba', id) from m;
-- "Monta o teu prato": preço 0, a Base obrigatória dá o preço
with m as (insert into cardapio (nome, preco, prato_base_id) values ('Monta o teu prato', 0, testes.u('base_muamba')) returning id)
select testes.def('monta', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('monta'), 'Base', 1, 1) returning id)
select testes.def('g_base', id) from g;
with o as (insert into opcoes (grupo_id, nome, preco_extra) values (testes.u('g_base'), 'Arroz', 1000) returning id) select testes.def('arroz', id) from o;
with m as (insert into cardapio (nome, preco) values ('Erro a zero', 0) returning id) select testes.def('zero', id) from m;

select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));
create function testes.orc(p_itens jsonb) returns text language plpgsql as $$
begin
  return (select orcamento_pedido(p_itens, testes.u('casa'))::text);
exception when others then
  return sqlstate || ':' || sqlerrm;
end $$;
create function pg_temp.item(p_cardapio text, p_qtd int, p_excl jsonb default null, p_opcoes jsonb default null) returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('cardapio_id', testes.v(p_cardapio), 'qtd', p_qtd,
                                              'componentes_excluidos', p_excl, 'opcoes', p_opcoes));
$$;

-- O que a app mostra
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('comp', componentes_dos_pratos(array[testes.u('muamba')]));
reset role;
select is((select jsonb_agg(jsonb_build_array(e ->> 'nome', (e ->> 'valor')::int) order by e ->> 'nome') from jsonb_array_elements(testes.v('comp')::jsonb) e),
          '[["Cebola", 25], ["Frango", 1026], ["Jindungo", 200], ["Sal", 0]]'::jsonb,
          'ingredientes da receita com o valor de cada um (custo × margem × IVA × quantidade; sem custo = 0)');
select ok(testes.v('comp') not like '%custo%' and testes.v('comp') not like '%margem%', 'sem mostrar custos nem margens');

-- Orçamento
set local role authenticated;
select testes.def('r1', testes.orc(jsonb_build_array(pg_temp.item('muamba', 2, jsonb_build_array(testes.v('cebola'), testes.v('jindungo'))))));
select testes.def('r_fora', testes.orc(jsonb_build_array(pg_temp.item('muamba', 1, jsonb_build_array(testes.v('batata'))))));
select testes.def('r_rep', testes.orc(jsonb_build_array(pg_temp.item('muamba', 1, jsonb_build_array(testes.v('sal'), testes.v('sal'))))));
select testes.def('r_todos', testes.orc(jsonb_build_array(pg_temp.item('muamba', 1,
         jsonb_build_array(testes.v('frango'), testes.v('cebola'), testes.v('jindungo'), testes.v('sal'))))));
select testes.def('r_ajust', testes.orc(jsonb_build_array(pg_temp.item('muamba', 1) || jsonb_build_object('componentes_ajustados',
         jsonb_build_array(jsonb_build_object('produto_id', testes.v('frango'), 'quantidade', 2000, 'unidade', 'g'))))));
select testes.def('r_monta', testes.orc(jsonb_build_array(pg_temp.item('monta', 1, jsonb_build_array(testes.v('cebola')), jsonb_build_array(testes.v('arroz'))))));
select testes.def('r_monta_sem', testes.orc(jsonb_build_array(pg_temp.item('monta', 1))));
select testes.def('r_zero', testes.orc(jsonb_build_array(pg_temp.item('zero', 1))));
reset role;
select is((testes.v('r1')::jsonb -> 'itens' -> 0) - 'cardapio_id' - 'prato_base_id',
          jsonb_build_object('nome', 'Muamba (sem Cebola, Jindungo)', 'qtd', 2, 'preco_unitario', 3775,
                             'componentes_excluidos', jsonb_build_array(testes.v('cebola'), testes.v('jindungo')),
                             'desconto_componentes', 225),
          'tirar cebola e jindungo: 4000 − 25 − 200 = 3775 por prato, e o nome diz o que vai sem');
select is((testes.v('r1')::jsonb ->> 'subtotal')::int, 7550, 'subtotal = 2 × 3775');
select ok(testes.v('r_fora') = 'P0001:componentes_invalidos' and testes.v('r_rep') = 'P0001:componentes_invalidos'
          and testes.v('r_todos') = 'P0001:componentes_todos_excluidos',
          'só ingredientes da receita, sem repetir e sem tirar todos');
select ok(testes.v('r_ajust')::jsonb -> 'itens' -> 0 -> 'componentes_ajustados' is null
          and (testes.v('r_ajust')::jsonb -> 'itens' -> 0 ->> 'preco_unitario')::int = 4000,
          'ajustes de quantidade vindos da app são ignorados (não há como os pagar)');
select ok(testes.v('r_monta')::jsonb -> 'itens' -> 0 ->> 'nome' = 'Monta o teu prato (Arroz; sem Cebola)'
          and (testes.v('r_monta')::jsonb -> 'itens' -> 0 ->> 'preco_unitario')::int = 975,
          'prato a 0 Kz: o preço vem das opções (0 + 1000 do arroz − 25 da cebola)');
select ok(testes.v('r_monta_sem') = 'P0001:opcoes_em_falta' and testes.v('r_zero') like 'P0001:item_sem_preco%',
          'sem opções que lhe dêem preço, um prato a 0 Kz é recusado');

-- Interruptor desligado: não se tira nada e paga-se o prato inteiro
select testes.funcionalidade('pratos_montaveis', false);
set local role authenticated;
select testes.def('r_off', testes.orc(jsonb_build_array(pg_temp.item('muamba', 1, jsonb_build_array(testes.v('cebola'))))));
reset role;
select ok((testes.v('r_off')::jsonb -> 'itens' -> 0 ->> 'preco_unitario')::int = 4000
          and testes.v('r_off')::jsonb -> 'itens' -> 0 -> 'componentes_excluidos' is null,
          'com o interruptor desligado não se tira nada');
select testes.funcionalidade('pratos_montaveis', true);

-- O pedido feito pela app e o stock
set local role authenticated;
with p as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('ana'), testes.u('casa'), jsonb_build_array(
             pg_temp.item('muamba', 1, jsonb_build_array(testes.v('frango'))) || '{"preco_unitario": 1}'::jsonb))
           returning id)
select testes.def('pedido', id) from p;
reset role;
select is((select subtotal || '|' || (itens -> 0 ->> 'nome') from pedidos where id = testes.u('pedido')), '2974|Muamba (sem Frango)',
          'o pedido fica com o preço do servidor (4000 − 1026), não o que a app enviou');
select testes.pagar(testes.u('pedido'));
select is((select coalesce(jsonb_agg(p.nome order by p.nome), '[]') from estoque_longo_prazo e join produtos p on p.id = e.produto_id
             join vendas v on v.id = e.venda_id where v.pedido_id = testes.u('pedido')),
          '["Cebola", "Jindungo", "Sal"]'::jsonb, 'o stock não desconta o frango que foi tirado');

select ok(not has_function_privilege('authenticated', 'valor_componente(uuid, numeric, text)', 'execute')
          and not has_function_privilege('anon', 'componentes_dos_pratos(uuid[])', 'execute')
          and has_function_privilege('authenticated', 'componentes_dos_pratos(uuid[])', 'execute'),
          'o cálculo fica no servidor; a lista de ingredientes só com sessão');

select * from finish();
rollback;
