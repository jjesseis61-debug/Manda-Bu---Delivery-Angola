-- Secção 13 · Pagamentos (testes 22 a 25)
begin;
\ir _helpers.psql
select plan(22);

select testes.funcionalidade('indicacao', true);
select testes.cliente('Paula Indicadora') as paula \gset
-- 30 ganhos de 1.000 Kz confirmados em minutos sucessivos (saldo 30.000 Kz)
select testes.ganhos(:'paula', 30, 1000, now() - interval '2 hours');

select testes.entrar(:'paula');
select is((select saldo_disponivel from saldo_indicacao where indicador_id = :'paula'), 30000,
          'saldo disponível = ganhos confirmados');

-- 22. Levantamento abaixo do mínimo -> recusado
select throws_ok($$select pedir_levantamento(1500, 'multicaixa_express', '923 111 222')$$,
                 'P0001', 'abaixo_minimo', '22. levantamento abaixo do mínimo -> recusado');

-- 23. Levantamento acima do saldo -> recusado
select throws_ok($$select pedir_levantamento(40000, 'multicaixa_express', '923 111 222')$$,
                 'P0001', 'saldo_insuficiente', '23. levantamento acima do saldo -> recusado');

select throws_ok($$select pedir_levantamento(3000, 'paypal', '923 111 222')$$,
                 'P0001', 'metodo_invalido', 'método de levantamento inválido -> recusado');

-- 24. Levantamento de 25.000 Kz -> 2 parcelas com o mesmo lote
select pedir_levantamento(25000, 'multicaixa_express', '+244 923 111 222') as lote \gset
select results_eq(
  format($$select parcela, total_parcelas, valor, estado, numero_destino
             from pagamentos_indicacao where lote_id = %L order by parcela$$, :'lote'),
  $$values (1, 2, 12500, 'pedido'::text, '923111222'::text), (2, 2, 12500, 'pedido'::text, '923111222'::text)$$,
  '24. 25.000 Kz -> 2 parcelas de 12.500 Kz com o mesmo lote_id');
select is((select saldo_disponivel from saldo_indicacao where indicador_id = :'paula'), 5000,
          'pagamentos em curso descontam no saldo');
select throws_ok($$select pedir_levantamento(6000, 'unitel_money', '923111222')$$,
                 'P0001', 'saldo_insuficiente', 'saldo já comprometido não se levanta duas vezes');

-- Levantamento até ao limite de parcelamento -> 1 parcela
select pedir_levantamento(2000, 'unitel_money', '923111222') as lote_simples \gset
select is((select count(*)::int from pagamentos_indicacao where lote_id = :'lote_simples'), 1,
          'levantamento abaixo de 20.000 Kz -> 1 parcela');
select testes.sair();

-- 25. Marcar pago sem referência -> recusado; com referência -> ganhos mais antigos passam a pago
select id as parcela1 from pagamentos_indicacao where lote_id = :'lote' and parcela = 1 \gset
select testes.funcionario('Tesoureira', array['indicacoes.aprovar_pagamentos']) as tesoureira \gset

select testes.entrar(:'paula');
select throws_ok(format($$select marcar_pago(%L, 'REF-1')$$, :'parcela1'), '42501', 'sem_permissao',
                 'cliente não pode marcar pagamentos como pagos');

select testes.entrar_funcionario(:'tesoureira');
select throws_ok(format($$select marcar_pago(%L, '')$$, :'parcela1'), 'P0001', 'referencia_obrigatoria',
                 '25. marcar pago sem referência -> recusado');
select throws_ok(format($$select marcar_pago(%L, null)$$, :'parcela1'), 'P0001', 'referencia_obrigatoria',
                 '25. marcar pago com referência nula -> recusado');
select lives_ok(format($$select aprovar_levantamento(%L)$$, :'parcela1'), 'aprovar levantamento');
select lives_ok(format($$select marcar_pago(%L, 'MCX-778899')$$, :'parcela1'),
                '25. marcar pago com referência');
select results_eq(format($$select estado, referencia from pagamentos_indicacao where id = %L$$, :'parcela1'),
                  $$values ('pago'::text, 'MCX-778899'::text)$$, '25. parcela paga com referência');
select is((select count(*)::int from ganhos_indicacao where indicador_id = :'paula' and estado = 'pago'), 12,
          '25. ganhos cobertos pelo pagamento (12 x 1.000 <= 12.500) passam a pago');
select ok((select max(confirmado_em) from ganhos_indicacao where indicador_id = :'paula' and estado = 'pago')
        < (select min(confirmado_em) from ganhos_indicacao where indicador_id = :'paula' and estado = 'confirmado'),
          '25. são os ganhos mais antigos que passam a pago');
select is((select count(*)::int from notificacoes_fila where cliente_id = :'paula' and codigo = 'N8'), 1,
          'N8 enfileirada');
select ok(exists (select 1 from auditoria where acao = 'levantamento_pago' and ref_id = :'parcela1'),
          'pagamento auditado');
select testes.sair();

-- Crédito em refeições: imediato; volta ao saldo se o pedido for cancelado
select testes.pedido(:'paula') as ped \gset
select testes.entrar(:'paula');
select is(usar_credito(:'ped', 1000), 1000, 'crédito aplicado ao pedido');
select is((select saldo_disponivel from saldo_indicacao where indicador_id = :'paula'), 2000,
          'crédito usado desconta imediatamente no saldo');
select lives_ok(format($$select cancelar_pedido(%L, 'Mudei de ideias')$$, :'ped'),
                'cliente cancela o pedido pendente');
select is((select saldo_disponivel from saldo_indicacao where indicador_id = :'paula'), 3000,
          'pedido cancelado -> crédito volta ao saldo');
select testes.sair();

select * from finish();
rollback;
