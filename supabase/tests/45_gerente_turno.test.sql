-- Gerente de turno: situação da cozinha (sem nomes de clientes), escolha da cozinha a analisar, propostas
-- validadas e sem repetir, N27, e a decisão do gerente (a acção corre com as permissões dele)
begin;
\ir _helpers.psql
select plan(15);

select testes.funcionalidade('agente_turno', true);
select testes.funcionalidade('multi_cozinha', true);
update parametros set turno_hora_inicio = 0, turno_hora_fim = 24 where unico;
select testes.def('cz', cozinha_padrao());
with c as (insert into cozinhas (nome, responsavel) values ('Cozinha do Kilamba', 'Rosa') returning id) select testes.def('outra', id) from c;
select testes.def('gerente', testes.funcionario('Alexandra Gerente', array['pedidos.gerir']));
select testes.def('gerente2', testes.funcionario('Kátia Gerente', array['pedidos.gerir']));
select testes.def('rui', testes.funcionario('Rui Estafeta', array['entregas.registar']));
insert into turnos (data, funcionario_id, cozinha_id) values ((now() at time zone 'Africa/Luanda')::date, testes.u('gerente'), testes.u('cz')),
                                                           ((now() at time zone 'Africa/Luanda')::date, testes.u('gerente2'), testes.u('outra')),
                                                           ((now() at time zone 'Africa/Luanda')::date, testes.u('rui'), testes.u('cz'));
with c as (insert into cardapio (cozinha_id, nome, preco, do_dia) values (testes.u('cz'), 'Calulu de peixe', 3500, true) returning id)
select testes.def('calulu', id) from c;
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('ponto', testes.ponto('residencial'));
create function pg_temp.pedido(p_min int, p_cozinha text default 'cz') returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, subtotal, itens, criado_em)
  values (testes.u('ana'), testes.u('ponto'), testes.u(p_cozinha), 3500,
          jsonb_build_array(jsonb_build_object('nome', 'Calulu de peixe', 'qtd', 1, 'preco_unitario', 3500, 'cardapio_id', testes.v('calulu'))),
          -- Não recua antes da meia-noite de Luanda: o turno vê os pedidos pelo dia de Luanda,
          -- por isso perto da meia-noite UTC um "há 70 min" cairia no dia anterior e sumia.
          greatest(now() - make_interval(mins => p_min),
                   date_trunc('day', now() at time zone 'Africa/Luanda') at time zone 'Africa/Luanda'))
  returning id;
$$;
select testes.def('A', pg_temp.pedido(12));           -- por confirmar há 12 min
select testes.def('B', pg_temp.pedido(70));           -- atrasado (hora prometida há 25 min)
select testes.def('K', pg_temp.pedido(5, 'outra'));   -- de outra cozinha (ainda no prazo)
select testes.def('K2', pg_temp.pedido(30, 'outra')); -- outra cozinha: perto da hora prometida
update pedidos set estado = 'confirmado' where id = testes.u('B');
-- B está atrasado: a hora prometida já passou há 25 min (fixa, para não depender de quão "velho" é o
-- pedido — perto da meia-noite de Luanda o criado_em é ancorado ao próprio dia, ver acima).
update pedidos set estado = 'em_preparacao', hora_prometida = now() - interval '25 min' where id = testes.u('B');

-- Situação e escolha da cozinha
select testes.def('reserva', reservar_turno());
select ok(testes.v('reserva')::jsonb ->> 'cozinha_id' in (testes.v('cz'), testes.v('outra')), 'escolhe uma cozinha com algo a pedir atenção');
select testes.def('reserva2', reservar_turno());
select testes.def('reserva3', reservar_turno());
select ok(testes.v('reserva2') is not null and testes.v('reserva3') is null,
          'cada cozinha é vista uma vez de 5 em 5 minutos (a segunda chamada dá a outra; a terceira nada)');
select testes.def('sit', situacao_turno(testes.u('cz')));
select ok(jsonb_array_length(testes.v('sit')::jsonb -> 'pedidos_em_curso') = 2
          and (select (e ->> 'minutos_ate_a_hora_prometida')::int < -20 from jsonb_array_elements(testes.v('sit')::jsonb -> 'pedidos_em_curso') e
                where e ->> 'pedido_id' = testes.v('B')),
          'situação: os 2 pedidos em curso da cozinha, com o atraso do B');
select ok((testes.v('sit')::jsonb -> 'estafetas_de_turno' -> 0 ->> 'nome') = 'Rui Estafeta'
          and exists (select 1 from jsonb_array_elements(testes.v('sit')::jsonb -> 'pratos_disponiveis') e
                       where e ->> 'cardapio_id' = testes.v('calulu') and (e ->> 'vendidos_hoje')::int = 2)
          and testes.v('sit') not like '%Ana%', 'estafetas de turno, pratos disponíveis e nenhum nome de cliente');

