-- Consumo de stock das vendas geradas de pedidos (regra 3): o servidor desconta
-- só as vendas que gera; as vendas da app do operador ficam com a app.
begin;
\ir _helpers.psql
select plan(35);

-- ---------------------------------------------------------------------------
-- Catálogo: produtos e pratos
-- ---------------------------------------------------------------------------
with dados (chave, nome, tipo, medida) as (values
       ('frango',   'Frango',        'Longo Prazo', 'Peso'),
       ('oleo',     'Óleo de palma', 'Longo Prazo', 'Volume'),
       ('jindungo', 'Jindungo',      'Longo Prazo', 'Unidade'),
       ('pao',      'Pão do dia',    'Diário',      'Unidade'),
       ('sem_tipo', 'Sem tipo',      null,          'Peso')),
     p as (insert into produtos (nome, tipo_estoque, categoria_medida)
           select nome, tipo, medida from dados returning id, nome)
select testes.def(d.chave, p.id) from p join dados d using (nome);

with x as (insert into pratos_base (nome, componentes)
           values ('Muamba de galinha', jsonb_build_array(
                     jsonb_build_object('produto_id', testes.u('frango'),        'quantidade', 0.25, 'unidade', 'kg'),
                     jsonb_build_object('produto_id', testes.u('oleo'), 'quantidade', 0.05, 'unidade', 'l'),
                     jsonb_build_object('produto_id', testes.u('jindungo'),      'quantidade', 1,    'unidade', 'un'),
                     jsonb_build_object('produto_id', testes.u('pao'),    'quantidade', 1,    'unidade', 'un')))
           returning id)
select testes.def('muamba', id) from x;

with x as (insert into pratos_base (nome, componentes)
           values ('Prato mal registado', jsonb_build_array(
                     jsonb_build_object('produto_id', testes.u('frango'),   'quantidade', 2,   'unidade', 'chávena'),
                     jsonb_build_object('produto_id', testes.u('sem_tipo'), 'quantidade', 100, 'unidade', 'g'),
                     jsonb_build_object('produto_id', testes.u('jindungo'), 'quantidade', 2,   'unidade', 'un')))
           returning id)
select testes.def('mal_registado', id) from x;

with x as (insert into pratos_base (nome, componentes, deletado_em)
           values ('Prato apagado', '[]', now()) returning id)
select testes.def('apagado', id) from x;

select testes.def('cliente', testes.cliente('Rita Cliente'));
select testes.def('casa', testes.ponto('residencial'));

-- ---------------------------------------------------------------------------
-- 1. Conversão para a unidade base
-- ---------------------------------------------------------------------------
select is(quantidade_unidade_base(0.25, 'kg', 'Peso'), 250.00, 'kg -> g (0,25 kg = 250 g)');
select is(quantidade_unidade_base(0.05, ' L ', 'Volume'), 50.00, 'l -> ml (0,05 l = 50 ml)');
select is(quantidade_unidade_base(3, 'un', 'Unidade'), 3::numeric, 'unidade -> unidade');
select is(quantidade_unidade_base(1, 'kg', 'Volume'), null, 'unidade incompatível com a categoria -> desconhecida');
select is(quantidade_unidade_base(2, 'chávena', 'Peso'), null, 'unidade desconhecida -> null');

-- ---------------------------------------------------------------------------
-- 2. Validação dos itens na criação do pedido
-- ---------------------------------------------------------------------------
select throws_ok(format($$insert into pedidos (cliente_id, itens) values (%L, %L)$$, testes.u('cliente'),
                        jsonb_build_array(jsonb_build_object('nome', 'X', 'qtd', 1, 'prato_base_id', gen_random_uuid()))),
                 'P0001', 'prato_invalido', 'prato inexistente -> pedido recusado');
select throws_ok(format($$insert into pedidos (cliente_id, itens) values (%L, %L)$$, testes.u('cliente'),
                        '[{"nome": "X", "qtd": 1, "prato_base_id": "abc"}]'),
                 'P0001', 'prato_invalido', 'id de prato mal formado -> pedido recusado');
