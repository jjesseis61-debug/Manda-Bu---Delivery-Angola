-- Decisões de I1: duração garantida, vendas por item (regra 7), caixa na
-- entrega (regra 8), estorno sem reposição de stock (regra 3), catálogo de
-- permissões.
begin;
\ir _helpers.psql
select plan(29);

select testes.funcionalidade('indicacao', true);
select testes.def('gestor', testes.funcionario('Gestora', array['plataforma.parametros']));
select testes.def('entregador', testes.funcionario('Entregador', array['entregas.registar']));
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
select testes.def('ana', testes.cliente('Ana Indicadora'));

-- ---------------------------------------------------------------------------
-- 1. Duração garantida na ligação
-- ---------------------------------------------------------------------------
select testes.def('carla', testes.indicado(testes.u('ana'), 'Carla'));
select is((select duracao_dias_garantida from ligacoes_indicacao where indicado_id = testes.u('carla')), 60,
          'ligação guarda a duração em vigor (60 dias)');

select testes.entrar_funcionario(testes.u('gestor'));
select lives_ok($$select alterar_parametros('{"duracao_dias": 30}')$$, 'duração alterada para 30 dias');
select testes.sair();

select testes.def('pc', testes.pedido(testes.u('carla'), testes.ponto('residencial')));
select testes.pagar(testes.u('pc'));
select is((select expira_em from ligacoes_indicacao where indicado_id = testes.u('carla')),
          (select entregue_em + interval '60 days' from pedidos where id = testes.u('pc')),
          'ligação anterior à alteração: expira_em = 1.º pedido pago + 60 dias (garantidos)');

select testes.def('dora', testes.indicado(testes.u('ana'), 'Dora'));
select is((select duracao_dias_garantida from ligacoes_indicacao where indicado_id = testes.u('dora')), 30,
          'nova ligação guarda a duração nova (30 dias)');
select testes.def('pd', testes.pedido(testes.u('dora'), testes.ponto('residencial')));
select testes.pagar(testes.u('pd'));
select is((select expira_em from ligacoes_indicacao where indicado_id = testes.u('dora')),
          (select entregue_em + interval '30 days' from pedidos where id = testes.u('pd')),
          'nova ligação: expira_em = 1.º pedido pago + 30 dias');

-- ---------------------------------------------------------------------------
-- 2 e 3. Venda por item, com a caixa onde o dinheiro entrou
-- ---------------------------------------------------------------------------
-- Bruno: indicado da Ana (desconto 500) e com 300 Kz de saldo próprio (crédito)
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno'));
select testes.ganhos(testes.u('bruno'), 3, 100);
with z as (insert into zonas (nome, tipo) values ('Talatona', 'Própria') returning id)
select testes.def('zona', id) from z;
with x as (
  insert into pedidos (cliente_id, ponto_entrega_id, subtotal, taxa_entrega, itens)
  values (testes.u('bruno'), testes.ponto('residencial', null, null, testes.u('zona')), 4500, 700,
          '[{"nome": "Muamba de galinha", "qtd": 1, "preco_unitario": 1000},
            {"nome": "Calulu",            "qtd": 2, "preco_unitario": 1500},
            {"nome": "Sumo de múcua",     "qtd": 1, "preco_unitario": 500}]')
  returning id)
select testes.def('p', id) from x;
select is((select desconto_indicacao from pedidos where id = testes.u('p')), 500, 'pedido com desconto de 500 Kz');
select testes.entrar(testes.u('bruno'));
select lives_ok(format($$select usar_credito(%L, 300)$$, testes.u('p')), 'Bruno usa 300 Kz de crédito');
select testes.sair();

-- Caixas: uma fechada, uma aberta no Posto Talatona
with c as (insert into caixa (posto, cozinha_id, troco_inicial, fechamento)
           values ('Posto Fechado', cozinha_padrao(), 0, '{"diferenca": 0}') returning id)
select testes.def('caixa_fechada', id) from c;
select testes.def('caixa', testes.caixa(null, 'Posto Talatona'));

select testes.entrar_funcionario(testes.u('entregador'));
select throws_ok(format($$select mudar_estado_pedido(%L, 'entregue_pago')$$, testes.u('p')),
                 'P0001', 'caixa_obrigatoria', 'regra 8: entregue_pago sem caixa -> recusado');
select throws_ok(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L)$$,
                        testes.u('p'), testes.u('caixa_fechada')),
                 'P0001', 'caixa_invalida', 'regra 8: caixa já fechada -> recusado');
select throws_ok(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
                        testes.u('p'), testes.u('caixa'), '[{"metodo": "Dinheiro", "valor": 1000}]'),
                 'P0001', 'parcelas_nao_somam_valor_final', 'regra 7: parcelas que não somam o valor final -> recusado');
select lives_ok(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
                       testes.u('p'), testes.u('caixa'),
                       '[{"metodo": "Dinheiro", "valor": 2000}, {"metodo": "Multicaixa Express", "valor": 2400}]'),
                'entregue_pago com caixa e parcelas (2000 + 2400 + 300 de crédito = 4700)');
select testes.sair();

