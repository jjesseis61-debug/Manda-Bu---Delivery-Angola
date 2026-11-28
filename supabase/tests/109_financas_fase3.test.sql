-- Finanças, Fase 3: estafetas (salário, dia, entrega), serviço de entregas contratado (por entrega
-- e mensal, pelas zonas que serve), resultados do mês e obrigações. Contas feitas à mão.
begin;
\ir _helpers.psql
select plan(24);

select testes.def('cz', cozinha_padrao());
update cozinhas set comissao_percent = 10, convida_cozinha_percent = 0 where id = testes.u('cz');
select testes.def('mes', (date_trunc('month', current_date) - interval '1 month')::date::text);  -- mês passado
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Própria', 'Própria', 2000, 'Fixo') returning id) select testes.def('za', id) from z;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Longe', 'Terceirizada', 2000, 'Fixo') returning id) select testes.def('zb', id) from z;
select testes.def('pa', testes.ponto('residencial', null, null, testes.u('za')));
select testes.def('pb', testes.ponto('residencial', null, null, testes.u('zb')));
select testes.def('ana', testes.cliente('Ana Resultados'));
select testes.def('carlos', testes.funcionario('Carlos Estafeta', array['entregas.registar']));
select testes.def('fin', testes.funcionario('Financeira', array['financas.conferir', 'financas.acertos', 'financas.faturas', 'financas.compensacoes', 'financas.empresas', 'financas.estafetas', 'financas.servico_entregas', 'financas.resultados', 'financas.obrigacoes']));
update funcionarios set criado_em = testes.v('mes')::date where id = testes.u('carlos');  -- contratado no início do mês passado

-- 5 pedidos de 4.000 + entrega 2.000 no mês passado, todos levados pelo Carlos:
--  3 na zona própria em 2 dias diferentes; 2 na zona do serviço contratado (não contam para ele)
create function pg_temp.pedido(p_ponto text, p_dia int) returns uuid language plpgsql as $$
declare v uuid := testes.pedido(testes.u('ana'));
begin
  alter table pedidos disable trigger user;
  update pedidos set ponto_entrega_id = testes.u(p_ponto), cozinha_id = testes.u('cz'), subtotal = 4000, taxa_entrega = 2000,
         desconto_indicacao = 0, credito_indicacao_usado = 0, estado = 'entregue_pago', entregador_id = testes.u('carlos'),
         entregue_em = (testes.v('mes')::date + p_dia + time '12:00') at time zone 'Africa/Luanda'
   where id = v;
  alter table pedidos enable trigger user;
  return v;
end $$;
select pg_temp.pedido('pa', 2), pg_temp.pedido('pa', 2), pg_temp.pedido('pa', 9), pg_temp.pedido('pb', 3), pg_temp.pedido('pb', 4);
insert into custos (categoria, descricao, valor, data) values ('Telefone', 'Saldo dos estafetas', 5000, testes.v('mes')::date + 5);

-- Configuração (valores lançados depois no operador)
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select definir_remuneracao_estafeta(testes.u('carlos'), 50000, 2000, 100);
select testes.def('forn', guardar_fornecedor_entrega(null, 'Motoboy Express', 500, 10000, array[testes.u('zb')]));
select testes.def('e_neg', testes.erro(format($$select definir_remuneracao_estafeta(%L, -1, 0, 0)$$, testes.v('carlos'))));
select testes.def('folha', estafetas_pagamentos(testes.v('mes')::date)::text);
select testes.def('forns', fornecedores_entrega_lista(testes.v('mes')::date)::text);
reset role; select testes.sair();

select is((select fornecedor_entrega_id from zonas where id = testes.u('zb')), testes.u('forn'), 'a zona Longe passa a ser do serviço contratado');
select matches(testes.v('e_neg'), 'valor_invalido', 'valores negativos são recusados');
select results_eq(format($$select (e ->> 'dias_sugeridos')::int, (e ->> 'entregas')::int, (e ->> 'a_pagar')::int
                            from jsonb_array_elements(%L::jsonb -> 'estafetas') e where e ->> 'funcionario_id' = %L$$,
                         testes.v('folha'), testes.v('carlos')),
                  $$values (2, 3, 54300)$$,
                  'Carlos: 2 dias com entregas, 3 entregas (as da zona contratada não contam); 50.000 + 2×2.000 + 3×100 = 54.300');
select results_eq(format($$select (f ->> 'entregas')::int, (f ->> 'a_pagar')::int from jsonb_array_elements(%L::jsonb -> 'fornecedores') f$$,
                         testes.v('forns')),
                  $$values (2, 11000)$$, 'serviço contratado: 10.000 por mês + 2 entregas × 500 = 11.000');

