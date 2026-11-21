-- Permissões de finanças separadas: cada área só abre com a sua permissão; financas.conferir
-- deixa de abrir as outras áreas; o catálogo tem as novas.
begin;
\ir _helpers.psql
select plan(13);

select testes.def('mes', (date_trunc('month', current_date) - interval '1 month')::date::text);
select testes.def('est', testes.funcionario('Só estafetas', array['financas.estafetas']));
select testes.def('conf', testes.funcionario('Só conferência', array['financas.conferir']));
select testes.def('res', testes.funcionario('Só resultados', array['financas.resultados', 'financas.obrigacoes']));

select is((select count(*)::int from permissoes where deletado_em is null and chave in
  ('financas.acertos', 'financas.faturas', 'financas.compensacoes', 'financas.empresas', 'financas.estafetas',
   'financas.servico_entregas', 'financas.resultados', 'financas.obrigacoes')), 8, 'as 8 permissões novas estão no catálogo');

-- Só estafetas
select testes.entrar_funcionario(testes.u('est'));
set local role authenticated;
select testes.def('a1', testes.erro(format($$select estafetas_pagamentos(%L)$$, testes.v('mes'))));
select testes.def('a2', testes.erro(format($$select resultados_mes(%L)$$, testes.v('mes'))));
select testes.def('a3', testes.erro(format($$select acertos_semana(%L)$$, current_date - 7)));
select testes.def('a4', testes.erro(format($$select fornecedores_entrega_lista(%L)$$, testes.v('mes'))));
select testes.def('a5', testes.erro($$select obrigacoes_resumo()$$));
reset role; select testes.sair();
select is(testes.v('a1'), 'sem_erro', 'financas.estafetas abre o pagamento dos estafetas');
select matches(testes.v('a2'), '^42501', 'financas.estafetas não vê os resultados');
select matches(testes.v('a3'), '^42501', 'financas.estafetas não vê os acertos');
select matches(testes.v('a4'), '^42501', 'financas.estafetas não vê o serviço contratado');
select matches(testes.v('a5'), '^42501', 'financas.estafetas não vê as obrigações');

-- Só conferência: já não abre as outras áreas
select testes.entrar_funcionario(testes.u('conf'));
set local role authenticated;
select testes.def('b1', testes.erro(format($$select estafetas_pagamentos(%L)$$, testes.v('mes'))));
select testes.def('b2', testes.erro(format($$select contas_empresas(%L)$$, testes.v('mes'))));
select testes.def('b3', testes.erro($$select compensacoes_lista(null)$$));
reset role; select testes.sair();
select matches(testes.v('b1'), '^42501', 'financas.conferir sozinha não paga estafetas');
select matches(testes.v('b2'), '^42501', 'financas.conferir sozinha não vê as contas das empresas');
select matches(testes.v('b3'), '^42501', 'financas.conferir sozinha não vê as compensações');

-- Resultados e obrigações (só leitura)
select testes.entrar_funcionario(testes.u('res'));
set local role authenticated;
select testes.def('c1', testes.erro(format($$select resultados_mes(%L)$$, testes.v('mes'))));
select testes.def('c2', testes.erro($$select obrigacoes_resumo()$$));
select testes.def('c3', testes.erro(format($$select pagar_estafeta_mes(%L, %L, 'Dinheiro', null)$$, testes.v('est'), testes.v('mes'))));
reset role; select testes.sair();
select is(testes.v('c1'), 'sem_erro', 'financas.resultados abre os resultados');
select is(testes.v('c2'), 'sem_erro', 'financas.obrigacoes abre as obrigações');
select matches(testes.v('c3'), '^42501', 'quem só vê resultados não paga estafetas');

select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('estafetas_pagamentos', 'resultados_mes', 'acertos_semana', 'obrigacoes_resumo')
              and pg_get_functiondef(p.oid) like '%financas.conferir%'), 0, 'as áreas já não pedem financas.conferir');

select * from finish();
rollback;