-- Valor final = 4500 + 700 − 500 = 4700; bruto por item 1000 / 3000 / 500
select results_eq(
  format($$select linha_pedido, produto, qtd::int, valor_antes_desconto::int, desconto_aplicado::int,
                  valor_total::int, taxa_entrega::int
             from vendas where pedido_id = %L and origem = 'App cliente' order by linha_pedido$$, testes.u('p')),
  $$values (1, 'Muamba de galinha'::text, 1, 1700, 163, 1537, 700),
           (2, 'Calulu'::text,            2, 3000, 288, 2712, 0),
           (3, 'Sumo de múcua'::text,     1,  500,  49,  451, 0)$$,
  'uma venda por item; taxa só na 1.ª; desconto proporcional com arredondamento na última');
select is((select sum(valor_total)::int from vendas where pedido_id = testes.u('p') and origem = 'App cliente'), 4700,
          'regra 7: soma das vendas = valor final do pedido');
select is((select count(*)::int from vendas v
            where v.pedido_id = testes.u('p') and v.origem = 'App cliente'
              and v.valor_total <> (select sum((x ->> 'valor')::numeric) from jsonb_array_elements(v.parcelas) x)), 0,
          'em cada venda, as parcelas somam o total da linha');
select results_eq(
  format($$select x ->> 'metodo', sum((x ->> 'valor')::numeric)::int
             from vendas v, jsonb_array_elements(v.parcelas) x
            where v.pedido_id = %L and v.origem = 'App cliente'
            group by 1 order by 1$$, testes.u('p')),
  $$values ('Crédito indicação'::text, 300), ('Dinheiro'::text, 2000), ('Multicaixa Express'::text, 2400)$$,
  'cada parcela repartida pelas vendas soma o valor recebido');
select results_eq(
  format($$select x ->> 'metodo', (x ->> 'valor')::int from vendas v, jsonb_array_elements(v.parcelas) x
            where v.pedido_id = %L and v.origem = 'App cliente' and v.linha_pedido = 3 order by 1$$, testes.u('p')),
  $$values ('Crédito indicação'::text, 29), ('Dinheiro'::text, 192), ('Multicaixa Express'::text, 230)$$,
  'arredondamento das parcelas acertado na última venda');
select is((select count(*)::int from vendas
            where pedido_id = testes.u('p') and origem = 'App cliente'
              and local = 'Posto Talatona' and caixa_id = testes.u('caixa')), 3,
          'regra 8: cada venda regista o posto e a caixa onde o dinheiro entrou');
select is((select zona_nome from vendas where pedido_id = testes.u('p') and linha_pedido = 1), 'Talatona',
          'venda regista a zona do ponto de entrega');
select ok((select indexdef like '%(pedido_id, linha_pedido, origem)%' from pg_indexes
            where indexname = 'vendas_pedido_linha_origem_key'),
          'índice único (pedido_id, linha_pedido, origem)');
update pedidos set estado = 'entregue_pago' where id = testes.u('p');
select is((select count(*)::int from vendas where pedido_id = testes.u('p')), 3,
          'repetir o estado não duplica as vendas');

-- ---------------------------------------------------------------------------
-- 4. Estorno: a venda de compensação não repõe stock (regra 3)
-- ---------------------------------------------------------------------------
select testes.def('stock_antes', (select (select count(*) from estoque_diario) + (select count(*) from estoque_longo_prazo)));
select testes.entrar_funcionario(testes.u('gerente'));
select lives_ok(format($$select mudar_estado_pedido(%L, 'estornado', 'Cliente devolveu')$$, testes.u('p')),
                'gerente estorna o pedido');
select testes.sair();
select results_eq(
  format($$select linha_pedido, qtd::int, valor_total::int, movimenta_stock
             from vendas where pedido_id = %L and origem = 'App cliente (estorno)' order by linha_pedido$$, testes.u('p')),
  $$values (1, 0, -1537, false), (2, 0, -2712, false), (3, 0, -451, false)$$,
  'estorno: uma compensação por venda, valores negativos, qtd 0, sem movimento de stock');
select is((select sum(valor_total)::int from vendas where pedido_id = testes.u('p')), 0,
          'vendas e compensações somam 0');
select is((select sum((x ->> 'valor')::numeric)::int from vendas v, jsonb_array_elements(v.parcelas) x
            where v.pedido_id = testes.u('p')), 0,
          'parcelas das compensações anulam as parcelas das vendas');
select is((select sum(qtd)::int from vendas where pedido_id = testes.u('p') and movimenta_stock), 4,
          'regra 3: quantidades que movimentam stock não mudam com o estorno (4 unidades vendidas)');
select is((select (select count(*) from estoque_diario) + (select count(*) from estoque_longo_prazo))::text,
          testes.v('stock_antes'), 'regra 3: o estorno não cria movimentos de stock');

-- ---------------------------------------------------------------------------
-- 5. Permissões do organograma
-- ---------------------------------------------------------------------------
select results_eq($$select chave from permissoes where chave in ('pedidos.gerir','entregas.registar') order by chave$$,
                  $$values ('entregas.registar'::text), ('pedidos.gerir'::text)$$,
                  'pedidos.gerir e entregas.registar estão no catálogo de permissões');
select is((select count(*)::int from permissoes), 17, 'catálogo com as 10 permissões da secção 4.12, as 6 das tabelas base e pacotes.gerir');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'public' and table_name = 'permissoes'
              and column_name in ('id','dispositivo_id','criado_em','atualizado_em','sincronizado_em','deletado_em')), 6,
          'catálogo com os 6 campos de sincronização');

select * from finish();
rollback;
