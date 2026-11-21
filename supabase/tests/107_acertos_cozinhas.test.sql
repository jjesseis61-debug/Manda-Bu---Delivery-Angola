-- Acerto semanal com as cozinhas: a cozinha fica com o dinheiro, a plataforma fica com a taxa de
-- entrega e a comissão, e paga à cozinha o Convida (na parte dela), os pacotes e a parte da empresa.
begin;
\ir _helpers.psql
select plan(24);

-- Cozinha com 10% de comissão e Convida 100% a cargo da plataforma
select testes.def('cz', cozinha_padrao());
update cozinhas set comissao_percent = 10, convida_cozinha_percent = 0 where id = testes.u('cz');
select testes.def('ana', testes.cliente('Ana Acerto'));
select testes.def('semana', (semana_de((now() at time zone 'Africa/Luanda')::date) - 7)::text);  -- semana passada

-- Dois pedidos entregues na semana passada:
--  P1: comida 8.000, entrega 2.000, desconto convite 1.000  → cozinha deve 2.000 + 800 = 2.800; plataforma deve 1.000 → saldo 1.800
--  P2: comida 5.000, entrega 1.000, pacote 5.000 (pago à plataforma) → cozinha deve 1.000 + 500 = 1.500; plataforma deve 5.000 → saldo −3.500
select testes.def('p1', testes.pedido(testes.u('ana')));
select testes.def('p2', testes.pedido(testes.u('ana')));
-- Os triggers recalculam valores à inserção; fixamos os valores do cenário e a entrega na semana passada
alter table pedidos disable trigger user;
update pedidos set cozinha_id = testes.u('cz'), subtotal = 8000, taxa_entrega = 2000, desconto_indicacao = 1000, credito_indicacao_usado = 0, pago_pacote = 0,
       valor_empresa = 0, estado = 'entregue_pago', entregue_em = (testes.v('semana')::date + 2 + time '13:00') at time zone 'Africa/Luanda'
 where id = testes.u('p1');
update pedidos set cozinha_id = testes.u('cz'), subtotal = 5000, taxa_entrega = 1000, desconto_indicacao = 0, credito_indicacao_usado = 0, pago_pacote = 5000,
       valor_empresa = 0, estado = 'entregue_pago', entregue_em = (testes.v('semana')::date + 4 + time '20:00') at time zone 'Africa/Luanda'
 where id = testes.u('p2');
alter table pedidos enable trigger user;

select testes.def('fin', testes.funcionario('Financeira', array['financas.conferir', 'financas.acertos', 'financas.faturas', 'financas.compensacoes', 'financas.empresas', 'financas.estafetas', 'financas.servico_entregas', 'financas.resultados', 'financas.obrigacoes']));
select testes.def('outro', testes.funcionario('Sem finanças', array['pedidos.gerir']));

-- Sem permissão
select testes.entrar_funcionario(testes.u('outro'));
set local role authenticated;
select testes.def('e_ver', testes.erro(format($$select acertos_semana(%L)$$, testes.v('semana'))));
select testes.def('e_fechar', testes.erro(format($$select fechar_acerto(%L, %L)$$, testes.v('cz'), testes.v('semana'))));
reset role; select testes.sair();
select matches(testes.v('e_ver'), '^42501', 'sem financas.acertos não vê os acertos');
select matches(testes.v('e_fechar'), '^42501', 'sem financas.acertos não fecha acertos');

-- Pré-visualização e fecho
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('previa', acertos_semana(testes.v('semana')::date)::text);
select testes.def('e_em_curso', testes.erro(format($$select fechar_acerto(%L, %L)$$, testes.v('cz'), semana_de(current_date))));
select testes.def('acerto', fechar_acerto(testes.u('cz'), testes.v('semana')::date));
select testes.def('acerto2', fechar_acerto(testes.u('cz'), testes.v('semana')::date));
reset role; select testes.sair();

