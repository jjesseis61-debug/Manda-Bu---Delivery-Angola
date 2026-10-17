-- Reclamações (avaliação com poucas estrelas ou botão no pedido), análise automática, decisão do
-- gerente; desempenho do mês e estímulos (Bandura) com aprovação do administrador
begin;
\ir _helpers.psql
select plan(34);

select testes.funcionalidade('multi_cozinha', true);
select testes.funcionalidade('avaliacoes', true);
select testes.def('cz', cozinha_padrao());
with c as (insert into cozinhas (nome, responsavel) values ('Cozinha do Kilamba', 'Rosa') returning id) select testes.def('outra', id) from c;
select testes.def('gerente', testes.funcionario('Alexandra Gerente', array['pedidos.gerir']));
select testes.def('gerente2', testes.funcionario('Kátia Gerente', array['pedidos.gerir']));
select testes.def('rui', testes.funcionario('Rui Mateus', array['entregas.registar']));
select testes.def('joana', testes.funcionario('Joana Lopes', array['vendas.registar']));
select testes.def('admin', testes.funcionario('Paulo Admin', array['equipa.gerir']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), testes.u('cz')),
                                                           (current_date, testes.u('gerente2'), testes.u('outra')),
                                                           (current_date, testes.u('rui'), testes.u('cz'));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('bruno', testes.cliente('Bruno Lima'));
select testes.def('ponto', testes.ponto('residencial'));

-- Três pedidos da Ana entregues pelo Rui: P1 com 75 min de atraso, P2 e P3 a horas
create function pg_temp.pedido(p_min int) returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, subtotal, itens, criado_em)
  values (testes.u('ana'), testes.u('ponto'), testes.u('cz'), 3000,
          jsonb_build_array(jsonb_build_object('nome', 'Muamba de galinha', 'qtd', 1, 'preco_unitario', 3000)),
          now() - make_interval(mins => p_min))
  returning id;
$$;
select testes.def('P1', pg_temp.pedido(120));
select testes.def('P2', pg_temp.pedido(30));
select testes.def('P3', pg_temp.pedido(20));
update pedidos set estado = 'confirmado' where id in (testes.u('P1'), testes.u('P2'), testes.u('P3'));
update pedidos set estado = 'em_preparacao' where id in (testes.u('P1'), testes.u('P2'), testes.u('P3'));
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select mudar_estado_pedido(testes.u('P1'), 'em_entrega', null, null, null);
select mudar_estado_pedido(testes.u('P2'), 'em_entrega', null, null, null);
select mudar_estado_pedido(testes.u('P3'), 'em_entrega', null, null, null);
reset role;
select testes.sair();
select testes.pagar(testes.u('P1'));
select testes.pagar(testes.u('P2'));
select testes.pagar(testes.u('P3'));
delete from notificacoes_fila;

-- ---------------------------------------------------------------- reclamações
select testes.entrar(testes.u('ana'));
set local role authenticated;
insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario) values (testes.u('P1'), testes.u('ana'), 1, 'Chegou muito tarde e frio');
insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario) values (testes.u('P2'), testes.u('ana'), 4, 'Bom');
select testes.def('R2', fazer_reclamacao(testes.u('P2'), 'Faltou o sumo que pedi'));
select testes.def('e_repetida', testes.erro(format($$select fazer_reclamacao(%L, 'Outra vez o sumo')$$, testes.v('P2'))));
select testes.def('e_curta', testes.erro(format($$select fazer_reclamacao(%L, 'mau')$$, testes.v('P3'))));
select testes.def('minhas_ana', (select count(*) from minhas_reclamacoes()));
select testes.def('tabela_ana', (select count(*) from reclamacoes));
reset role;
select testes.entrar(testes.u('bruno'));
set local role authenticated;
select testes.def('e_bruno', testes.erro(format($$select fazer_reclamacao(%L, 'Não gostei nada')$$, testes.v('P3'))));
select testes.def('minhas_bruno', (select count(*) from minhas_reclamacoes()));
reset role;
select testes.sair();
select testes.def('R1', (select id from reclamacoes where pedido_id = testes.u('P1')));

select is((select array_agg(origem || ':' || coalesce(estrelas::text, '-') order by origem) from reclamacoes),
          array['avaliacao:1', 'cliente:-'], 'a avaliação de 1★ vira reclamação; a de 4★ não; o botão do pedido também cria');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila
            where codigo = 'N21' and dados ->> 'reclamacao_id' = testes.v('R1') and funcionario_id = testes.u('gerente')),
          'Reclamação de Ana (1★): Chegou muito tarde e frio', 'N21 ao gerente da cozinha, com quem e o quê');
