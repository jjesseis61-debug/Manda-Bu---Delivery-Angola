-- Finanças, Fase 1 (fecho) e Fase 2: o gerente vê o acerto da sua cozinha, aviso de segunda (N45),
-- foto do comprovativo nos pagamentos, número da fatura de cada venda, compensações das reclamações
-- (a cargo de quem e no acerto) e contas a receber das empresas.
begin;
\ir _helpers.psql
select plan(31);

select testes.def('cz', cozinha_padrao());
insert into cozinhas (nome, responsavel) values ('Cozinha Dois', 'Bia');
select testes.def('cz2', (select id from cozinhas where nome = 'Cozinha Dois'));
update cozinhas set comissao_percent = 10 where id in (testes.u('cz'), testes.u('cz2'));
select testes.def('ana', testes.cliente('Ana Fatura'));
select testes.def('fin', testes.funcionario('Financeira', array['financas.conferir']));
select testes.def('gerente', testes.funcionario('Gerente Um', array['relatorios.exportar', 'pedidos.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('cz'));
select testes.def('rec', testes.funcionario('Reclamações', array['pedidos.gerir', 'clientes.gerir']));

-- Uma venda em cada cozinha, entregue esta semana
select testes.def('p1', testes.pedido(testes.u('ana')));
select testes.def('p2', testes.pedido(testes.u('ana')));
update pedidos set cozinha_id = testes.u('cz2') where id = testes.u('p2');
select testes.pagar(testes.u('p1'));
select testes.pagar(testes.u('p2'));

-- ---------------------------------------------------------------- gerente vê só a sua cozinha
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('g_semana', acertos_semana(current_date)::text);
select testes.def('g_fechar', testes.erro(format($$select fechar_acerto(%L, %L)$$, testes.v('cz'), current_date - 7)));
reset role; select testes.sair();
select is(jsonb_array_length(testes.v('g_semana')::jsonb -> 'cozinhas'), 1, 'o gerente vê só a sua cozinha');
select is(testes.v('g_semana')::jsonb -> 'cozinhas' -> 0 ->> 'cozinha_id', testes.v('cz'), '…a cozinha dele');
select is((testes.v('g_semana')::jsonb ->> 'pode_gerir')::boolean, false, 'o gerente não pode fechar nem pagar');
select matches(testes.v('g_fechar'), '^42501', 'o gerente não fecha acertos');

select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('f_semana', acertos_semana(current_date)::text);
reset role; select testes.sair();
select is(jsonb_array_length(testes.v('f_semana')::jsonb -> 'cozinhas'), 2, 'finanças vê todas as cozinhas');
select is((select (c ->> 'sem_fatura')::int from jsonb_array_elements(testes.v('f_semana')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')), 1, 'cada cozinha mostra as vendas da semana sem fatura');

-- ---------------------------------------------------------------- faturas das vendas
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('sf1', jsonb_array_length(vendas_sem_fatura(30))::text);
select registar_fatura_pedido(testes.u('p1'), ' ft  2026/1 ');
select testes.def('e_rep', testes.erro(format($$select registar_fatura_pedido(%L, 'FT 2026/1', 'plataforma')$$, testes.v('p2'))));
select registar_fatura_pedido(testes.u('p2'), 'FT 2026/1', 'cozinha');
select testes.def('sf2', jsonb_array_length(vendas_sem_fatura(30))::text);
reset role; select testes.sair();
select is(testes.v('sf1'), '2', 'duas vendas sem fatura');
select results_eq(format($$select numero, emitida_por from faturas_pedidos where pedido_id = %L$$, testes.u('p1')),
                  $$values ('FT 2026/1'::text, 'plataforma'::text)$$, 'número arrumado; emissor por defeito: a plataforma');
select matches(testes.v('e_rep'), 'numero_repetido', 'o mesmo número não se repete no mesmo emissor');
select is((select emitida_por from faturas_pedidos where pedido_id = testes.u('p2')), 'cozinha',
          'a mesma numeração pode existir na fatura emitida pela cozinha');
select is(testes.v('sf2'), '0', 'depois de registar, nada sem fatura');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_cli', testes.erro(format($$select registar_fatura_pedido(%L, 'X1')$$, testes.v('p1'))));
reset role; select testes.sair();
select matches(testes.v('e_cli'), '^42501', 'o cliente não regista faturas');

-- ---------------------------------------------------------------- compensações
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('r1', fazer_reclamacao(testes.u('p1'), 'A comida veio fria e com pouca quantidade'));
reset role; select testes.sair();
select testes.entrar_funcionario(testes.u('rec'));
set local role authenticated;
select decidir_reclamacao(testes.u('r1'), true, 'Tens razão, devolvemos 800 Kz.', 'qualidade', 'reembolso_parcial', 800);
reset role; select testes.sair();
select results_eq(format($$select valor, a_cargo, estado from compensacoes where reclamacao_id = %L$$, testes.u('r1')),
                  $$values (800, 'cozinha'::text, 'por_pagar'::text)$$,
                  'a decisão com valor cria a compensação; falha de qualidade fica a cargo da cozinha');
select testes.def('comp', (select id from compensacoes where reclamacao_id = testes.u('r1')));
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('cl', compensacoes_lista('por_pagar')::text);
select testes.def('e_ref', testes.erro(format($$select pagar_compensacao(%L, 'Unitel Money')$$, testes.v('comp'))));
select pagar_compensacao(testes.u('comp'), 'Unitel Money', 'UM-77881');
select testes.def('e_cargo', testes.erro(format($$select definir_cargo_compensacao(%L, 'plataforma')$$, testes.v('comp'))));
select testes.def('f_semana2', acertos_semana(current_date)::text);
reset role; select testes.sair();
select is(jsonb_array_length(testes.v('cl')::jsonb), 1, 'a compensação aparece por pagar');
select matches(testes.v('e_ref'), 'referencia_obrigatoria', 'pagamento electrónico sem referência é recusado');
select is((select estado from compensacoes where id = testes.u('comp')), 'paga', 'compensação paga');
select matches(testes.v('e_cargo'), 'compensacao_ja_paga', 'depois de paga já não se muda o cargo');
select is((select (c -> 'totais' ->> 'compensacoes')::int from jsonb_array_elements(testes.v('f_semana2')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')), 800, 'a compensação a cargo da cozinha entra no acerto dela');
select is((select (c -> 'totais' ->> 'saldo')::int from jsonb_array_elements(testes.v('f_semana2')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')),
          (select (c -> 'totais' ->> 'saldo')::int + 800 from jsonb_array_elements(testes.v('f_semana')::jsonb -> 'cozinhas') c
            where c ->> 'cozinha_id' = testes.v('cz')), '…e soma ao que a cozinha deve');

-- ---------------------------------------------------------------- foto do comprovativo de um acerto
-- (acerto de uma semana passada com uma venda de 3.000 + entrega)
select testes.def('p3', testes.pedido(testes.u('ana')));
select testes.pagar(testes.u('p3'));
alter table pedidos disable trigger user;
update pedidos set entregue_em = (semana_de(current_date) - 5 + time '12:00') at time zone 'Africa/Luanda' where id = testes.u('p3');
alter table pedidos enable trigger user;
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('ac', fechar_acerto(testes.u('cz'), semana_de(current_date) - 7));
select testes.def('e_foto_mal', testes.erro($$insert into storage.objects (bucket_id, name, owner) values ('comprovativos', 'acertos/x/a.jpg', auth.uid())$$));
select testes.def('e_foto', testes.erro(format($$insert into storage.objects (bucket_id, name, owner) values ('comprovativos', 'acertos/%s/trf.jpg', auth.uid())$$, testes.v('ac'))));
select testes.def('e_comp_alheio', testes.erro(format($$select registar_pagamento_acerto(%L, 1, 'Dinheiro', null, null, 'acertos/%s/nada.jpg')$$, testes.v('ac'), testes.v('ac'))));
select testes.def('pg', registar_pagamento_acerto(testes.u('ac'), 100, 'Transferência', 'TRF-9', null, 'acertos/' || testes.v('ac') || '/trf.jpg')::text);
reset role; select testes.sair();
select matches(testes.v('e_foto_mal'), '^42501', 'foto fora do caminho de um acerto é recusada');
select is(testes.v('e_foto'), 'sem_erro', 'finanças envia a foto do comprovativo do acerto');
select matches(testes.v('e_comp_alheio'), 'comprovativo_invalido', 'só aceita uma foto que existe no acerto');
select is((select comprovativo from acertos_pagamentos where acerto_id = testes.u('ac')), 'acertos/' || testes.v('ac') || '/trf.jpg',
          'o pagamento guarda a foto do comprovativo');

-- ---------------------------------------------------------------- aviso de segunda (N45)
select testes.def('p4', testes.pedido(testes.u('ana')));
update pedidos set cozinha_id = testes.u('cz2') where id = testes.u('p4');
select testes.pagar(testes.u('p4'));
alter table pedidos disable trigger user;
update pedidos set entregue_em = (semana_de(current_date) - 5 + time '12:00') at time zone 'Africa/Luanda' where id = testes.u('p4');
alter table pedidos enable trigger user;
select is(job_acertos_semana(), 1, 'segunda: 1 cozinha por fechar na semana passada (a outra já fechou)');
select ok(exists (select 1 from notificacoes_fila where funcionario_id = testes.u('fin') and codigo = 'N45'), 'N45 chega a quem trata das finanças');
select alike((texto_notificacao('N45', (select dados from notificacoes_fila where codigo = 'N45' limit 1))).corpo,
            '%1 cozinha(s) por fechar%', 'texto do aviso');

-- ---------------------------------------------------------------- contas a receber das empresas
insert into empresas (nome, limite_refeicao) values ('Sonangol Teste', 3000);
select testes.def('emp', (select id from empresas where nome = 'Sonangol Teste'));
select testes.def('p5', testes.pedido(testes.u('ana')));
alter table pedidos disable trigger user;
update pedidos set empresa_id = testes.u('emp'), valor_empresa = 3000, estado = 'entregue_pago',
       entregue_em = (date_trunc('month', current_date) - interval '10 days') where id = testes.u('p5');
alter table pedidos enable trigger user;
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('ce', contas_empresas((date_trunc('month', current_date) - interval '1 month')::date)::text);
select testes.def('e_venc', testes.erro(format($$select emitir_fatura_empresa(%L, %L, 'FT 2026/90', %L)$$, testes.v('emp'),
          (date_trunc('month', current_date) - interval '1 month')::date, (date_trunc('month', current_date) - interval '20 days')::date)));
select testes.def('fe', emitir_fatura_empresa(testes.u('emp'), (date_trunc('month', current_date) - interval '1 month')::date,
          'ft 2026/90', current_date - 1));
select testes.def('ce2', contas_empresas((date_trunc('month', current_date) - interval '1 month')::date)::text);
select pagar_fatura_empresa(testes.u('fe'), 'Transferência', 'TRF-EMP-1');
reset role; select testes.sair();
select is((testes.v('ce')::jsonb -> 'empresas' -> 0 ->> 'estado'), 'por_faturar', 'a empresa aparece por faturar com o valor do mês');
select is((testes.v('ce')::jsonb -> 'empresas' -> 0 ->> 'valor')::int, 3000, '…3.000 Kz');
select matches(testes.v('e_venc'), 'vencimento_invalido', 'o vencimento não pode ser antes do fim do mês');
select is((testes.v('ce2')::jsonb -> 'empresas' -> 0 ->> 'em_atraso')::boolean, true, 'fatura vencida e por pagar: em atraso');
select is((select estado from faturas_empresa where id = testes.u('fe')), 'paga', 'pagamento registado');

select * from finish();
rollback;
