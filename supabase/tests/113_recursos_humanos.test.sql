-- Recursos humanos: ficha (só rh.gerir), contratos, folha com INSS e IRT (contas à mão),
-- ajustes, fecho, pagamento (só financas.salarios) e custo do pessoal nos resultados.
begin;
\ir _helpers.psql
select plan(25);

select testes.def('mes', (date_trunc('month', current_date) - interval '1 month')::date::text);
select testes.def('ana', testes.funcionario('Ana Cozinheira', array['vendas.registar']));
select testes.def('bia', testes.funcionario('Bia Meio Mês', array['vendas.registar']));
select testes.def('rui', testes.funcionario('Rui Prestador', array['entregas.registar']));
select testes.def('rh', testes.funcionario('RH', array['rh.gerir', 'rh.salarios']));
select testes.def('fin', testes.funcionario('Tesouraria', array['financas.salarios', 'financas.resultados']));
select testes.def('curioso', testes.funcionario('Curioso', array['financas.estafetas']));

-- IRT (tabela inicial)
select is(irt_calcular(150000), 0, 'IRT: até 150.000 isento');
select is(irt_calcular(200000), 20500, 'IRT: 200.000 → 12.500 + 16% de 50.000');
select is(irt_calcular(600000), 107250, 'IRT: 600.000 → 87.250 + 20% de 100.000');
select is(irt_calcular(12000000), 2842250, 'IRT: 12.000.000 → 2.342.250 + 25% de 2.000.000');

-- Sem permissão de RH não se vê a ficha
select testes.entrar_funcionario(testes.u('curioso'));
set local role authenticated;
select testes.def('e1', testes.erro($$select rh_lista()$$));
select testes.def('e2', testes.erro(format($$select rh_ficha(%L)$$, testes.u('ana'))));
reset role; select testes.sair();
select matches(testes.v('e1'), '^42501', 'sem rh.gerir não vê a equipa');
select matches(testes.v('e2'), '^42501', 'sem rh.gerir não vê os dados pessoais');

-- RH regista ficha, documento, contratos e equipamento
select testes.entrar_funcionario(testes.u('rh'));
set local role authenticated;
select rh_guardar_ficha(testes.u('ana'), jsonb_build_object('nif', '005000111LA041', 'inss_numero', '123456', 'iban', 'ao06 0040 0000 1234',
                                                            'data_admissao', testes.v('mes')));
select testes.def('doc', rh_guardar_documento(jsonb_build_object('funcionario_id', testes.u('ana'), 'tipo', 'declaracao_saude',
                                                                  'validade', current_date + 10))::text);
select testes.def('c_ana', rh_guardar_contrato(jsonb_build_object('funcionario_id', testes.u('ana'), 'tipo', 'indeterminado',
  'funcao', 'Cozinheira', 'inicio', (testes.v('mes')::date - 60), 'salario_base', 200000, 'subsidio_alimentacao', 30000,
  'subsidio_transporte', 40000))::text);
select testes.def('e_pe', testes.erro(format($$select rh_guardar_contrato(jsonb_build_object('funcionario_id', %L, 'tipo', 'termo_certo',
  'inicio', %L, 'fim', %L, 'periodo_experimental_dias', 60, 'salario_base', 100000))$$,
  testes.u('bia'), testes.v('mes'), (testes.v('mes')::date + 180))));
select testes.def('c_bia', rh_guardar_contrato(jsonb_build_object('funcionario_id', testes.u('bia'), 'tipo', 'termo_certo',
  'inicio', (testes.v('mes')::date + 15), 'fim', (testes.v('mes')::date + 200), 'salario_base', 100000))::text);
select rh_guardar_contrato(jsonb_build_object('funcionario_id', testes.u('rui'), 'tipo', 'prestacao_servicos',
  'inicio', testes.v('mes'), 'salario_base', 50000));
select rh_guardar_equipamento(jsonb_build_object('funcionario_id', testes.u('rui'), 'tipo', 'mota', 'matricula', 'ld-12-34-ab'));
select testes.def('ficha', rh_ficha(testes.u('ana'))::text);
select testes.def('lista', rh_lista()::text);
select testes.def('sim', rh_simular_salario(200000, 30000, 40000, 0)::text);
reset role; select testes.sair();

select matches(testes.v('e_pe'), 'periodo_experimental_maximo_30', 'contrato a termo: período experimental até 30 dias');
select is(testes.v('ficha')::jsonb -> 'ficha' ->> 'iban', 'AO06004000001234', 'IBAN guardado sem espaços e em maiúsculas');
select is((testes.v('ficha')::jsonb -> 'contratos' -> 0 ->> 'periodo_experimental_dias')::int, 60, 'contrato sem prazo: 60 dias de experiência por defeito');
select ok((testes.v('ficha')::jsonb -> 'alertas')::text like '%Caduca em breve: declaracao saude%', 'avisa a declaração de saúde a caducar');
select ok((select (x -> 'alertas')::text like '%Sem contrato%' from jsonb_array_elements(testes.v('lista')::jsonb) x
            where x ->> 'funcionario_id' = testes.v('curioso')), 'avisa quem não tem contrato');