select ok(not exists (select 1 from notificacoes_fila where codigo = 'N21' and funcionario_id = testes.u('gerente2')),
          'o gerente de outra cozinha não é avisado');
select ok(testes.v('e_repetida') = 'P0001:reclamacao_existente' and testes.v('e_curta') = 'P0001:texto_curto'
          and testes.v('e_bruno') = 'P0001:pedido_inexistente',
          'uma reclamação por pedido, com texto, e só do próprio cliente');
select ok(testes.v('minhas_ana') = '2' and testes.v('minhas_bruno') = '0' and testes.v('tabela_ana') = '0',
          'o cliente vê as suas reclamações pela função (nunca a análise interna da tabela)');

-- A análise automática recebe os factos do pedido, sem nomes
select testes.def('reserva', reservar_analises(5));
select is((select count(*)::int from jsonb_array_elements(testes.v('reserva')::jsonb -> 'reclamacoes')), 2,
          'reserva as 2 reclamações por analisar');
select ok((select (e -> 'factos' -> 'pedido' ->> 'minutos_de_atraso_na_entrega')::int between 74 and 76
                  and e -> 'factos' -> 'pedido' ->> 'saiu_as' is not null
                  and e ->> 'texto' = 'Chegou muito tarde e frio'
             from jsonb_array_elements(testes.v('reserva')::jsonb -> 'reclamacoes') e where e ->> 'id' = testes.v('R1')),
          'os factos mostram o atraso real na entrega e a hora a que saiu');
select ok(testes.v('reserva') not like '%Ana%' and testes.v('reserva') not like '%Rui%',
          'os factos não levam nomes de clientes nem de funcionários');
select is((select count(*)::int from jsonb_array_elements(reservar_analises(5) -> 'reclamacoes')), 0,
          'o que está a ser analisado não volta a ser reservado');
select is(registar_analise_reclamacao(testes.u('R1'), 'analisada',
            '{"categoria":"atraso","gravidade":"media","procedente":"sim","fundamento":"Entregue 75 min depois da hora prometida",
              "resumo":"Atraso e comida fria","accao_sugerida":"Rever a saída dos pedidos","resposta_cliente":"Pedimos desculpa pelo atraso.",
              "compensacao":"desconto"}'::jsonb), 'analisada', 'regista a análise');
select registar_analise_reclamacao(testes.u('R2'), 'erro', null, 'limite');
select registar_analise_reclamacao(testes.u('R2'), 'erro', null, 'limite');
select is(registar_analise_reclamacao(testes.u('R2'), 'erro', null, 'limite'), 'indisponivel',
          'três falhas: fica para o gerente sem análise');
select ok(not has_function_privilege('authenticated', 'reservar_analises(int)', 'execute')
          and not has_function_privilege('authenticated', 'registar_analise_reclamacao(uuid, text, jsonb, text)', 'execute'),
          'só o serviço reserva e regista análises');

-- O gerente decide
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('lista', reclamacoes_lista('aberta'));
select testes.def('e_curta_resp', testes.erro(format($$select decidir_reclamacao(%L, true, 'ok')$$, testes.v('R1'))));
select decidir_reclamacao(testes.u('R1'), true, 'Tens razão, Ana. Pedimos desculpa: o próximo pedido tem 1.000 Kz de desconto.',
                          null, 'desconto', 1000);
select testes.def('e_de_novo', testes.erro(format($$select decidir_reclamacao(%L, false, 'Não tens razão')$$, testes.v('R1'))));
select testes.def('relatorio', relatorio_reclamacoes(extract(year from now() at time zone 'Africa/Luanda')::int,
                                                     extract(month from now() at time zone 'Africa/Luanda')::int));
reset role;
select testes.entrar_funcionario(testes.u('gerente2'));
set local role authenticated;
select testes.def('lista2', reclamacoes_lista('todas'));
select testes.def('e_outra', testes.erro(format($$select decidir_reclamacao(%L, false, 'Não é da nossa cozinha')$$, testes.v('R2'))));
reset role;
select testes.sair();

select ok((select count(*) = 2 and bool_or(e ->> 'ia_procedente' = 'sim' and e ->> 'estafeta' = 'Rui Mateus')
             from jsonb_array_elements(testes.v('lista')::jsonb) e),
          'o gerente vê as reclamações abertas com a análise e quem entregou');
select is(jsonb_array_length(testes.v('lista2')::jsonb), 0, 'o gerente de outra cozinha não vê as reclamações desta');
select ok(testes.v('e_curta_resp') = 'P0001:resposta_obrigatoria' and testes.v('e_de_novo') = 'P0001:reclamacao_decidida'
          and testes.v('e_outra') like '42501:%', 'resposta obrigatória, decide-se uma vez e só na sua cozinha');
select results_eq(format($$select estado, procedente, categoria, compensacao, compensacao_valor, decidido_por from reclamacoes where id = %L$$, testes.v('R1')),
                  format($$values ('resolvida'::text, true, 'atraso'::text, 'desconto'::text, 1000, %L::uuid)$$, testes.v('gerente')),
                  'a decisão fica guardada (a categoria vem da análise se o gerente não a mudar)');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N22' and cliente_id = testes.u('ana')),
          'Sobre a tua reclamação: Tens razão, Ana. Pedimos desculpa: o próximo pedido tem 1.000 Kz de desconto.',
          'N22: a cliente recebe a resposta');
