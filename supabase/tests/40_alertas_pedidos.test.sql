-- Alertas dos pedidos: sem confirmação há 7 min (N18), atrasado (N19 gerentes, N20 cliente),
-- motivo do atraso dito pelo gerente ou pelo estafeta (N20 com o motivo)
begin;
\ir _helpers.psql
select plan(18);

select testes.funcionalidade('multi_cozinha', true);
select testes.def('cz', cozinha_padrao());
with c as (insert into cozinhas (nome, responsavel) values ('Cozinha do Kilamba', 'Rosa') returning id) select testes.def('outra', id) from c;
select testes.def('gerente', testes.funcionario('Gerente Alexandra', array['pedidos.gerir']));
select testes.def('gerente2', testes.funcionario('Gerente Kilamba', array['pedidos.gerir']));
select testes.def('estafeta', testes.funcionario('Estafeta Rui', array['entregas.registar']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), testes.u('cz')),
                                                           (current_date, testes.u('gerente2'), testes.u('outra')),
                                                           (current_date, testes.u('estafeta'), testes.u('cz'));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('bruno', testes.cliente('Bruno Lima'));
select testes.def('ponto', testes.ponto('residencial'));

-- A: por confirmar há 10 min; B: confirmado, passou a hora prometida; C: a caminho, atrasado;
-- D: entregue (não conta); E: por confirmar há 2 min (ainda no prazo)
create function pg_temp.pedido(p_min int) returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, subtotal, itens, criado_em)
  values (testes.u('ana'), testes.u('ponto'), testes.u('cz'), 3000,
          jsonb_build_array(jsonb_build_object('nome', 'Chocos', 'qtd', 1, 'preco_unitario', 3000)),
          now() - make_interval(mins => p_min))
  returning id;
$$;
select testes.def('A', pg_temp.pedido(10));
select testes.def('B', pg_temp.pedido(60));
select testes.def('C', pg_temp.pedido(70));
select testes.def('D', pg_temp.pedido(80));
select testes.def('E', pg_temp.pedido(2));
update pedidos set estado = 'confirmado' where id in (testes.u('B'), testes.u('C'), testes.u('D'));
update pedidos set estado = 'em_preparacao' where id in (testes.u('C'), testes.u('D'));
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select mudar_estado_pedido(testes.u('C'), 'em_entrega', null, null, null);
select mudar_estado_pedido(testes.u('D'), 'em_entrega', null, null, null);
reset role;
select testes.sair();
select testes.pagar(testes.u('D'));
delete from notificacoes_fila;

select is(job_alertas_pedidos(), 3, 'o job dá 3 alertas: A sem confirmação, B e C atrasados');
select is(job_alertas_pedidos(), 0, 'na execução seguinte não repete os mesmos alertas');

select is((select array_agg(funcionario_id order by funcionario_id) from notificacoes_fila where codigo = 'N18'),
          array[testes.u('gerente')], 'N18 (sem confirmação) só ao gerente da cozinha do pedido');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N18'),
          'O pedido de Ana (1× Chocos) foi feito há 10 minutos e ainda não foi confirmado.', 'N18: quem, o quê e há quanto tempo');
select ok(not exists (select 1 from alertas_pedido where pedido_id in (testes.u('D'), testes.u('E'))),
          'pedido entregue e pedido ainda no prazo não têm alerta');
select is((select count(*)::int from notificacoes_fila where codigo = 'N19' and dados ->> 'pedido_id' = testes.v('C')
            and funcionario_id in (testes.u('gerente'), testes.u('estafeta'))), 2,
          'N19 (atraso) ao gerente e ao estafeta que leva o pedido');
select is((select count(*)::int from notificacoes_fila where codigo = 'N20' and cliente_id = testes.u('ana')), 2,
          'N20: a cliente é avisada de cada pedido atrasado');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N20' and dados ->> 'pedido_id' = testes.v('B')),
          'O teu pedido está a demorar mais do que o previsto. Já avisámos a cozinha e damos-te notícias em breve.',
          'N20 sem motivo: a cozinha já sabe');
select is((select minutos from alertas_pedido where pedido_id = testes.u('B') and tipo = 'atraso'), 15,
          'o alerta guarda os minutos de atraso (hora prometida 45 min depois do pedido)');

-- O gerente diz o motivo; o gerente de outra cozinha não pode; o estafeta pode no pedido que leva
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select informar_atraso(testes.u('B'), 'Muitos pedidos neste momento', 15);
select testes.def('e_vazio', testes.erro(format($$select informar_atraso(%L, '  ')$$, testes.v('B'))));
select testes.def('abertos', (select count(*) from alertas_abertos()));
reset role;
select testes.entrar_funcionario(testes.u('gerente2'));
set local role authenticated;
select testes.def('e_outra', testes.erro(format($$select informar_atraso(%L, 'x')$$, testes.v('B'))));
reset role;
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('ok_estafeta', testes.erro(format($$select informar_atraso(%L, 'Trânsito na estrada de Catete', 10)$$, testes.v('C'))));
select testes.def('e_estafeta', testes.erro(format($$select informar_atraso(%L, 'x')$$, testes.v('B'))));
reset role;
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila
            where codigo = 'N20' and dados ->> 'pedido_id' = testes.v('B') and dados ? 'motivo'),
          'O teu pedido vai atrasar cerca de 15 minutos: Muitos pedidos neste momento. Pedimos desculpa pela espera.',
          'N20 com o motivo e a nova estimativa');
select results_eq(format($$select motivo, mais_minutos, motivo_por from alertas_pedido where pedido_id = %L and tipo = 'atraso'$$, testes.v('B')),
                  format($$values ('Muitos pedidos neste momento'::text, 15, %L::uuid)$$, testes.v('gerente')),
                  'o alerta guarda o motivo, a estimativa e quem a deu');
select is(testes.v('e_vazio'), 'P0001:motivo_obrigatorio', 'sem motivo não se avisa');
select ok(testes.v('e_outra') like '42501:%' and testes.v('e_estafeta') like '42501:%',
          'gerente de outra cozinha e estafeta que não leva o pedido não podem');
select is(testes.v('ok_estafeta'), 'sem_erro', 'o estafeta avisa o atraso do pedido que leva');
select is(testes.v('abertos'), '3', 'o gerente vê os alertas dos pedidos em curso');

-- A cliente vê os alertas dos seus pedidos; outro cliente não
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('vistos_ana', (select count(*) from alertas_pedido));
reset role;
select testes.entrar(testes.u('bruno'));
set local role authenticated;
select testes.def('vistos_bruno', (select count(*) from alertas_pedido));
reset role;
select testes.sair();
select ok(testes.v('vistos_ana') = '3' and testes.v('vistos_bruno') = '0', 'a cliente vê os alertas dos seus pedidos; outro cliente não');
select ok(exists (select 1 from notificacoes_por_enviar(1000) where codigo = 'N18')
          and exists (select 1 from notificacoes_por_enviar(1000) where codigo = 'N20'),
          'N18 a N20 seguem para envio');
select ok(exists (select 1 from auditoria where acao = 'atraso_informado' and funcionario_nome = 'Gerente Alexandra')
          and exists (select 1 from auditoria where acao = 'alerta_sem_confirmacao' and ref_id = testes.u('A')),
          'alertas e motivos ficam na auditoria (aparecem no histórico do pedido)');

select * from finish();
rollback;