select throws_ok(format($$insert into pedidos (cliente_id, itens) values (%L, %L)$$, testes.u('cliente'),
                        jsonb_build_array(jsonb_build_object('nome', 'X', 'qtd', 1, 'prato_base_id', testes.u('apagado')))),
                 'P0001', 'prato_invalido', 'prato apagado -> pedido recusado');
select throws_ok(format($$insert into pedidos (cliente_id, itens) values (%L, %L)$$, testes.u('cliente'),
                        jsonb_build_array(jsonb_build_object('nome', 'X', 'qtd', 1,
                                                             'componentes_excluidos', jsonb_build_array(testes.u('jindungo'))))),
                 'P0001', 'componentes_sem_prato', 'componentes sem prato -> pedido recusado');
select throws_ok(format($$insert into pedidos (cliente_id, itens) values (%L, %L)$$, testes.u('cliente'),
                        jsonb_build_array(jsonb_build_object('nome', 'X', 'qtd', 1, 'prato_base_id', testes.u('muamba'),
                          'componentes_ajustados', jsonb_build_array(jsonb_build_object('produto_id', testes.u('frango'),
                                                                                        'quantidade', 'muito'))))),
                 'P0001', 'componentes_invalidos', 'ajuste com quantidade inválida -> pedido recusado');
select lives_ok(format($$insert into pedidos (cliente_id, itens) values (%L, '[{"nome": "Sumo", "qtd": 1, "preco_unitario": 500}]')$$,
                       testes.u('cliente')),
                'item sem prato_base_id é aceite (bebidas e extras)');

-- ---------------------------------------------------------------------------
-- 3. Consumo de uma venda gerada de um pedido
--    2 × Muamba sem jindungo e com 0,1 l de óleo; 1 × Sumo sem prato
-- ---------------------------------------------------------------------------
with x as (
  insert into pedidos (cliente_id, ponto_entrega_id, subtotal, itens)
  values (testes.u('cliente'), testes.u('casa'), 5500, jsonb_build_array(
            jsonb_build_object('nome', 'Muamba de galinha', 'qtd', 2, 'preco_unitario', 2500,
                               'prato_base_id', testes.u('muamba'),
                               'componentes_excluidos', jsonb_build_array(testes.u('jindungo')),
                               'componentes_ajustados', jsonb_build_array(jsonb_build_object(
                                  'produto_id', testes.u('oleo'), 'quantidade', 0.1, 'unidade', 'l'))),
            jsonb_build_object('nome', 'Sumo', 'qtd', 1, 'preco_unitario', 500)))
  returning id, cozinha_id)
select testes.def('p', id), testes.def('cozinha_p', cozinha_id) from x;

select testes.def('diario_antes', (select count(*) from estoque_diario));
select testes.pagar(testes.u('p'));

select results_eq(
  format($$select linha_pedido, stock_consumido_por, componentes_excluidos is not null, componentes_ajustados is not null
             from vendas where pedido_id = %L order by linha_pedido$$, testes.u('p')),
  $$values (1, 'servidor'::text, true, true), (2, 'servidor'::text, false, false)$$,
  'vendas do pedido marcadas servidor; componentes copiados do item');

select results_eq(
  format($$select p.nome, e.tipo, e.quantidade
             from estoque_longo_prazo e join produtos p on p.id = e.produto_id
             join vendas v on v.id = e.venda_id
            where v.pedido_id = %L order by p.nome$$, testes.u('p')),
  $$values ('Frango'::text, 'Consumo'::text, 500.000), ('Óleo de palma'::text, 'Consumo'::text, 200.000)$$,
  'consumo: frango 2 × 250 g; óleo ajustado 2 × 100 ml; jindungo excluído; pão (Diário) não desconta');

select is((select count(distinct e.cozinha_id)::int from estoque_longo_prazo e join vendas v on v.id = e.venda_id
            where v.pedido_id = testes.u('p') and e.cozinha_id = testes.u('cozinha_p')), 1,
          'consumo registado na cozinha da venda');
select is((select count(*) from estoque_diario)::text, testes.v('diario_antes'),
          'produtos diários: nenhum movimento por venda');
select is((select count(*)::int from estoque_longo_prazo e join vendas v on v.id = e.venda_id
            where v.pedido_id = testes.u('p') and v.linha_pedido = 2), 0,
          'item sem prato não desconta stock');