select is((select (c -> 'totais' ->> 'saldo')::int from jsonb_array_elements(testes.v('previa')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')), -1700, 'pré-visualização: 1.800 − 3.500 = −1.700 (a plataforma paga)');
select is((select c ->> 'estado' from jsonb_array_elements(testes.v('previa')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')), 'aberto', 'antes de fechar a semana está «aberto»');
select matches(testes.v('e_em_curso'), 'semana_em_curso', 'a semana em curso não se fecha');
select is(testes.v('acerto2'), testes.v('acerto'), 'fechar outra vez devolve o mesmo acerto (sem duplicar)');
select results_eq(format($$select pedidos, vendas, taxas_entrega, comissao, convida_plataforma, pago_pacote, deve_cozinha, deve_plataforma, saldo, estado
                            from acertos_cozinha where id = %L$$, testes.u('acerto')),
                  $$values (2, 13000, 3000, 1300, 1000, 5000, 4300, 6000, -1700, 'fechado'::text)$$,
                  'totais: entregas 3.000 + comissão 1.300 = 4.300; Convida 1.000 + pacote 5.000 = 6.000; saldo −1.700');
select is((select count(*)::int from acertos_linhas where acerto_id = testes.u('acerto')), 2, 'uma linha por pedido');
select is((select saldo from acertos_linhas where pedido_id = testes.u('p1')), 1800, 'P1: 2.000 + 800 − 1.000 = 1.800');

-- Pagamento (a plataforma paga à cozinha 1.700) em duas vezes
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('e_ref', testes.erro(format($$select registar_pagamento_acerto(%L, 700, 'Transferência')$$, testes.v('acerto'))));
select testes.def('e_demais', testes.erro(format($$select registar_pagamento_acerto(%L, 5000, 'Dinheiro')$$, testes.v('acerto'))));
select testes.def('pg1', registar_pagamento_acerto(testes.u('acerto'), 700, 'Dinheiro')::text);
select testes.def('pg2', registar_pagamento_acerto(testes.u('acerto'), 1000, 'Transferência', 'TRF-2026-0042')::text);
select testes.def('e_pago', testes.erro(format($$select registar_pagamento_acerto(%L, 1, 'Dinheiro')$$, testes.v('acerto'))));
select definir_fatura_acerto(testes.u('acerto'), 'FT 2026/118');
select testes.def('cc', conta_corrente_cozinha(testes.u('cz'))::text);
reset role; select testes.sair();
select matches(testes.v('e_ref'), 'referencia_obrigatoria', 'transferência sem referência é recusada');
select matches(testes.v('e_demais'), 'valor_invalido', 'não se paga mais do que o saldo');
select is(testes.v('pg1')::jsonb ->> 'falta', '1000', '1.º pagamento: faltam 1.000');
select is(testes.v('pg2')::jsonb ->> 'estado', 'pago', '2.º pagamento cobre o saldo: «pago»');
select matches(testes.v('e_pago'), 'acerto_ja_pago', 'acerto pago não aceita mais pagamentos');
select is((select quem_paga from acertos_pagamentos where acerto_id = testes.u('acerto') limit 1), 'plataforma', 'saldo negativo: quem paga é a plataforma');
select is((select numero_fatura from acertos_cozinha where id = testes.u('acerto')), 'FT 2026/118', 'número da fatura guardado');
select is((testes.v('cc')::jsonb ->> 'em_aberto')::int, 0, 'conta-corrente: nada em aberto');

-- Estorno depois do fecho: entra ao contrário no acerto seguinte; a semana fechada não muda
alter table pedidos disable trigger user;
update pedidos set estado = 'estornado' where id = testes.u('p1');
alter table pedidos enable trigger user;
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('previa2', acertos_semana(testes.v('semana')::date + 7)::text);
reset role; select testes.sair();
select is((select saldo from acertos_cozinha where id = testes.u('acerto')), -1700, 'a semana fechada não muda com o estorno');
select is((select (c -> 'totais' ->> 'saldo')::int from jsonb_array_elements(testes.v('previa2')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')), -1800, 'o estorno do P1 entra na semana seguinte ao contrário (−1.800)');
select is((select (c -> 'totais' ->> 'pedidos')::int from jsonb_array_elements(testes.v('previa2')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')), 0, 'o estorno não conta como pedido novo');

-- Convida metade a cargo da cozinha: a plataforma só devolve metade do desconto
update cozinhas set convida_cozinha_percent = 50 where id = testes.u('cz');
select is((acerto_valores_pedido((select p from pedidos p where id = testes.u('p1')), 1) ->> 'convida_plataforma')::int, 500,
          'Convida 50% a cargo da cozinha: a plataforma devolve 500 dos 1.000');

-- Ninguém de fora lê as tabelas
set local role authenticated;
select testes.def('e_tab', testes.erro('select count(*) from acertos_cozinha'));
reset role;
select matches(testes.v('e_tab'), '^42501', 'as tabelas dos acertos só se lêem pelas funções');
select ok(not has_function_privilege('anon', 'acertos_semana(date)', 'execute'), 'o visitante não chama os acertos');
select ok(not has_function_privilege('authenticated', 'acerto_movimentos(uuid, date)', 'execute'), 'as funções internas não estão expostas');

select * from finish();
rollback;
