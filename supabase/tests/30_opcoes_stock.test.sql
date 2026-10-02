-- I9 · As opções dos pratos montáveis descontam stock na venda gerada do pedido
begin;
\ir _helpers.psql
select plan(9);

with dados (chave, nome, tipo, medida) as (values
       ('frango', 'Frango',  'Longo Prazo', 'Peso'),
       ('arroz',  'Arroz',   'Longo Prazo', 'Peso'),
       ('ovo',    'Ovo',     'Longo Prazo', 'Unidade'),
       ('salada', 'Alface',  'Diário',      'Unidade')),
     p as (insert into produtos (nome, tipo_estoque, categoria_medida)
           select nome, tipo, medida from dados returning id, nome)
select testes.def(d.chave, p.id) from p join dados d using (nome);

with x as (insert into pratos_base (nome, componentes)
           values ('Frango grelhado', jsonb_build_array(
                     jsonb_build_object('produto_id', testes.u('frango'), 'quantidade', 0.25, 'unidade', 'kg'),
                     jsonb_build_object('produto_id', testes.u('arroz'),  'quantidade', 100,  'unidade', 'g')))
           returning id)
select testes.def('base', id) from x;

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco, prato_base_id) values ('Frango', 3000, testes.u('base')) returning id) select testes.def('prato', id) from m;
with m as (insert into cardapio (nome, preco) values ('Salada', 1000) returning id) select testes.def('so_opcoes', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('prato'), 'Extras', 0, 3) returning id)
select testes.def('g', id) from g;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('so_opcoes'), 'Extras', 0, 1) returning id)
select testes.def('g2', id) from g;
-- Mais arroz (o mesmo produto da receita soma-se), um ovo, salada (stock diário) e uma opção mal registada
with o as (insert into opcoes (grupo_id, nome, preco_extra, componentes) values (testes.u('g'), 'Mais arroz', 300,
           jsonb_build_array(jsonb_build_object('produto_id', testes.u('arroz'), 'quantidade', 0.05, 'unidade', 'kg'))) returning id)
select testes.def('o_arroz', id) from o;
with o as (insert into opcoes (grupo_id, nome, preco_extra, componentes) values (testes.u('g'), 'Ovo', 200,
           jsonb_build_array(jsonb_build_object('produto_id', testes.u('ovo'), 'quantidade', 1, 'unidade', 'un'),
                             jsonb_build_object('produto_id', testes.u('salada'), 'quantidade', 1, 'unidade', 'un'))) returning id)
select testes.def('o_ovo', id) from o;
with o as (insert into opcoes (grupo_id, nome, componentes) values (testes.u('g'), 'Molho', 
           jsonb_build_array(jsonb_build_object('produto_id', testes.u('frango'), 'quantidade', 2, 'unidade', 'chávena'))) returning id)
select testes.def('o_molho', id) from o;
with o as (insert into opcoes (grupo_id, nome, componentes) values (testes.u('g2'), 'Com ovo',
           jsonb_build_array(jsonb_build_object('produto_id', testes.u('ovo'), 'quantidade', 2, 'unidade', 'un'))) returning id)
select testes.def('o_so', id) from o;

select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));
select testes.funcionalidade('pratos_montaveis', true);

create function testes.pedir(p_prato uuid, p_qtd int, p_opcoes uuid[]) returns uuid language plpgsql as $$
declare v uuid;
begin
  perform testes.entrar(testes.u('ana'));
  set local role authenticated;
  insert into pedidos (cliente_id, ponto_entrega_id, itens)
  values (testes.u('ana'), testes.u('casa'),
          jsonb_build_array(jsonb_build_object('cardapio_id', p_prato, 'qtd', p_qtd, 'opcoes', to_jsonb(p_opcoes))))
  returning id into v;
  reset role;
  perform testes.sair();
  perform testes.pagar(v);
  return v;
end $$;
create function testes.consumo(p_pedido uuid, p_produto uuid) returns numeric language sql as $$
  select sum(e.quantidade) from estoque_longo_prazo e join vendas v on v.id = e.venda_id
   where v.pedido_id = p_pedido and e.produto_id = p_produto and e.tipo = 'Consumo';
$$;

-- 2 pratos com mais arroz e ovo
select testes.def('p1', testes.pedir(testes.u('prato'), 2, array[testes.u('o_arroz'), testes.u('o_ovo')]));
select is(testes.consumo(testes.u('p1'), testes.u('frango')), 500.00, 'receita do prato: 2 × 250 g de frango');
select is(testes.consumo(testes.u('p1'), testes.u('arroz')), 300.00, 'arroz da receita e da opção somam: 2 × (100 g + 50 g)');
select is(testes.consumo(testes.u('p1'), testes.u('ovo')), 2::numeric, 'opção Ovo: 2 × 1 ovo');
select is(testes.consumo(testes.u('p1'), testes.u('salada')), null, 'produto de stock diário não gera movimento por venda');

-- Sem opções: só a receita
select testes.def('p2', testes.pedir(testes.u('prato'), 1, array[]::uuid[]));
select is(testes.consumo(testes.u('p2'), testes.u('arroz')), 100.00, 'sem opções: só a receita do prato');

-- Prato sem receita, só com opções
select testes.def('p3', testes.pedir(testes.u('so_opcoes'), 3, array[testes.u('o_so')]));
select is(testes.consumo(testes.u('p3'), testes.u('ovo')), 6::numeric, 'prato sem receita: as opções descontam (3 × 2 ovos)');

-- Opção com unidade desconhecida: avisa, não desconta
select testes.def('p4', testes.pedir(testes.u('prato'), 1, array[testes.u('o_molho')]));
select is((select count(*)::int from auditoria a join vendas v on v.id = a.ref_id
            where v.pedido_id = testes.u('p4') and a.acao = 'stock_consumo_pendente'), 1,
          'opção com unidade desconhecida fica como consumo pendente');

-- Ingrediente sem quantidade numérica: a entrega não falha, fica pendente
update opcoes set componentes = jsonb_build_array(jsonb_build_object('produto_id', testes.u('ovo'), 'quantidade', 'muito', 'unidade', 'un'))
 where id = testes.u('o_molho');
select lives_ok(format($$select testes.pedir(%L, 1, array[%L]::uuid[])$$, testes.v('prato'), testes.v('o_molho')),
                'ingrediente mal escrito não trava a entrega');

select throws_ok(format($$update opcoes set componentes = '{"x": 1}' where id = %L$$, testes.v('o_ovo')),
                 '23514', null, 'os ingredientes de uma opção são uma lista');

select * from finish();
rollback;