-- Repetir o estado não volta a descontar
update pedidos set estado = 'entregue_pago' where id = testes.u('p');
select is((select count(*)::int from estoque_longo_prazo e join vendas v on v.id = e.venda_id
            where v.pedido_id = testes.u('p')), 2, 'repetir entregue_pago não volta a descontar');

-- Segunda tentativa do servidor: não duplica
insert into estoque_longo_prazo (dispositivo_id, produto_id, tipo, quantidade, venda_id)
select 'servidor', testes.u('frango'), 'Consumo', 500, id from vendas where pedido_id = testes.u('p') and linha_pedido = 1
on conflict (venda_id, produto_id) where venda_id is not null do nothing;
select is((select count(*)::int from estoque_longo_prazo e join vendas v on v.id = e.venda_id
            where v.pedido_id = testes.u('p')), 2, 'segunda tentativa do servidor não duplica o consumo');
select throws_ok(format($$insert into estoque_longo_prazo (dispositivo_id, produto_id, tipo, quantidade, venda_id)
                          select 'servidor', %L, 'Consumo', 1, id from vendas where pedido_id = %L and linha_pedido = 1$$,
                        testes.u('frango'), testes.u('p')),
                 '23505', null, 'índice único (venda_id, produto_id) impede consumo duplicado');

-- ---------------------------------------------------------------------------
-- 4. Estorno: não desconta nem repõe stock
-- ---------------------------------------------------------------------------
select testes.def('lp_antes', (select count(*) from estoque_longo_prazo));
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
select testes.entrar_funcionario(testes.u('gerente'));
select lives_ok(format($$select mudar_estado_pedido(%L, 'estornado', 'Cliente devolveu')$$, testes.u('p')),
                'gerente estorna o pedido');
select testes.sair();
select is((select count(*)::int from vendas where pedido_id = testes.u('p') and origem = 'App cliente (estorno)'
              and not movimenta_stock), 2, 'compensações com movimenta_stock = false');
select is((select count(*) from estoque_longo_prazo)::text, testes.v('lp_antes'),
          'regra 3: o estorno não cria nem repõe movimentos de stock');

-- ---------------------------------------------------------------------------
-- 5. Vendas da app do operador: o servidor nunca lhes toca
-- ---------------------------------------------------------------------------
select testes.def('lp_antes_op', (select count(*) from estoque_longo_prazo));
with v as (insert into vendas (produto, qtd, valor_total, prato_base_id, origem)
           values ('Muamba de galinha', 3, 7500, testes.u('muamba'), 'Venda direta') returning stock_consumido_por)
select testes.def('op_default', stock_consumido_por) from v;
select is(testes.v('op_default'), 'dispositivo', 'venda do operador: dispositivo por defeito');
select is((select count(*) from estoque_longo_prazo)::text, testes.v('lp_antes_op'),
          'venda do operador não é descontada pelo servidor');

-- Um dispositivo não consegue marcar servidor (simulado com uma política só desta transacção)
create policy teste_inserir on vendas for insert to authenticated with check (true);
select testes.def('operador', testes.funcionario('Operadora', array[]::text[]));
select testes.entrar_funcionario(testes.u('operador'));
set local role authenticated;
insert into vendas (produto, qtd, valor_total, prato_base_id, origem, stock_consumido_por, dispositivo_id)
values ('Muamba de galinha', 1, 2500, testes.u('muamba'), 'Venda direta', 'servidor', 'tablet-1');
reset role;
select testes.sair();
select is((select stock_consumido_por from vendas where dispositivo_id = 'tablet-1'), 'dispositivo',
          'dispositivo que envia servidor fica com dispositivo');
select is((select count(*) from estoque_longo_prazo)::text, testes.v('lp_antes_op'),
          'e o servidor não desconta essa venda');

update vendas set stock_consumido_por = 'dispositivo' where pedido_id = testes.u('p') and linha_pedido = 1
   and origem = 'App cliente';
select is((select stock_consumido_por from vendas where pedido_id = testes.u('p') and linha_pedido = 1
              and origem = 'App cliente'), 'servidor', 'o responsável pelo desconto não muda depois de criado');

