-- Secção 13 · Pagamentos (testes 22 a 25)
begin;
\ir _helpers.psql
select plan(22);

select testes.funcionalidade('indicacao', true);
select testes.def('paula', testes.cliente('Paula Indicadora'));
-- 30 ganhos de 1.000 Kz confirmados em minutos sucessivos (saldo 30.000 Kz)
select testes.ganhos(testes.u('paula'), 30, 1000, now() - interval '2 hours');

select testes.entrar(testes.u('paula'));
select is((select saldo_disponivel from saldo_indicacao where indicador_id = testes.u('paula')), 30000,
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
select testes.def('lote', pedir_levantamento(25000, 'multicaixa_express', '+244 923 111 222'));
select results_eq(
  format($$select parcela, total_parcelas, valor, estado, numero_destino
             from pagamentos_indicacao where lote_id = %L order by parcela$$, testes.u('lote')),
  $$values (1, 2, 12500, 'pedido'::text, '923111222'::text), (2, 2, 12500, 'pedido'::text, '923111222'::text)$$,
  '24. 25.000 Kz -> 2 parcelas de 12.500 Kz com o mesmo lote_id');
select is((select saldo_disponivel from saldo_indicacao where indicador_id = testes.u('paula')), 5000,
          'pagamentos em curso descontam no saldo');
select throws_ok($$select pedir_levantamento(6000, 'unitel_money', '923111222')$$,
                 'P0001', 'saldo_insuficiente', 'saldo já comprometido não se levanta duas vezes');

-- Levantamento até ao limite de parcelamento -> 1 parcela
select testes.def('lote_simples', pedir_levantamento(2000, 'unitel_money', '923111222'));
select is((select count(*)::int from pagamentos_indicacao where lote_id = testes.u('lote_simples')), 1,
          'levantamento abaixo de 20.000 Kz -> 1 parcela');
select testes.sair();

-- 25. Marcar pago sem referência -> recusado; com referência -> ganhos mais antigos passam a pago
select testes.def('parcela1', id) from pagamentos_indicacao where lote_id = testes.u('lote') and parcela = 1;
select testes.def('tesoureira', testes.funcionario('Tesoureira', array['indicacoes.aprovar_pagamentos']));

select testes.entrar(testes.u('paula'));
select throws_ok(format($$select marcar_pago(%L, 'REF-1')$$, testes.u('parcela1')), '42501', 'sem_permissao',
                 'cliente não pode marcar pagamentos como pagos');

select testes.entrar_funcionario(testes.u('tesoureira'));
select throws_ok(format($$select marcar_pago(%L, '')$$, testes.u('parcela1')), 'P0001', 'referencia_obrigatoria',
                 '25. marcar pago sem referência -> recusado');
select throws_ok(format($$select marcar_pago(%L, null)$$, testes.u('parcela1')), 'P0001', 'referencia_obrigatoria',
                 '25. marcar pago com referência nula -> recusado');
select lives_ok(format($$select aprovar_levantamento(%L)$$, testes.u('parcela1')), 'aprovar levantamento');
select lives_ok(format($$select marcar_pago(%L, 'MCX-778899')$$, testes.u('parcela1')),
                '25. marcar pago com referência');
select results_eq(format($$select estado, referencia from pagamentos_indicacao where id = %L$$, testes.u('parcela1')),
                  $$values ('pago'::text, 'MCX-778899'::text)$$, '25. parcela paga com referência');
select is((select count(*)::int from ganhos_indicacao where indicador_id = testes.u('paula') and estado = 'pago'), 12,
          '25. ganhos cobertos pelo pagamento (12 x 1.000 <= 12.500) passam a pago');
select ok((select max(confirmado_em) from ganhos_indicacao where indicador_id = testes.u('paula') and estado = 'pago')
        < (select min(confirmado_em) from ganhos_indicacao where indicador_id = testes.u('paula') and estado = 'confirmado'),
          '25. são os ganhos mais antigos que passam a pago');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('paula') and codigo = 'N8'), 1,
          'N8 enfileirada');
select ok(exists (select 1 from auditoria where acao = 'levantamento_pago' and ref_id = testes.u('parcela1')),
          'pagamento auditado');
select testes.sair();

-- Crédito em refeições: imediato; volta ao saldo se o pedido for cancelado
select testes.def('ped', testes.pedido(testes.u('paula')));
select testes.entrar(testes.u('paula'));
select is(usar_credito(testes.u('ped'), 1000), 1000, 'crédito aplicado ao pedido');
select is((select saldo_disponivel from saldo_indicacao where indicador_id = testes.u('paula')), 2000,
          'crédito usado desconta imediatamente no saldo');
select lives_ok(format($$select cancelar_pedido(%L, 'Mudei de ideias')$$, testes.u('ped')),
                'cliente cancela o pedido pendente');
select is((select saldo_disponivel from saldo_indicacao where indicador_id = testes.u('paula')), 3000,
          'pedido cancelado -> crédito volta ao saldo');
select testes.sair();

select * from finish();
rollback;