select is((select upper(matricula) from rh_equipamentos where funcionario_id = testes.u('rui')), 'LD-12-34-AB', 'mota da empresa registada');
select results_eq($$select (testes.v('sim')::jsonb ->> 'bruto')::int, (testes.v('sim')::jsonb ->> 'inss_trabalhador')::int,
                           (testes.v('sim')::jsonb ->> 'materia_colectavel')::int, (testes.v('sim')::jsonb ->> 'irt')::int,
                           (testes.v('sim')::jsonb ->> 'liquido')::int, (testes.v('sim')::jsonb ->> 'custo_empresa')::int$$,
                  $$values (270000, 8100, 201900, 31592, 230308, 291600)$$,
                  'salário 200.000 + 30.000 alimentação + 40.000 transporte: INSS 8.100, IRT 31.592, líquido 230.308');

-- Folha do mês passado: subsídio de férias e horas extra para a Ana
select testes.entrar_funcionario(testes.u('rh'));
set local role authenticated;
select rh_folha_ajustar(testes.v('mes')::date, testes.u('ana'), 10000, 0, true, false, 'Férias em Agosto');
select testes.def('folha', rh_folha(testes.v('mes')::date)::text);
reset role; select testes.sair();

select is(jsonb_array_length(testes.v('folha')::jsonb -> 'linhas'), 2, 'folha: Ana e Bia (o prestador de serviços fica de fora)');
select is((select (l ->> 'bruto')::int from jsonb_array_elements(testes.v('folha')::jsonb -> 'linhas') l where l ->> 'nome' = 'Ana Cozinheira'),
          380000, 'Ana: 270.000 + 10.000 extra + 100.000 de subsídio de férias');
select is((select (l ->> 'irt')::int from jsonb_array_elements(testes.v('folha')::jsonb -> 'linhas') l where l ->> 'nome' = 'Ana Cozinheira'),
          49250 + round((380000 - 60000 - 11400 - 300000) * 0.19)::int, 'Ana: IRT sobre 380.000 − 60.000 isentos − 11.400 INSS');
select is((select (l ->> 'salario_base')::int from jsonb_array_elements(testes.v('folha')::jsonb -> 'linhas') l where l ->> 'nome' = 'Bia Meio Mês'),
          round(100000 * (extract(day from (testes.v('mes')::date + interval '1 month - 1 day')) - 15) / extract(day from (testes.v('mes')::date + interval '1 month - 1 day')))::int,
          'Bia entrou a meio do mês: salário proporcional aos dias');
select is(testes.v('folha')::jsonb -> 'prestadores' -> 0 ->> 'nome', 'Rui Prestador', 'o prestador aparece à parte');

-- Fechar, pagar (só a tesouraria) e custo nos resultados
select testes.entrar_funcionario(testes.u('rh'));
set local role authenticated;
select testes.def('n', rh_folha_fechar(testes.v('mes')::date)::text);
select testes.def('e_pagar_rh', testes.erro(format($$select rh_folha_pagar(%L, %L, 'Dinheiro', null)$$, testes.v('mes'), testes.u('ana'))));
select testes.def('e_ajustar', testes.erro(format($$select rh_folha_ajustar(%L, %L, 1, 0, false, false, null)$$, testes.v('mes'), testes.u('ana'))));
reset role; select testes.sair();
update rh_contratos set salario_base = 999999 where id = testes.v('c_ana')::uuid;  -- mudança depois de fechar não mexe na folha
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('pago', rh_folha_pagar(testes.v('mes')::date, testes.u('ana'), 'Transferência', 'TRF-777')::text);
select testes.def('e_dup', testes.erro(format($$select rh_folha_pagar(%L, %L, 'Dinheiro', null)$$, testes.v('mes'), testes.u('ana'))));
select testes.def('res', resultados_mes(testes.v('mes')::date)::text);
select testes.def('folha2', rh_folha(testes.v('mes')::date)::text);
reset role; select testes.sair();

select is(testes.v('n'), '2', 'folha fechada com 2 linhas');
select matches(testes.v('e_pagar_rh'), '^42501', 'quem calcula a folha não paga (separação de funções)');
select matches(testes.v('e_ajustar'), 'folha_fechada', 'folha fechada não se ajusta');
select is(testes.v('pago')::int, 380000 - 11400 - (49250 + round((380000 - 60000 - 11400 - 300000) * 0.19)::int), 'paga o líquido da Ana');
select matches(testes.v('e_dup'), 'ja_pago', 'não paga duas vezes');
select is((select (l ->> 'bruto')::int from jsonb_array_elements(testes.v('folha2')::jsonb -> 'linhas') l where l ->> 'nome' = 'Ana Cozinheira'),
          380000, 'folha fechada não muda com o contrato');
select is((testes.v('res')::jsonb -> 'custos' ->> 'pessoal')::int, (testes.v('folha2')::jsonb -> 'totais' ->> 'custo_empresa')::int,
          'custo do pessoal (bruto + INSS da empresa) entra nos resultados');

select * from finish();
rollback;
