-- Funções de apoio de I1 fora da secção 13: jobs, avaliações, grupos, locais,
-- métricas de turno e relatório de cozinha. Garantem que correm sem erro e
-- respeitam interruptores e permissões.
begin;
\ir _helpers.psql
select plan(19);

select testes.def('gil', testes.cliente('Gil Cliente'));
select testes.def('helena', testes.cliente('Helena Colega'));
select testes.def('alexandra', id) from cozinhas limit 1;

-- Jobs não fazem nada com os interruptores desligados
select job_n5_lembrete();
select job_n6_expiracao();
select job_n7_destaques();
select is((select count(*)::int from notificacoes_fila), 0, 'jobs inertes com interruptores desligados');

-- N6: indicado a 5 dias de expirar
select testes.funcionalidade('indicacao', true);
select testes.def('ivo', testes.indicado(testes.u('gil'), 'Ivo'));
update ligacoes_indicacao set expira_em = (hoje_luanda() + 5 + time '12:00') at time zone 'Africa/Luanda'
 where indicado_id = testes.u('ivo');
select job_n6_expiracao();
select job_n6_expiracao();
select is((select count(*)::int from notificacoes_fila where codigo = 'N6' and cliente_id = testes.u('gil')), 1,
          'N6 enfileirada uma só vez');

-- N5: só quem já partilhou e não desligou o lembrete
select testes.entrar(testes.u('gil'));
select registar_partilha();
select testes.sair();
select job_n5_lembrete();
select is((select count(*)::int from notificacoes_fila where codigo = 'N5'),
          case when extract(isodow from hoje_luanda()) between 1 and 5 then 1 else 0 end,
          'N5 só para quem partilhou (dias úteis)');

-- Locais próximos: sugere o local existente dentro do raio, sem referência residencial
select testes.def('casa', testes.ponto('residencial', -8.7000, 13.3000));
update pontos_entrega set referencia = 'Porta 12' where id = testes.u('casa');
select testes.entrar(testes.u('helena'));
select results_eq($$select ponto_entrega_id, referencia from pontos_entrega_proximos(-8.70005, 13.3000, 'residencial')$$,
                  format($$values (%L::uuid, null::text)$$, testes.u('casa')),
                  'pontos_entrega_proximos sugere o ponto e não expõe a referência residencial');
select testes.sair();

-- Clientes Empresa só com locais empresa
select testes.def('empresa', testes.cliente('Empresa Lda', 'Empresa'));
select throws_ok(format($$insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (%L, %L)$$, testes.u('empresa'), testes.u('casa')),
                 'P0001', 'empresa_requer_ponto_empresa', 'cliente Empresa não usa ponto residencial');

-- Avaliações: só com interruptor, pedido próprio entregue e dentro do prazo
select testes.def('ped', testes.pedido(testes.u('gil'), testes.u('casa')));
select testes.pagar(testes.u('ped'));
select testes.entrar(testes.u('gil'));
select is(avaliacao_permitida(testes.u('ped')), false, 'avaliação indisponível com interruptor desligado');
select testes.funcionalidade('avaliacoes', true);
select is(avaliacao_permitida(testes.u('ped')), true, 'avaliação permitida após entrega');
update pedidos set entregue_em = now() - interval '4 days' where id = testes.u('ped');
select is(avaliacao_permitida(testes.u('ped')), false, 'fora do prazo de 3 dias');
update pedidos set entregue_em = now() where id = testes.u('ped');
select testes.entrar(testes.u('helena'));
select is(avaliacao_permitida(testes.u('ped')), false, 'só o dono do pedido avalia');
select testes.sair();

insert into palavras_filtradas (palavra) values ('porcaria');
with a as (insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario)
           values (testes.u('ped'), testes.u('gil'), 2, 'Que porcaria de entrega') returning id)
select testes.def('aval', id) from a;
select results_eq(format($$select oculta, cozinha_id from avaliacoes where id = %L$$, testes.u('aval')),
                  format($$values (true, %L::uuid)$$, testes.u('alexandra')),
                  'filtro de palavras oculta o comentário; cozinha vem do pedido');
select is((select count(*)::int from media_avaliacoes_cozinha), 0, 'média só com o mínimo de avaliações');

-- Moderação exige permissão
select testes.def('moderador', testes.funcionario('Moderador', array['avaliacoes.moderar']));
select testes.entrar(testes.u('gil'));
select throws_ok(format($$select ocultar_avaliacao(%L, false)$$, testes.u('aval')), '42501', 'sem_permissao',
                 'cliente não modera avaliações');
select testes.entrar_funcionario(testes.u('moderador'));
select lives_ok(format($$select ocultar_avaliacao(%L, false)$$, testes.u('aval')), 'moderador mostra o comentário');
select testes.sair();

-- Grupos: interruptor desligado impede adesão
select testes.def('sede', testes.ponto('empresa'));
with g as (insert into pedidos_grupo (organizador_id, ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
           values (testes.u('gil'), testes.u('sede'), now() + interval '3 hours', now() + interval '2 hours', 'individual')
           returning id, codigo_convite)
select testes.def('grupo', id), testes.def('convite', codigo_convite) from g;
select matches(testes.v('convite')::text, '^G-[0-9A-F]{6}$', 'código de convite do grupo gerado');
select throws_ok(format($$insert into pedidos (cliente_id, grupo_id) values (%L, %L)$$, testes.u('helena'), testes.u('grupo')),
                 'P0001', 'funcionalidade_inactiva', 'pedidos de grupo desligados');
select testes.funcionalidade('pedidos_grupo', true);
with x as (insert into pedidos (cliente_id, grupo_id) values (testes.u('helena'), testes.u('grupo'))
           returning ponto_entrega_id)
select testes.def('ponto_grupo', ponto_entrega_id) from x;
select is(testes.u('ponto_grupo'), testes.u('sede')::uuid, 'pedido do grupo usa o ponto de entrega do grupo');
select is((select count(*)::int from notificacoes_fila where codigo = 'N10' and cliente_id = testes.u('gil')), 1,
          'N10 para o organizador');

-- Métricas de turno e relatório de cozinha (permissões e execução)
select testes.def('chefe', testes.funcionario('Chefe', array['equipa.reconhecer','relatorios.exportar']));
insert into turnos (funcionario_id, data, hora_inicio, hora_fim, periodo)
values (testes.u('chefe'), date_trunc('week', hoje_luanda())::date, '07:00', '15:00', 'manha');
select testes.entrar_funcionario(testes.u('chefe'));
select lives_ok(format($$select * from metricas_turno(%L, %L)$$, testes.u('alexandra'), date_trunc('week', hoje_luanda())::date),
                'metricas_turno executa');
select ok((relatorio_cozinha(testes.u('alexandra'), hoje_luanda() - 30, hoje_luanda()) ->> 'clientes_novos')::int >= 1,
          'relatorio_cozinha conta clientes novos');
select testes.sair();

select * from finish();
rollback;