-- Ajuste dos dias e pagamentos
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select definir_dias_estafeta(testes.u('carlos'), testes.v('mes')::date, 3);
select testes.def('folha2', estafetas_pagamentos(testes.v('mes')::date)::text);
select testes.def('e_ref', testes.erro(format($$select pagar_estafeta_mes(%L, %L, 'Transferência')$$, testes.v('carlos'), testes.v('mes'))));
select testes.def('pago', pagar_estafeta_mes(testes.u('carlos'), testes.v('mes')::date, 'Transferência', 'TRF-SAL-11')::text);
select testes.def('e_2x', testes.erro(format($$select pagar_estafeta_mes(%L, %L, 'Dinheiro')$$, testes.v('carlos'), testes.v('mes'))));
select testes.def('e_dias', testes.erro(format($$select definir_dias_estafeta(%L, %L, 1)$$, testes.v('carlos'), testes.v('mes'))));
select definir_remuneracao_estafeta(testes.u('carlos'), 99999, 0, 0);  -- muda depois de pagar: o mês pago não muda
select testes.def('folha3', estafetas_pagamentos(testes.v('mes')::date)::text);
-- Um mês que ainda não acabou não se paga. O próprio mês em curso já se pode pagar nos últimos 5 dias
-- (fecho do mês), por isso o teste usa o mês seguinte, para não falhar no fim de cada mês.
select testes.def('e_atual', testes.erro(format($$select pagar_estafeta_mes(%L, %L, 'Dinheiro')$$, testes.v('carlos'), (current_date + interval '1 month')::date)));
select testes.def('pago_f', pagar_fornecedor_entrega(testes.u('forn'), testes.v('mes')::date, 'Transferência', 'TRF-MOTO-1', 'ft m/7')::text);
select testes.def('res', resultados_mes(testes.v('mes')::date)::text);
select testes.def('obr', obrigacoes_resumo()::text);
reset role; select testes.sair();

select is((select (e ->> 'a_pagar')::int from jsonb_array_elements(testes.v('folha2')::jsonb -> 'estafetas') e
            where e ->> 'funcionario_id' = testes.v('carlos')), 56300, 'com 3 dias trabalhados: 50.000 + 6.000 + 300 = 56.300');
select matches(testes.v('e_ref'), 'referencia_obrigatoria', 'transferência sem referência é recusada');
select is(testes.v('pago'), '56300', 'paga o valor calculado no servidor');
select matches(testes.v('e_2x'), 'mes_ja_pago', 'o mesmo mês não se paga duas vezes');
select matches(testes.v('e_dias'), 'mes_ja_pago', 'depois de pago, os dias não mudam');
select is((select (e ->> 'a_pagar')::int from jsonb_array_elements(testes.v('folha3')::jsonb -> 'estafetas') e
            where e ->> 'funcionario_id' = testes.v('carlos')), 56300, 'mudar o salário depois não altera o mês já pago');
select matches(testes.v('e_atual'), 'mes_em_curso', 'um mês que ainda não acabou não se paga');
select is(testes.v('pago_f'), '11000', 'serviço contratado pago: 11.000');
select is((select numero_fatura from fornecedores_entrega_mes where fornecedor_id = testes.u('forn')), 'FT M/7', 'fatura do serviço guardada');

-- Resultados do mês: receitas 5 × (400 comissão + 2.000 entrega) = 12.000;
-- custos 56.300 + 11.000 + 5.000 despesas gerais = 72.300; resultado −60.300
select is((testes.v('res')::jsonb -> 'receitas' ->> 'comissoes')::int, 2000, 'comissões: 5 × 400 = 2.000');
select is((testes.v('res')::jsonb -> 'receitas' ->> 'taxas_entrega')::int, 10000, 'taxas de entrega: 5 × 2.000 = 10.000');
select is((testes.v('res')::jsonb -> 'receitas' ->> 'total')::int, 12000, 'receitas: 12.000');
select is((testes.v('res')::jsonb -> 'custos' ->> 'estafetas')::int, 56300, 'custo dos estafetas (o pago)');
select is((testes.v('res')::jsonb -> 'custos' ->> 'despesas_gerais')::int, 5000, 'despesas gerais (sem cozinha)');
select is((testes.v('res')::jsonb -> 'custos' ->> 'total')::int, 72300, 'custos: 72.300');
select is((testes.v('res')::jsonb ->> 'resultado')::int, -60300, 'resultado do mês: −60.300');
select is((testes.v('res')::jsonb ->> 'custo_por_entrega')::int, 13460, 'custo das entregas por pedido: 67.300 / 5 = 13.460');
select is((testes.v('obr')::jsonb -> 'a_pagar' ->> 'estafetas_meses_anteriores')::int, 0,
          'obrigações: o mês passado já está pago e antes de ser contratado não há salário');
select is((select a_pagar from folha_estafetas((testes.v('mes')::date - interval '1 month')::date)
            where funcionario_id = testes.u('carlos')), 0, 'no mês antes de entrar na equipa: nada a pagar');

-- Permissões
select testes.entrar_funcionario(testes.u('carlos'));
set local role authenticated;
select testes.def('e_carlos', testes.erro(format($$select estafetas_pagamentos(%L)$$, testes.v('mes'))));
reset role; select testes.sair();
select matches(testes.v('e_carlos'), '^42501', 'o estafeta não vê a folha de pagamentos');

select * from finish();
rollback;