-- Propostas do agente: valida, não repete, avisa (N27)
select testes.def('n', registar_propostas_turno(testes.u('cz'), jsonb_build_array(
  jsonb_build_object('tipo', 'avisar_atraso', 'pedido_id', testes.v('B'), 'prioridade', 'alta',
                     'explicacao', 'Passou 25 min da hora prometida e o cliente ainda não sabe porquê.',
                     'motivo_cliente', 'A cozinha está com muitos pedidos', 'mais_minutos', 15),
  jsonb_build_object('tipo', 'confirmar', 'pedido_id', testes.v('A'), 'explicacao', 'Está por confirmar há 12 minutos.'),
  jsonb_build_object('tipo', 'pausar_prato', 'cardapio_id', testes.v('calulu'), 'explicacao', 'Acabou o peixe.'),
  jsonb_build_object('tipo', 'avisar_atraso', 'pedido_id', testes.v('A'), 'explicacao', 'sem motivo para o cliente'),
  jsonb_build_object('tipo', 'confirmar', 'pedido_id', testes.v('K'), 'explicacao', 'pedido de outra cozinha'),
  jsonb_build_object('tipo', 'apagar_tudo', 'explicacao', 'tipo que não existe'))));
select testes.def('n2', registar_propostas_turno(testes.u('cz'), jsonb_build_array(
  jsonb_build_object('tipo', 'confirmar', 'pedido_id', testes.v('A'), 'explicacao', 'De novo.'))));
select ok(testes.v('n') = '3' and testes.v('n2') = '0',
          'guarda as 3 propostas válidas (sem motivo, de outra cozinha ou tipo estranho não entram) e não repete');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N27' and funcionario_id = testes.u('gerente')),
          format('Gerente de turno: 3 sugestões na %s. Abre para aceitar ou recusar.', (select trim(nome) from cozinhas where id = testes.u('cz'))),
          'N27 ao gerente da cozinha');
select ok(not exists (select 1 from notificacoes_fila where codigo = 'N27' and funcionario_id = testes.u('gerente2')),
          'o gerente de outra cozinha não é avisado');

-- O gerente decide
select testes.def('P_atraso', (select id from propostas_turno where tipo = 'avisar_atraso'));
select testes.def('P_conf', (select id from propostas_turno where tipo = 'confirmar'));
select testes.def('P_prato', (select id from propostas_turno where tipo = 'pausar_prato'));
select testes.entrar_funcionario(testes.u('gerente2'));
set local role authenticated;
select testes.def('e_outra', testes.erro(format($$select decidir_proposta_turno(%L, true)$$, testes.v('P_conf'))));
select testes.def('lista2', jsonb_array_length(propostas_turno_lista()));
reset role;
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('lista', jsonb_array_length(propostas_turno_lista()));
select decidir_proposta_turno(testes.u('P_atraso'), true, 'Estamos com muitos pedidos ao almoço', 20);
select decidir_proposta_turno(testes.u('P_conf'), true);
select decidir_proposta_turno(testes.u('P_prato'), false);
select testes.def('e_duas', testes.erro(format($$select decidir_proposta_turno(%L, true)$$, testes.v('P_conf'))));
reset role;
select testes.sair();
select ok(testes.v('e_outra') like '42501:%' and testes.v('lista2') = '0' and testes.v('lista') = '3',
          'cada gerente vê e decide só as propostas da sua cozinha');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N20' and dados ? 'motivo'),
          'O teu pedido vai atrasar cerca de 20 minutos: Estamos com muitos pedidos ao almoço. Pedimos desculpa pela espera.',
          'aceitar o aviso de atraso avisa o cliente (com o motivo editado pelo gerente)');
select is((select estado from pedidos where id = testes.u('A')), 'confirmado', 'aceitar "confirmar" confirma o pedido');
select ok((select disponivel from cardapio where id = testes.u('calulu')) and (select estado from propostas_turno where id = testes.u('P_prato')) = 'recusada',
          'recusar a pausa deixa o prato disponível');
select is(testes.v('e_duas'), 'P0001:proposta_expirada', 'uma proposta decide-se uma vez');

-- Propostas caducam; pausar o prato quando aceite
select registar_propostas_turno(testes.u('cz'), jsonb_build_array(
  jsonb_build_object('tipo', 'pausar_prato', 'cardapio_id', testes.v('calulu'), 'explicacao', 'Acabou mesmo o peixe.')));
select testes.def('P_prato2', (select id from propostas_turno where tipo = 'pausar_prato' and estado = 'pendente'));
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select decidir_proposta_turno(testes.u('P_prato2'), true);
reset role;
select testes.sair();
select ok(not (select disponivel from cardapio where id = testes.u('calulu'))
          and exists (select 1 from auditoria where acao = 'prato_pausado' and funcionario_nome = 'Alexandra Gerente'),
          'aceitar a pausa tira o prato do cardápio (fica na auditoria com o nome do gerente)');
select registar_propostas_turno(testes.u('cz'), jsonb_build_array(jsonb_build_object('tipo', 'reforco', 'explicacao', 'Muitos pedidos e um só estafeta.')));
update propostas_turno set expira_em = now() - interval '1 minute' where tipo = 'reforco';
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('e_velha', testes.erro(format($$select decidir_proposta_turno(%L, true)$$, (select id from propostas_turno where tipo = 'reforco'))));
reset role;
select testes.sair();
select is(testes.v('e_velha'), 'P0001:proposta_expirada', 'uma proposta com mais de 30 minutos já não se aceita');

select testes.funcionalidade('agente_turno', false);
select ok(reservar_turno() is null and not has_function_privilege('authenticated', 'situacao_turno(uuid)', 'execute'),
          'interruptor desligado = parado; as ferramentas só o serviço as chama');

select * from finish();
rollback;
