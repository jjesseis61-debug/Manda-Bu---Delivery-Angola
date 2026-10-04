-- Agente investigador financeiro: sinais e abertura dos casos, ferramentas só de leitura (e só do serviço),
-- resultado com aviso N24 (nunca ao próprio), decisão humana e quem vê os casos
begin;
\ir _helpers.psql
select plan(22);

select testes.funcionalidade('agente_investigador', true);
select testes.def('cz', cozinha_padrao());
select testes.def('rui', testes.funcionario('Rui Mateus', array['entregas.registar']));
select testes.def('leo', testes.funcionario('Leo Cardoso', array['entregas.registar']));
select testes.def('joana', testes.funcionario('Joana Finanças', array['financas.conferir']));
select testes.def('marta', testes.funcionario('Marta Finanças', array['financas.conferir']));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('caixa', testes.caixa());

-- Comprovativos do Rui: C1 rejeitado, C2 não confere com a foto, C3 sem entrada no extrato, C4 encontrado.
-- Do Leo: L1 encontrado. A Marta fechou uma caixa com 500 Kz a menos.
create function pg_temp.comp(p_func text, p_ref text, p_valor int, p_estado text default 'conferido', p_ia text default 'confere')
returns uuid language sql as $$
  insert into comprovativos_pagamento (pedido_id, caixa_id, cozinha_id, metodo, valor, referencia, referencia_chave, caminho,
                                       registado_por, estado, ia_estado, ia_valor, nota)
  values (testes.pedido(testes.u('ana')), testes.u('caixa'), testes.u('cz'), 'Multicaixa Express', p_valor, p_ref,
          chave_referencia(p_ref), 'x/1.jpg', testes.u(p_func), p_estado, p_ia,
          case when p_ia = 'diverge' then p_valor - 1000 end, case when p_estado = 'rejeitado' then 'Talão de outro dia' end)
  returning id;
$$;
select testes.def('C1', pg_temp.comp('rui', 'MCX-9001', 3000, 'rejeitado', 'diverge'));
select testes.def('C2', pg_temp.comp('rui', 'MCX-9002', 4000, 'conferido', 'diverge'));
select testes.def('C3', pg_temp.comp('rui', 'MCX-9003', 3500));
select testes.def('C4', pg_temp.comp('rui', 'MCX-9004', 2000));
select testes.def('L1', pg_temp.comp('leo', 'MCX-9005', 2500));
with e as (insert into extratos (conta, periodo_inicio, periodo_fim, estado) values ('BAI', current_date - 5, current_date, 'lido') returning id)
select testes.def('ext', id) from e;
insert into extrato_movimentos (extrato_id, data, valor, referencia, referencia_chave, origem, comprovativo_id) values
  (testes.u('ext'), current_date, 2000, 'MCX-9004', chave_referencia('MCX-9004'), 'ia', testes.u('C4')),
  (testes.u('ext'), current_date, 2500, 'MCX-9005', chave_referencia('MCX-9005'), 'ia', testes.u('L1')),
  (testes.u('ext'), current_date - 1, 3500, 'MCX-9030', chave_referencia('MCX-9030'), 'ia', null);
with c as (insert into caixa (posto, cozinha_id, data, troco_inicial, fechamento)
           values ('Balcão de teste', testes.u('cz'), current_date, 0,
                   jsonb_build_object('esperado', 10000, 'contado', 9500, 'diferenca', -500, 'funcionario_id', testes.v('marta'),
                                      'funcionario_nome', 'Marta Finanças', 'observacao', 'Faltou troco'))
           returning id)
select testes.def('cx_marta', id) from c;

select results_eq(format($$select (s ->> 'rejeitados')::int, (s ->> 'nao_conferem')::int, (s ->> 'sem_extrato')::int,
                                  (s ->> 'valor_sem_extrato')::numeric, (s ->> 'pontuacao')::int
                             from sinais_financeiros(%L, current_date - 5, current_date) s$$, testes.v('rui')),
                  $$values (1, 2, 2, 7500::numeric, 13)$$,
                  'sinais do Rui: 1 rejeitado, 2 não conferem com a foto, 2 sem extrato (o rejeitado não conta duas vezes)');