select ok((testes.v('relatorio')::jsonb ->> 'total')::int = 2 and (testes.v('relatorio')::jsonb ->> 'procedentes')::int = 1
          and (testes.v('relatorio')::jsonb ->> 'ia_concordou')::int = 1 and (testes.v('relatorio')::jsonb ->> 'compensacoes_kz')::int = 1000
          and testes.v('relatorio')::jsonb -> 'por_estafeta' -> 0 ->> 'estafeta' = 'Rui Mateus',
          'relatório do mês: total, com razão, acerto da análise, compensações e por estafeta');

-- ---------------------------------------------------------------- estímulos
-- A Joana vendeu 4 vezes ao balcão; o Rui tinha a meta de 2 entregas no mês passado (aprovada)
insert into vendas (data, produto, qtd, valor_total, registado_por, movimenta_stock, cozinha_id)
select now(), 'Prato do dia', 1, 2500, testes.u('joana'), false, testes.u('cz') from generate_series(1, 4);
insert into estimulos_mensais (ano, mes, tipo, funcionario_id, mensagem, meta, estado)
values (extract(year from (now() at time zone 'Africa/Luanda') - interval '1 month'),
        extract(month from (now() at time zone 'Africa/Luanda') - interval '1 month'),
        'funcionario', testes.u('rui'), 'mês passado', '{"metrica": "entregas", "valor": 2}', 'aprovado');
create temp table periodo as select extract(year from now() at time zone 'Africa/Luanda')::int as a,
                                    extract(month from now() at time zone 'Africa/Luanda')::int as m;
grant select on periodo to authenticated;

select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('e_gerar', testes.erro('select gerar_estimulos((select a from periodo), (select m from periodo))'));
reset role;
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('gerados', gerar_estimulos((select a from periodo), (select m from periodo)));
select testes.def('regerados', gerar_estimulos((select a from periodo), (select m from periodo)));
select testes.def('e_futuro', testes.erro('select gerar_estimulos(2100, 12)'));
select testes.def('lista_est', estimulos_do_mes((select a from periodo), (select m from periodo)));
reset role;
select testes.sair();
select testes.def('E_rui', (select id from estimulos_mensais where funcionario_id = testes.u('rui') and mes = (select m from periodo)));
select testes.def('E_joana', (select id from estimulos_mensais where funcionario_id = testes.u('joana')));
select testes.def('E_ana', (select id from estimulos_mensais where cliente_id = testes.u('ana')));

select ok(testes.v('gerados') = '3' and testes.v('regerados') = '3'
          and (select count(*) from estimulos_mensais where mes = (select m from periodo) and ano = (select a from periodo)) = 3,
          'gera para quem trabalhou (Rui, Joana) e para quem mais comprou (Ana); refazer não duplica');
select ok(testes.v('e_gerar') like '42501:%' and testes.v('e_futuro') = 'P0001:periodo_invalido',
          'só quem gere a equipa gera, e não para meses futuros');
select ok((select mensagem like 'Rui, em % fizeste 3 entregas. Atingiste a meta que combinámos. Parabéns! Houve 1 reclamação com razão: vale a pena rever com o gerente o que aconteceu. Foste a referência da equipa neste ponto. Meta para %: 4 entregas.'
             from estimulos_mensais where id = testes.u('E_rui')),
          'Rui: mestria (o que fez), meta atingida, feedback concreto, modelo e meta próxima');
