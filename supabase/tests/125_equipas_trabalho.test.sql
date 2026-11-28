-- Junta Bué no trabalho: equipa fixa com responsável, grupo do dia, uma refeição por dia com extra aprovado
-- pela cozinha, pedido em nome do colega (só com autorização), conta do mês, acordo e benefício desbloqueado
-- quando o colega paga, sem ganha-ganha no mesmo pedido; «só a cozinha» sem taxa nem comissão.
begin;
\ir _helpers.psql
select plan(38);

select testes.funcionalidade('pedidos_grupo', true);
select testes.funcionalidade('equipas_trabalho', true);
select testes.funcionalidade('indicacao', true);
with z as (insert into zonas (nome, tipo, taxa) values ('Talatona Eq', 'Própria', 1000) returning id)
select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Funge Eq', 3000) returning id) select testes.def('funge', id) from m;
with m as (insert into cardapio (nome, preco, categoria) values ('Coca Eq', 500, 'Bebidas') returning id) select testes.def('coca', id) from m;

select testes.def('maria', testes.cliente('Maria Responsável'));
select testes.def('joao', testes.cliente('João Colega'));
select testes.def('rui', testes.cliente('Rui Colega'));
select testes.def('escritorio', testes.ponto('empresa', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('maria'), testes.u('escritorio'));
-- O João chegou pelo código da Maria (ganha-ganha), mas na equipa com acordo conta o benefício
select testes.def('lig', testes.ligar(testes.u('joao'), testes.u('maria')));
-- Entrega daqui a 3 horas (o dia pode ser amanhã, perto da meia-noite em Luanda)
select testes.def('quando', (now() at time zone 'Africa/Luanda') + interval '3 hours');

select testes.def('fin', testes.funcionario('Fátima Finanças', array['financas.acertos', 'clientes.gerir']));
select testes.def('coz', testes.funcionario('Carlos Cozinha', array['pedidos.gerir']));

-- 1) A Maria cria a equipa e convida os colegas pelo código
select testes.def('cod_joao', testes.codigo(testes.u('joao')));
select testes.def('cod_rui', testes.codigo(testes.u('rui')));
select testes.entrar(testes.u('maria'));
set local role authenticated;
select testes.def('eq', criar_equipa('Contabilidade', testes.u('escritorio'), cozinha_padrao(), testes.v('quando')::timestamp::time, 60));
select testes.def('e_dupla', testes.erro(format($$select criar_equipa('Outra', %L, cozinha_padrao(), '12:00')$$, testes.v('escritorio'))));
select testes.def('nome_joao', equipa_convidar(testes.u('eq'), testes.v('cod_joao')));
select equipa_convidar(testes.u('eq'), testes.v('cod_rui'));
select testes.def('e_cod', testes.erro(format($$select equipa_convidar(%L, 'MB0000000')$$, testes.v('eq'))));
reset role;
select is(testes.v('e_dupla'), 'P0001:ja_tem_equipa', 'uma equipa activa de cada vez');
select is(testes.v('nome_joao'), 'João Colega', 'convite pelo código do colega');
select is(testes.v('e_cod'), 'P0001:codigo_invalido', 'código desconhecido é recusado');

-- 2) O João aceita e autoriza tudo; o Rui aceita sem autorizações
select testes.entrar(testes.u('joao'));
set local role authenticated;
select equipa_responder(testes.u('eq'), true, true, true);
reset role;
select testes.entrar(testes.u('rui'));
set local role authenticated;
select equipa_responder(testes.u('eq'), true, false, false);
reset role;
select is((select count(*)::int from equipa_membros where equipa_id = testes.u('eq') and estado = 'activo'), 3, 'três colegas activos');