-- Abrir os casos: só quem confere as finanças; Rui (13 pontos) abre; Marta (2) e Leo (0) não; não repete
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('e_rui', testes.erro('select abrir_investigacoes(current_date - 5, current_date)'));
reset role;
select testes.entrar_funcionario(testes.u('joana'));
set local role authenticated;
select testes.def('abertos', abrir_investigacoes(current_date - 5, current_date));
select testes.def('de_novo', abrir_investigacoes(current_date - 5, current_date));
reset role;
select testes.sair();
select testes.def('caso', (select id from casos_investigacao where funcionario_id = testes.u('rui')));
select ok(testes.v('e_rui') like '42501:%' and testes.v('abertos') = '1' and testes.v('de_novo') = '0',
          'só quem confere abre casos; um caso para o Rui; o mesmo período não repete');
select ok(not exists (select 1 from casos_investigacao where funcionario_id in (testes.u('marta'), testes.u('leo'))),
          'abaixo dos pontos mínimos não se abre caso (caixa com 500 Kz a menos = 2 pontos)');

-- Ferramentas do agente
select testes.def('reserva', reservar_caso());
select ok(testes.v('reserva')::jsonb ->> 'funcionario' = 'Rui Mateus'
          and (testes.v('reserva')::jsonb -> 'sinais' ->> 'pontuacao')::int = 13, 'reserva o caso com quem e os sinais');
select ok(reservar_caso() is null, 'um caso a ser investigado não é reservado duas vezes');
select is((select count(*)::int from jsonb_array_elements(agente_comprovativos(testes.u('rui'), current_date - 5, current_date))), 4,
          'comprovativos do Rui no período');
select ok((select bool_and(not (e ->> 'encontrado_no_extrato')::boolean) and bool_and((e ->> 'periodo_com_extrato')::boolean)
             from jsonb_array_elements(agente_comprovativos(testes.u('rui'), current_date - 5, current_date)) e
            where e ->> 'referencia' = 'MCX-9003'), 'mostra que o MCX-9003 está num período com extrato e não foi encontrado');
select is((select e ->> 'referencia' from jsonb_array_elements(agente_entradas_parecidas(3500, current_date, 3)) e),
          'MCX-9030', 'há uma entrada de 3.500 Kz sem comprovativo no dia anterior (talvez referência mal escrita)');
select is((select count(*)::int from jsonb_array_elements(agente_referencia('mcx 9003') -> 'comprovativos')), 1,
          'procura a referência noutros comprovativos (normalizada)');
select ok(agente_historico_pedido((select pedido_id from comprovativos_pagamento where id = testes.u('C1')))::text not like '%Ana%',
          'o histórico do pedido vai sem o nome do cliente');
select ok((select (e -> 'diferenca')::numeric = -500 from jsonb_array_elements(agente_caixas(testes.u('marta'), current_date - 5, current_date)) e),
          'caixas fechadas pela pessoa, com a diferença');
select ok((select count(*) >= 3 from jsonb_array_elements(agente_equipa(current_date - 5, current_date))),
          'compara com a equipa no mesmo período');
select ok(not has_function_privilege('authenticated', 'agente_comprovativos(uuid, date, date)', 'execute')
          and not has_function_privilege('authenticated', 'reservar_caso()', 'execute')
          and not has_function_privilege('authenticated', 'registar_investigacao(uuid, text, jsonb, jsonb, text)', 'execute'),
          'as ferramentas do agente só o serviço as chama');

