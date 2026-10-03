-- Secção 13 · Ganho (testes 9 a 21)
begin;
\ir _helpers.psql
select plan(30);
-- os limites por local seguem os valores por defeito (a produção pode ter outros)
update parametros set max_indicados_por_local = 3, max_descontos_por_local = 3, raio_mesmo_local_m = 25 where unico;

select testes.funcionalidade('indicacao', true);
select testes.def('ana', testes.cliente('Ana Indicadora'));

-- 9 e 11. Pedido pago dentro dos 60 dias; expira_em só no 1.º pedido pago
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno'));
select is((select expira_em from ligacoes_indicacao where indicado_id = testes.u('bruno')), null,
          '11. expira_em vazio no momento da ligação');
select testes.def('p9', testes.pedido(testes.u('bruno'), testes.ponto('residencial')));
select is((select expira_em from ligacoes_indicacao where indicado_id = testes.u('bruno')), null,
          '11. expira_em continua vazio com o pedido ainda por entregar');
select testes.pagar(testes.u('p9'));
select is((select expira_em from ligacoes_indicacao where indicado_id = testes.u('bruno')),
          (select entregue_em + interval '60 days' from pedidos where id = testes.u('p9')),
          '11. expira_em = entrega do 1.º pedido pago + 60 dias');
select is((select primeiro_pedido_id from ligacoes_indicacao where indicado_id = testes.u('bruno')), testes.u('p9')::uuid,
          '11. primeiro_pedido_id registado');
select results_eq(format($$select estado, valor, indicador_id from ganhos_indicacao where pedido_id = %L$$, testes.u('p9')),
                  format($$values ('confirmado'::text, 100, %L::uuid)$$, testes.u('ana')),
                  '9. pedido pago dentro do período -> ganho confirmado de 100 Kz');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('ana') and codigo = 'N3'), 1,
          '9. N3 na fila');

-- 12. Mesmo pedido a mudar de estado duas vezes -> um só ganho
select testes.pagar(testes.u('p9'));
update pedidos set estado = 'entregue_pago' where id = testes.u('p9');
select is((select count(*)::int from ganhos_indicacao where pedido_id = testes.u('p9')), 1,
          '12. mesmo pedido actualizado de novo -> um só ganho');
select throws_ok(format($$update pedidos set estado = 'pendente' where id = %L$$, testes.u('p9')),
                 'P0001', 'transicao_invalida', '12. pedido pago não volta atrás no ciclo');

-- 10. Pedido pago no dia 61 -> sem ganho
select testes.def('celia', testes.indicado(testes.u('ana'), 'Célia'));
select testes.def('p10a', testes.pedido(testes.u('celia'), testes.ponto('residencial')));
select testes.pagar(testes.u('p10a'));
-- simula que o 1.º pedido foi entregue há 61 dias
update pedidos set entregue_em = now() - interval '61 days' where id = testes.u('p10a');
update ligacoes_indicacao set expira_em = now() - interval '1 day' where indicado_id = testes.u('celia');
select testes.def('p10b', testes.pedido(testes.u('celia'), testes.ponto('residencial')));
select testes.pagar(testes.u('p10b'));
select is((select count(*)::int from ganhos_indicacao where pedido_id = testes.u('p10b')), 0,
          '10. pedido pago no dia 61 -> sem ganho');

-- 13. Mesmo dispositivo -> anulado / mesmo_dispositivo
select testes.def('p_ana', testes.pedido(testes.u('ana'), null, 'DISP-ANA-1'));
select testes.def('falsa', testes.indicado(testes.u('ana'), 'Conta Falsa'));
select testes.def('p13', testes.pedido(testes.u('falsa'), testes.ponto('residencial'), 'DISP-ANA-1'));
select testes.pagar(testes.u('p13'));
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, testes.u('p13')),
                  $$values ('anulado'::text, 'mesmo_dispositivo'::text)$$,
                  '13. mesmo dispositivo -> anulado / mesmo_dispositivo');

-- 14 e 15. Colegas de casa: 1.º a 3.º confirmados, 4.º em verificação
select testes.def('casa', testes.ponto('residencial', -8.9000, 13.1500));
select testes.def('casa_mesmo_predio', testes.ponto('residencial', -8.90012, 13.1500));
select testes.def('outro', testes.cliente('Outro Indicador'));
create temp table casa as
select n, testes.indicado(case when n % 2 = 0 then testes.u('ana')::uuid else testes.u('outro')::uuid end,
                          'Morador ' || n) as cliente,
          null::uuid as pedido
  from generate_series(1, 4) n;