-- 3) O grupo do dia abre sozinho e pergunta «Vais almoçar hoje?»
select testes.def('grupo', abrir_grupo_equipa(testes.u('eq'), testes.v('quando')::timestamp::date));
select is((select modo_pagamento from pedidos_grupo where id = testes.u('grupo')), 'conta_mes', 'grupo do dia na conta do mês');
select is((select count(*)::int from notificacoes_fila where codigo = 'N31' and dados ->> 'titulo' = 'Vais almoçar hoje?'
             and cliente_id in (testes.u('maria'), testes.u('joao'), testes.u('rui'))), 3, 'cada colega recebe a pergunta');
select is(abrir_grupo_equipa(testes.u('eq'), testes.v('quando')::timestamp::date), null, 'não abre dois grupos no mesmo dia');

-- 4) O João pede: vai para a conta do mês; um segundo almoço passa o limite de um por dia
select testes.entrar(testes.u('joao'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('joao'), testes.u('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1),
                                                                          jsonb_build_object('cardapio_id', testes.u('coca'), 'qtd', 1)))
           returning id)
select testes.def('p1', id) from x;
select testes.def('e_dois', testes.erro(format($$insert into pedidos (cliente_id, grupo_id, itens) values (%L, %L, %L)$$,
  testes.v('joao'), testes.v('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1)))));
select testes.def('e_porpor', testes.erro(format($$insert into pedidos (cliente_id, grupo_id, itens, pedido_por) values (%L, %L, %L, %L) returning pedido_por$$,
  testes.v('joao'), testes.v('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('coca'), 'qtd', 1)), testes.v('maria'))));
-- Pede mais uma refeição (visita)
select testes.def('extra', pedir_refeicoes_extra(testes.u('eq'), 1, 'Visita de um cliente'));
reset role;
select ok((select empresa_id = (select empresa_id from equipas where id = testes.u('eq'))
                  and valor_empresa = subtotal + taxa_entrega - desconto_indicacao and valor_empresa > 0
             from pedidos where id = testes.u('p1')), 'o almoço vai todo para a conta do mês');
select is(testes.v('e_dois'), 'P0001:limite_refeicoes_dia', 'uma refeição por dia (a bebida não conta)');
select ok(testes.v('e_porpor') like '42501:%', 'a app não escolhe quem pediu');
select ok(exists (select 1 from notificacoes_fila where codigo = 'N32' and funcionario_id = testes.u('coz')), 'a cozinha é avisada do pedido extra');

-- 5) A cozinha aprova a refeição extra e o João já pode pedir mais uma
select testes.entrar_funcionario(testes.u('coz'));
set local role authenticated;
select decidir_extra(testes.u('extra'), 1);
reset role;
select testes.sair();
select testes.entrar(testes.u('joao'));
set local role authenticated;
select lives_ok(format($$insert into pedidos (cliente_id, grupo_id, itens) values (%L, %L, %L)$$,
  testes.v('joao'), testes.v('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1))),
  'com a extra aprovada, a segunda refeição passa');
reset role;

-- 6) Pedir em nome do colega: só com a autorização dele; ele é avisado e pode recusar
select testes.entrar(testes.u('maria'));
set local role authenticated;
select testes.def('e_aut', testes.erro(format($$select pedir_por_colega(%L, %L, %L)$$, testes.v('eq'), testes.v('rui'),
  jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1)))));
select testes.def('e_ver', testes.erro(format($$select conta_mes(%L, %L)$$, testes.v('eq'), testes.v('rui'))));
reset role;
select testes.entrar(testes.u('rui'));
set local role authenticated;
select equipa_autorizacoes(testes.u('eq'), true, false);
reset role;
select testes.entrar(testes.u('maria'));
set local role authenticated;
select testes.def('p_rui', pedir_por_colega(testes.u('eq'), testes.u('rui'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1))));
reset role;
select is(testes.v('e_aut'), 'P0001:sem_autorizacao_do_colega', 'sem autorização não pede pelo colega');
select is(testes.v('e_ver'), '42501:sem_autorizacao_do_colega', 'sem autorização não vê a conta do colega');
select ok((select pedido_por = testes.u('maria') and cliente_id = testes.u('rui') and subtotal = 3000 and valor_empresa > 0
             from pedidos where id = testes.u('p_rui')), 'pedido em nome do Rui, com preço do servidor e na conta dele');
select ok(exists (select 1 from notificacoes_fila where cliente_id = testes.u('rui') and dados ->> 'titulo' = 'Maria pediu o teu almoço'),
          'o Rui é avisado');
select testes.entrar(testes.u('rui'));
set local role authenticated;
select recusar_pedido_colega(testes.u('p_rui'));
reset role;
select is((select estado from pedidos where id = testes.u('p_rui')), 'cancelado', 'o Rui recusa e o almoço sai da entrega');

-- 7) Acordo: «só a cozinha» exige equipa trazida pela cozinha; plataforma proposta e aceite pela cozinha
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('e_soc', testes.erro(format($$select propor_acordo_equipa(%L, 'cozinha')$$, testes.v('eq'))));
select testes.def('acordo', propor_acordo_equipa(testes.u('eq'), 'plataforma'));
reset role;
select testes.sair();
select testes.entrar_funcionario(testes.u('coz'));
set local role authenticated;
select aceitar_acordo_equipa(testes.u('acordo'));
reset role;
select testes.sair();
select is(testes.v('e_soc'), 'P0001:so_cozinha_exige_origem_cozinha', '«só a cozinha» só para equipas trazidas pela cozinha');
select is((select estado from equipa_acordos where id = testes.u('acordo')), 'activo', 'acordo aceite pela cozinha');

-- 8) Entregue: benefício de 3% (sem histórico) sobre o prato, sem a bebida nem a taxa; sem ganha-ganha
-- Nada a cobrar na entrega: as parcelas ficam vazias (a conta cobre tudo)
update pedidos set caixa_id = testes.caixa(cozinha_id), parcelas = '[]', estado = 'entregue_pago', entregue_em = now() where id = testes.u('p1');
select is((select valor from equipa_beneficios where pedido_id = testes.u('p1')), 75, '3% do prato pago: 3.000 − 500 de desconto do 1.º pedido (a bebida não conta)');
select is((select estado from equipa_beneficios where pedido_id = testes.u('p1')), 'pendente', 'fica pendente até o João pagar');
select is((select count(*)::int from ganhos_indicacao where pedido_id = testes.u('p1')), 0, 'o mesmo pedido não dá ganha-ganha');
select ok(exists (select 1 from vendas where pedido_id = testes.u('p1') and parcelas @> '[{"metodo": "Conta do mês"}]'),
          'na venda, a parte da conta chama-se «Conta do mês»');

-- 9) Conta do mês: o João paga por referência, as Finanças confirmam e o benefício desbloqueia
select testes.entrar(testes.u('joao'));
set local role authenticated;
select testes.def('conta', conta_mes(testes.u('eq'))::text);
select testes.def('e_mais', testes.erro(format($$select pagar_conta_mes(%L, %L, current_date, 'multicaixa_express', 'MCX 7788', 999999)$$,
  testes.v('eq'), testes.v('joao'))));
select testes.def('pag', pagar_conta_mes(testes.u('eq'), testes.u('joao'), testes.hoje(), 'multicaixa_express', 'MCX 7788',
                                         (testes.v('conta')::jsonb ->> 'em_falta')::int));
reset role;
select is((testes.v('conta')::jsonb ->> 'total')::int, (select valor_empresa from pedidos where id = testes.u('p1')),
          'a conta soma os almoços entregues');
select is(testes.v('e_mais'), 'P0001:valor_invalido', 'não se paga mais do que falta');
select testes.entrar(testes.u('maria'));
set local role authenticated;
select testes.def('conta_joao', conta_mes(testes.u('eq'), testes.u('joao'))::text);
reset role;
select is((testes.v('conta_joao')::jsonb ->> 'a_confirmar')::int, (testes.v('conta')::jsonb ->> 'em_falta')::int,
          'a responsável autorizada vê a conta do João (pagamento a confirmar)');
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select decidir_pagamento_conta_mes(testes.u('pag'), true);
reset role;
select is((select estado from equipa_beneficios where pedido_id = testes.u('p1')), 'desbloqueado', 'o João pagou: benefício desbloqueado');
select ok(exists (select 1 from notificacoes_fila where cliente_id = testes.u('joao') and dados ->> 'titulo' = 'Pagamento confirmado'),
          'o João sabe que o pagamento foi confirmado');

-- 10) A responsável vê o benefício; as Finanças pagam-lhe o desbloqueado
select testes.entrar(testes.u('maria'));
set local role authenticated;
select testes.def('minhas', minhas_equipas()::text);
reset role;
select is((testes.v('minhas')::jsonb -> 0 -> 'beneficio' ->> 'desbloqueado')::int, 75, 'a Maria vê 75 Kz desbloqueados');
select is((testes.v('minhas')::jsonb -> 0 -> 'colegas' -> 0 ->> 'nome'), 'Maria Responsável', 'a responsável aparece primeiro');
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('pago', pagar_beneficio_equipa(testes.u('eq'), 'multicaixa_express'));
select testes.def('lista_emp', (select count(*) from listar_empresas() where nome like 'Equipa ·%'));
reset role;
select is(testes.v('pago')::int, 75, 'benefício pago à responsável');
select is(testes.v('lista_emp')::int, 0, 'a conta da equipa não aparece nas empresas');

-- 11) «Só a cozinha»: equipa trazida pela cozinha, sem taxa de entrega e sem comissão
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select definir_equipa(testes.u('eq'), 40000, 'cozinha', true);
select terminar_acordo_equipa(testes.u('acordo'));
select testes.def('acordo2', propor_acordo_equipa(testes.u('eq'), 'cozinha'));
reset role;
select testes.sair();
select testes.entrar_funcionario(testes.u('coz'));
set local role authenticated;
select aceitar_acordo_equipa(testes.u('acordo2'));
reset role;
select testes.sair();
select testes.entrar(testes.u('rui'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('rui'), testes.u('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1)))
           returning id)
select testes.def('p_soc', id) from x;
reset role;
select is((select taxa_entrega from pedidos where id = testes.u('p_soc')), 0, '«só a cozinha»: entrega 0 Kz');
select is((acerto_valores_pedido((select p from pedidos p where id = testes.u('p_soc')), 1) ->> 'comissao')::int, 0,
          '«só a cozinha»: comissão 0');
select ok((acerto_valores_pedido((select p from pedidos p where id = testes.u('p1')), 1) ->> 'comissao')::int
            = round(3500 * coalesce((select comissao_percent from cozinhas where id = cozinha_padrao()), 0) / 100)::int,
          'os outros pedidos mantêm a comissão');

-- 12) Ao fechar o grupo, a taxa repartida não volta a aparecer no «só a cozinha»
select fechar_grupo_interno(testes.u('grupo'));
select is((select taxa_entrega from pedidos where id = testes.u('p_soc')), 0, 'no fecho, a entrega do «só a cozinha» continua a 0 Kz');
select ok((select valor_empresa = subtotal + taxa_entrega - desconto_indicacao from pedidos
            where grupo_id = testes.u('grupo') and cliente_id = testes.u('joao') and estado = 'pendente'),
          'no fecho, a conta do mês acompanha a taxa repartida');

-- 13) Sem o interruptor, nada disto funciona
select testes.funcionalidade('equipas_trabalho', false);
select testes.entrar(testes.u('joao'));
set local role authenticated;
select testes.def('e_off', testes.erro($$select minhas_equipas()$$));
reset role;
select is(testes.v('e_off'), 'P0001:funcionalidade_desligada', 'interruptor desligado');

select * from finish();
rollback;
