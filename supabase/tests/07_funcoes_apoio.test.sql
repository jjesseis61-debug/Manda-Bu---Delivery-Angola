-- Funções de apoio de I1 fora da secção 13: jobs, avaliações, grupos, locais,
-- métricas de turno e relatório de cozinha. Garantem que correm sem erro e
-- respeitam interruptores e permissões.
begin;
\ir _helpers.psql
select plan(19);

select testes.cliente('Gil Cliente') as gil \gset
select testes.cliente('Helena Colega') as helena \gset
select id as alexandra from cozinhas limit 1 \gset

-- Jobs não fazem nada com os interruptores desligados
select job_n5_lembrete();
select job_n6_expiracao();
select job_n7_destaques();
select is((select count(*)::int from notificacoes_fila), 0, 'jobs inertes com interruptores desligados');

-- N6: indicado a 5 dias de expirar
select testes.funcionalidade('indicacao', true);
select testes.indicado(:'gil', 'Ivo') as ivo \gset
update ligacoes_indicacao set expira_em = (hoje_luanda() + 5 + time '12:00') at time zone 'Africa/Luanda'
 where indicado_id = :'ivo';
select job_n6_expiracao();
select job_n6_expiracao();
select is((select count(*)::int from notificacoes_fila where codigo = 'N6' and cliente_id = :'gil'), 1,
          'N6 enfileirada uma só vez');

-- N5: só quem já partilhou e não desligou o lembrete
select testes.entrar(:'gil');
select registar_partilha();
select testes.sair();
select job_n5_lembrete();
select is((select count(*)::int from notificacoes_fila where codigo = 'N5'),
          case when extract(isodow from hoje_luanda()) between 1 and 5 then 1 else 0 end,
          'N5 só para quem partilhou (dias úteis)');

-- Locais próximos: sugere o local existente dentro do raio, sem referência residencial
select testes.local('residencial', -8.7000, 13.3000) as casa \gset
update locais_entrega set referencia = 'Porta 12' where id = :'casa';
select testes.entrar(:'helena');
select results_eq($$select local_id, referencia from locais_proximos(-8.70005, 13.3000, 'residencial')$$,
                  format($$values (%L::uuid, null::text)$$, :'casa'),
                  'locais_proximos sugere o local e não expõe a referência residencial');
select testes.sair();

-- Clientes Empresa só com locais empresa
select testes.cliente('Empresa Lda', 'Empresa') as empresa \gset
select throws_ok(format($$insert into enderecos_cliente (cliente_id, local_id) values (%L, %L)$$, :'empresa', :'casa'),
                 'P0001', 'empresa_requer_local_empresa', 'cliente Empresa não usa local residencial');

-- Avaliações: só com interruptor, pedido próprio entregue e dentro do prazo
select testes.pedido(:'gil', :'casa') as ped \gset
select testes.pagar(:'ped');
select testes.entrar(:'gil');
select is(avaliacao_permitida(:'ped'), false, 'avaliação indisponível com interruptor desligado');
select testes.funcionalidade('avaliacoes', true);
select is(avaliacao_permitida(:'ped'), true, 'avaliação permitida após entrega');
update pedidos set entregue_em = now() - interval '4 days' where id = :'ped';
select is(avaliacao_permitida(:'ped'), false, 'fora do prazo de 3 dias');
update pedidos set entregue_em = now() where id = :'ped';
select testes.entrar(:'helena');
select is(avaliacao_permitida(:'ped'), false, 'só o dono do pedido avalia');
select testes.sair();

insert into palavras_filtradas (palavra) values ('porcaria');
insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario)
values (:'ped', :'gil', 2, 'Que porcaria de entrega') returning id as aval \gset
select results_eq(format($$select oculta, cozinha_id from avaliacoes where id = %L$$, :'aval'),
                  format($$values (true, %L::uuid)$$, :'alexandra'),
                  'filtro de palavras oculta o comentário; cozinha vem do pedido');
select is((select count(*)::int from media_avaliacoes_cozinha), 0, 'média só com o mínimo de avaliações');

-- Moderação exige permissão
select testes.funcionario('Moderador', array['avaliacoes.moderar']) as moderador \gset
select testes.entrar(:'gil');
select throws_ok(format($$select ocultar_avaliacao(%L, false)$$, :'aval'), '42501', 'sem_permissao',
                 'cliente não modera avaliações');
select testes.entrar_funcionario(:'moderador');
select lives_ok(format($$select ocultar_avaliacao(%L, false)$$, :'aval'), 'moderador mostra o comentário');
select testes.sair();

-- Grupos: interruptor desligado impede adesão
select testes.local('empresa') as sede \gset
insert into pedidos_grupo (organizador_id, local_id, hora_entrega, prazo_adesao, modo_pagamento)
values (:'gil', :'sede', now() + interval '3 hours', now() + interval '2 hours', 'individual')
returning id as grupo, codigo_convite as convite \gset
select matches(:'convite'::text, '^G-[0-9A-F]{6}$', 'código de convite do grupo gerado');
select throws_ok(format($$insert into pedidos (cliente_id, grupo_id) values (%L, %L)$$, :'helena', :'grupo'),
                 'P0001', 'funcionalidade_inactiva', 'pedidos de grupo desligados');
select testes.funcionalidade('pedidos_grupo', true);
insert into pedidos (cliente_id, grupo_id) values (:'helena', :'grupo') returning local_id as local_grupo \gset
select is(:'local_grupo'::uuid, :'sede'::uuid, 'pedido do grupo usa o local do grupo');
select is((select count(*)::int from notificacoes_fila where codigo = 'N10' and cliente_id = :'gil'), 1,
          'N10 para o organizador');

-- Métricas de turno e relatório de cozinha (permissões e execução)
select testes.funcionario('Chefe', array['equipa.reconhecer','relatorios.exportar']) as chefe \gset
insert into turnos (funcionario_id, data, hora_inicio, hora_fim, periodo)
values (:'chefe', date_trunc('week', hoje_luanda())::date, '07:00', '15:00', 'manha');
select testes.entrar_funcionario(:'chefe');
select lives_ok(format($$select * from metricas_turno(%L, %L)$$, :'alexandra', date_trunc('week', hoje_luanda())::date),
                'metricas_turno executa');
select ok((relatorio_cozinha(:'alexandra', hoje_luanda() - 30, hoje_luanda()) ->> 'clientes_novos')::int >= 1,
          'relatorio_cozinha conta clientes novos');
select testes.sair();

select * from finish();
rollback;