update casa set pedido = testes.pedido(cliente, case when n = 4 then testes.u('casa_mesmo_predio')::uuid
                                                     else testes.u('casa')::uuid end,
                                        'DISP-CASA-' || n);
select testes.pagar(pedido) from (select pedido from casa order by n) s;
select is((select count(*)::int from casa c join ganhos_indicacao g on g.pedido_id = c.pedido
            where c.n <= 3 and g.estado = 'confirmado'), 3,
          '14. colegas de casa (mesmo local residencial), 1.º a 3.º -> confirmado');
select results_eq($$select g.estado, g.motivo from casa c join ganhos_indicacao g on g.pedido_id = c.pedido where c.n = 4$$,
                  $$values ('em_verificacao'::text, 'limite_local'::text)$$,
                  '15. 4.º indicado no mesmo local residencial -> em_verificacao / limite_local');

-- 16. Mesmo número de levantamento -> em_verificacao / numero_pagamento_partilhado
select testes.def('ind16', testes.cliente('Indicador Número'));
select testes.def('idd16', testes.indicado(testes.u('ind16'), 'Indicado Número'));
insert into pagamentos_indicacao (indicador_id, valor, tipo, metodo, numero_destino, estado)
values (testes.u('ind16'), 2000, 'levantamento', 'unitel_money', '923000111', 'rejeitado'),
       (testes.u('idd16'), 2000, 'levantamento', 'unitel_money', '923000111', 'rejeitado');
select testes.def('p16', testes.pedido(testes.u('idd16'), testes.ponto('empresa')));
select testes.pagar(testes.u('p16'));
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, testes.u('p16')),
                  $$values ('em_verificacao'::text, 'numero_pagamento_partilhado'::text)$$,
                  '16. mesmo número de levantamento -> em_verificacao / numero_pagamento_partilhado');

-- 17. Colegas de escritório (local empresa) -> confirmado, sem limite
select testes.def('escritorio', testes.ponto('empresa', -8.8300, 13.2400));
create temp table escritorio as
select n, testes.indicado(testes.u('ana'), 'Colega ' || n) as cliente, null::uuid as pedido
  from generate_series(1, 6) n;
update escritorio set pedido = testes.pedido(cliente, testes.u('escritorio'), 'DISP-ESC-' || n);
select testes.pagar(pedido) from (select pedido from escritorio order by n) s;
select is((select count(*)::int from escritorio e join ganhos_indicacao g on g.pedido_id = e.pedido
            where g.estado = 'confirmado'), 6,
          '17. 6 colegas de escritório (local empresa) -> todos confirmados');

-- 18. Soma semanal >= 10.000 Kz -> em_verificacao / limite_semanal; N4 só uma vez
select testes.def('forte', testes.cliente('Indicadora Forte'));
select testes.ganhos(testes.u('forte'), 100, 100);   -- 100 x 100 Kz = 10.000 Kz esta semana
select testes.def('a101', testes.indicado(testes.u('forte'), 'Amigo 101'));
select testes.def('a102', testes.indicado(testes.u('forte'), 'Amigo 102'));
select testes.def('p18a', testes.pedido(testes.u('a101'), testes.ponto('residencial')));
select testes.def('p18b', testes.pedido(testes.u('a102'), testes.ponto('residencial')));
select testes.pagar(testes.u('p18a'));
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, testes.u('p18a')),
                  $$values ('em_verificacao'::text, 'limite_semanal'::text)$$,
                  '18. soma semanal >= 10.000 Kz -> em_verificacao / limite_semanal');
select testes.pagar(testes.u('p18b'));
select is((select estado from ganhos_indicacao where pedido_id = testes.u('p18b')), 'em_verificacao',
          '18. ganho seguinte também em verificação');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('forte') and codigo = 'N4'), 1,
          '18. N4 só uma vez por semana');

-- 19. Embaixador acima de 10.000 Kz -> confirmado
select testes.def('emb', testes.cliente('Embaixadora'));
update codigos_indicacao set nivel = 'embaixador' where cliente_id = testes.u('emb');
select testes.ganhos(testes.u('emb'), 100, 100);
select testes.def('ae', testes.indicado(testes.u('emb'), 'Amigo E'));
select testes.def('p19', testes.pedido(testes.u('ae'), testes.ponto('residencial')));
select testes.pagar(testes.u('p19'));
select is((select estado from ganhos_indicacao where pedido_id = testes.u('p19')), 'confirmado',
          '19. embaixador acima de 10.000 Kz -> confirmado');