select results_eq(format($$select bonus_sugerido, meta, (meta_anterior ->> 'atingida')::boolean from estimulos_mensais where id = %L$$, testes.v('E_rui')),
                  $$values (5000, '{"metrica": "entregas", "valor": 4}'::jsonb, true)$$,
                  'bónus sugerido só porque atingiu a meta combinada; nova meta um passo acima');
select ok((select mensagem like 'Joana, em % fizeste 4 vendas ao balcão. Foste a referência da equipa neste ponto. Meta para %: 5 vendas ao balcão.'
                  and bonus_sugerido = 0 from estimulos_mensais where id = testes.u('E_joana')),
          'Joana: vendas ao balcão, sem meta anterior não há bónus');
select ok((select mensagem like 'Obrigado, Ana! Em % fizeste 3 pedidos na Manda Bué. Com 4 pedidos em % ganhas um prémio.'
             from estimulos_mensais where id = testes.u('E_ana')),
          'Ana (cliente que mais comprou): agradecimento e meta próxima');
select is(jsonb_array_length(testes.v('lista_est')::jsonb), 3, 'o administrador vê os estímulos propostos');

-- A análise automática escreve a mensagem da Ana; o administrador aprova e descarta
select is((select count(*)::int from jsonb_array_elements(reservar_analises(10) -> 'estimulos')), 3,
          'os estímulos propostos vão para a mensagem personalizada');
select registar_mensagem_estimulo(testes.u('E_ana'), 'analisada', 'Ana, obrigado pela confiança: 3 pedidos este mês!');
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('e_aprovar', testes.erro(format($$select decidir_estimulo(%L, true)$$, testes.v('E_rui'))));
reset role;
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select decidir_estimulo(testes.u('E_rui'), true, 6000, 'Rui, 3 entregas e meta cumprida. Bónus de 6.000 Kz. Próxima meta: 4 entregas.');
select decidir_estimulo(testes.u('E_ana'), true);
select decidir_estimulo(testes.u('E_joana'), false);
select testes.def('e_duas', testes.erro(format($$select decidir_estimulo(%L, true)$$, testes.v('E_rui'))));
select gerar_estimulos((select a from periodo), (select m from periodo));
reset role;
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('vistos_rui', (select count(*) from estimulos_mensais));
reset role;
select testes.entrar_funcionario(testes.u('joana'));
set local role authenticated;
select testes.def('vistos_joana', (select count(*) from estimulos_mensais));
reset role;
select testes.sair();

select ok(testes.v('e_aprovar') like '42501:%' and testes.v('e_duas') = 'P0001:estimulo_decidido',
          'só o administrador aprova, e uma vez');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N23' and funcionario_id = testes.u('rui')),
          'Rui, 3 entregas e meta cumprida. Bónus de 6.000 Kz. Próxima meta: 4 entregas.', 'N23 ao Rui com a mensagem editada');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N23' and cliente_id = testes.u('ana')),
          'Ana, obrigado pela confiança: 3 pedidos este mês!', 'N23 à Ana com a mensagem personalizada');
select ok(not exists (select 1 from notificacoes_fila where codigo = 'N23' and funcionario_id = testes.u('joana')),
          'descartado: a Joana não é avisada');
select results_eq(format($$select estado, bonus, mensagem_final like 'Rui, 3 entregas%%' from estimulos_mensais where id = %L$$, testes.v('E_rui')),
                  $$values ('aprovado'::text, 6000, true)$$, 'gerar de novo não mexe no que já foi aprovado');
select ok(testes.v('vistos_rui') = '2' and testes.v('vistos_joana') = '0',
          'cada funcionário vê os seus estímulos aprovados (o Rui: este mês e o anterior)');
select ok(exists (select 1 from notificacoes_por_enviar(1000) where codigo = 'N21')
          and exists (select 1 from notificacoes_por_enviar(1000) where codigo = 'N22')
          and exists (select 1 from notificacoes_por_enviar(1000) where codigo = 'N23'),
          'N21 a N23 seguem para envio');
select ok(job_estimulos_mensais() >= 0 and exists (select 1 from auditoria where acao = 'estimulo_aprovado')
          and exists (select 1 from auditoria where acao = 'reclamacao_decidida' and funcionario_nome = 'Alexandra Gerente'),
          'o job do dia 1 corre; decisões ficam na auditoria');

select * from finish();
rollback;