-- ---------------------------------------------------------------------------
-- 6. Receita mal registada: a venda passa e fica um aviso
-- ---------------------------------------------------------------------------
with x as (
  insert into pedidos (cliente_id, subtotal, itens)
  values (testes.u('cliente'), 2000, jsonb_build_array(jsonb_build_object(
            'nome', 'Prato mal registado', 'qtd', 1, 'preco_unitario', 2000, 'prato_base_id', testes.u('mal_registado'))))
  returning id)
select testes.def('pm', id) from x;
select lives_ok(format($$select testes.pagar(%L)$$, testes.u('pm')), 'entrega com receita mal registada não falha');
select results_eq(
  format($$select a.detalhe::jsonb ->> 'motivo' from auditoria a join vendas v on v.id = a.ref_id
            where a.acao = 'stock_consumo_pendente' and v.pedido_id = %L order by 1$$, testes.u('pm')),
  $$values ('produto_sem_tipo_stock'::text), ('unidade_desconhecida'::text)$$,
  'avisos stock_consumo_pendente: unidade desconhecida e produto sem tipo de stock');
select results_eq(
  format($$select p.nome, e.quantidade from estoque_longo_prazo e join produtos p on p.id = e.produto_id
             join vendas v on v.id = e.venda_id where v.pedido_id = %L$$, testes.u('pm')),
  $$values ('Jindungo'::text, 2.000)$$,
  'os componentes bem registados são descontados');

-- ---------------------------------------------------------------------------
-- 7. Guarda (regra 10): consumo de vendas 'App cliente' só pelo servidor
-- ---------------------------------------------------------------------------
select testes.def('venda_app', (select id from vendas where pedido_id = testes.u('p') and linha_pedido = 1
                                   and origem = 'App cliente'));
select testes.def('lp_guarda', (select count(*) from estoque_longo_prazo));

-- Fila de saída de um tablet (serviço de sincronização) a enviar um consumo dessa venda
insert into estoque_longo_prazo (dispositivo_id, produto_id, tipo, quantidade, venda_id)
values ('tablet-1', testes.u('jindungo'), 'Consumo', 2, testes.u('venda_app'));
select is((select count(*) from estoque_longo_prazo)::text, testes.v('lp_guarda'),
          'consumo enviado por dispositivo para venda App cliente é rejeitado');
select ok(exists (select 1 from auditoria where acao = 'consumo_dispositivo_bloqueado' and bloqueado
                    and detalhe::jsonb ->> 'venda_id' = testes.v('venda_app')
                    and detalhe::jsonb ->> 'dispositivo_id' = 'tablet-1'),
          'tentativa registada na auditoria como bloqueada');

-- Sessão do telemóvel a fingir ser o servidor (política só desta transacção)
create policy teste_inserir_stock on estoque_longo_prazo for insert to authenticated with check (true);
select testes.entrar_funcionario(testes.u('operador'));
set local role authenticated;
insert into estoque_longo_prazo (dispositivo_id, produto_id, tipo, quantidade, venda_id)
values ('servidor', testes.u('jindungo'), 'Consumo', 2, testes.u('venda_app'));
reset role;
select testes.sair();
select is((select count(*)::int from auditoria where acao = 'consumo_dispositivo_bloqueado' and bloqueado), 2,
          'sessão de dispositivo com dispositivo_id = servidor também é rejeitada e auditada');

-- Dispositivo a alterar o consumo do servidor
update estoque_longo_prazo set quantidade = 0, dispositivo_id = 'tablet-1'
 where venda_id = testes.u('venda_app') and produto_id = testes.u('frango');
select is((select quantidade from estoque_longo_prazo
            where venda_id = testes.u('venda_app') and produto_id = testes.u('frango')), 500.000,
          'dispositivo não altera o consumo do servidor');

-- Venda do operador: o consumo do dispositivo é aceite
select testes.def('venda_op', (select id from vendas where dispositivo_id = 'tablet-1'));
insert into estoque_longo_prazo (dispositivo_id, produto_id, tipo, quantidade, venda_id)
values ('tablet-1', testes.u('frango'), 'Consumo', 250, testes.u('venda_op'));
select is((select count(*)::int from estoque_longo_prazo where venda_id = testes.u('venda_op')), 1,
          'consumo do dispositivo para venda do operador é aceite');

select * from finish();
rollback;