-- 20. Estorno: ganho confirmado -> anulado; ganho pago -> mantém-se
select testes.def('e1', testes.indicado(testes.u('ana'), 'Estorno Um'));
select testes.def('p20a', testes.pedido(testes.u('e1'), testes.ponto('residencial')));
select testes.pagar(testes.u('p20a'));
update pedidos set estado = 'estornado' where id = testes.u('p20a');
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, testes.u('p20a')),
                  $$values ('anulado'::text, 'pedido_estornado'::text)$$,
                  '20. estorno com ganho confirmado -> anulado / pedido_estornado');

select testes.def('e2', testes.indicado(testes.u('ana'), 'Estorno Dois'));
select testes.def('p20b', testes.pedido(testes.u('e2'), testes.ponto('residencial')));
select testes.pagar(testes.u('p20b'));
update ganhos_indicacao set estado = 'pago' where pedido_id = testes.u('p20b');
update pedidos set estado = 'estornado' where id = testes.u('p20b');
select is((select estado from ganhos_indicacao where pedido_id = testes.u('p20b')), 'pago',
          '20. estorno com ganho pago -> mantém-se pago');

-- 21. Interruptor desligado -> nenhum desconto, nenhum ganho
select testes.def('sp', testes.indicado(testes.u('ana'), 'Sem Programa'));
select testes.funcionalidade('indicacao', false);
select testes.def('p21', testes.pedido(testes.u('sp'), testes.ponto('residencial')));
select is((select desconto_indicacao from pedidos where id = testes.u('p21')), 0,
          '21. interruptor desligado -> nenhum desconto');
select testes.pagar(testes.u('p21'));
select is((select count(*)::int from ganhos_indicacao where pedido_id = testes.u('p21')), 0,
          '21. interruptor desligado -> nenhum ganho');
select testes.funcionalidade('indicacao', true);

-- Revisão de ganhos (6.6)
select testes.def('verif', testes.funcionario('Verificadora', array['indicacoes.verificar']));
select testes.def('semperm', testes.funcionario('Sem Permissão', array['indicacoes.ver']));
select testes.def('g18a', id) from ganhos_indicacao where pedido_id = testes.u('p18a');
select testes.def('g18b', id) from ganhos_indicacao where pedido_id = testes.u('p18b');

select testes.entrar_funcionario(testes.u('semperm'));
select throws_ok(format($$select rever_ganho(%L, 'confirmar')$$, testes.u('g18a')), '42501', 'sem_permissao',
                 'rever ganho exige indicacoes.verificar');
select testes.entrar_funcionario(testes.u('verif'));
select throws_ok(format($$select rever_ganho(%L, 'anular', '  ')$$, testes.u('g18a')), 'P0001', 'motivo_obrigatorio',
                 'anular exige motivo escrito');
select lives_ok(format($$select rever_ganho(%L, 'anular', 'Pedidos repetidos à mesma hora')$$, testes.u('g18a')),
                'anular com motivo escrito');
select results_eq(format($$select estado, motivo, nota_revisao from ganhos_indicacao where id = %L$$, testes.u('g18a')),
                  $$values ('anulado'::text, 'rejeitado_verificacao'::text, 'Pedidos repetidos à mesma hora'::text)$$,
                  'anulação por verificação guarda motivo');
select ok(exists (select 1 from auditoria where acao = 'ganho_indicacao_anulado' and ref_id = testes.u('g18a')
                    and detalhe like '%Pedidos repetidos%' and funcionario_nome = 'Verificadora'),
          'anulação por verificação fica na auditoria com o motivo');
select lives_ok(format($$select rever_ganho(%L, 'confirmar')$$, testes.u('g18b')), 'confirmar ganho em verificação');
select ok((select estado = 'confirmado' and confirmado_em is not null from ganhos_indicacao where id = testes.u('g18b')),
          'confirmar em verificação -> confirmado com confirmado_em');
select testes.sair();

-- Auditoria dos ganhos criados
select ok((select count(*) from auditoria where acao = 'ganho_indicacao_criado') >= 10,
          'criação de ganhos auditada');

select * from finish();
rollback;