-- Resultado: risco alto -> N24 a quem confere (a Joana e a Marta), auditoria como "Agente Claude"
select is(registar_investigacao(testes.u('caso'), 'investigado',
            '{"risco": "alto", "resumo": "Três pagamentos de 3.000 a 4.000 Kz sem confirmação.", "factos": [{"texto": "MCX-9003 sem entrada", "pedido_id": null}],
              "explicacoes_possiveis": ["referência mal escrita (há 3.500 Kz com MCX-9030)"], "recomendacao": "Pedir os talões ao Rui",
              "perguntas_ao_funcionario": ["De onde veio o talão do MCX-9001?"]}'::jsonb,
            '[{"ferramenta": "agente_comprovativos"}, {"ferramenta": "agente_entradas_parecidas"}]'::jsonb), 'investigado',
          'regista o dossiê do agente');
select results_eq(format($$select estado, risco, conclusao ->> 'recomendacao', jsonb_array_length(passos) from casos_investigacao where id = %L$$, testes.v('caso')),
                  $$values ('investigado'::text, 'alto'::text, 'Pedir os talões ao Rui'::text, 2)$$, 'guarda o risco, a conclusão e os passos');
select is((select array_agg(funcionario_id order by funcionario_id) from notificacoes_fila where codigo = 'N24'),
          (select array_agg(x order by x) from unnest(array[testes.u('joana'), testes.u('marta')]) x),
          'N24 a quem confere as finanças');
select ok((select bool_and((texto_notificacao(codigo, dados)).corpo like 'Pagamentos a confirmar de %: há diferenças por explicar. Abre a Conferência para ver os factos e decidir.'
                           and (texto_notificacao(codigo, dados)).corpo not ilike '%risco%')
             from notificacoes_fila where codigo = 'N24'),
          'N24 diz o que há a confirmar, sem rotular a pessoa com "risco"');
select ok(exists (select 1 from auditoria where acao = 'caso_investigado' and funcionario_nome = 'Agente Claude' and ref_id = testes.u('caso')),
          'fica na auditoria como "Agente Claude"');

-- Quem vê e quem decide: o próprio nunca
update casos_investigacao set funcionario_id = testes.u('marta') where id = testes.u('caso');
select testes.entrar_funcionario(testes.u('marta'));
set local role authenticated;
select testes.def('vistos_marta', (select count(*) from casos_investigacao));
select testes.def('lista_marta', jsonb_array_length(casos_investigacao_lista()));
select testes.def('e_propria', testes.erro(format($$select decidir_caso(%L, 'sem_problema', 'Está tudo certo')$$, testes.v('caso'))));
reset role;
update casos_investigacao set funcionario_id = testes.u('rui') where id = testes.u('caso');
select testes.entrar_funcionario(testes.u('joana'));
set local role authenticated;
select testes.def('vistos_joana', (select count(*) from casos_investigacao));
select testes.def('e_nota', testes.erro(format($$select decidir_caso(%L, 'erro_operacional', 'ok')$$, testes.v('caso'))));
select decidir_caso(testes.u('caso'), 'erro_operacional', 'O MCX-9003 era o MCX-9030: referência mal escrita. Rever os outros dois.');
select testes.def('e_duas', testes.erro(format($$select decidir_caso(%L, 'sem_problema', 'Outra decisão')$$, testes.v('caso'))));
reset role;
select testes.sair();
select ok(testes.v('vistos_marta') = '0' and testes.v('lista_marta') = '0' and testes.v('e_propria') like '42501:%',
          'quem é investigado não vê nem decide o seu caso');
select ok(testes.v('vistos_joana') = '1' and testes.v('e_nota') = 'P0001:nota_obrigatoria' and testes.v('e_duas') = 'P0001:caso_decidido',
          'quem confere vê, decide com uma nota e uma vez só');
select results_eq(format($$select decisao, decidido_por from casos_investigacao where id = %L$$, testes.v('caso')),
                  format($$values ('erro_operacional'::text, %L::uuid)$$, testes.v('joana')), 'a decisão fica guardada');

-- Interruptor desligado: o job não abre casos e o agente não reserva
select testes.funcionalidade('agente_investigador', false);
select ok(job_investigacoes() = 0 and reservar_caso() is null, 'com o interruptor desligado o agente não trabalha');

select * from finish();
rollback;
