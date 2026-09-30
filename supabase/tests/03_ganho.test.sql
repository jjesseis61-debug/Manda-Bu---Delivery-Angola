-- Secção 13 · Ganho (testes 9 a 21)
begin;
\ir _helpers.psql
select plan(30);

select testes.funcionalidade('indicacao', true);
select testes.cliente('Ana Indicadora') as ana \gset

-- 9 e 11. Pedido pago dentro dos 60 dias; expira_em só no 1.º pedido pago
select testes.indicado(:'ana', 'Bruno') as bruno \gset
select is((select expira_em from ligacoes_indicacao where indicado_id = :'bruno'), null,
          '11. expira_em vazio no momento da ligação');
select testes.pedido(:'bruno', testes.local('residencial')) as p9 \gset
select is((select expira_em from ligacoes_indicacao where indicado_id = :'bruno'), null,
          '11. expira_em continua vazio com o pedido ainda por entregar');
select testes.pagar(:'p9');
select is((select expira_em from ligacoes_indicacao where indicado_id = :'bruno'),
          (select entregue_em + interval '60 days' from pedidos where id = :'p9'),
          '11. expira_em = entrega do 1.º pedido pago + 60 dias');
select is((select primeiro_pedido_id from ligacoes_indicacao where indicado_id = :'bruno'), :'p9'::uuid,
          '11. primeiro_pedido_id registado');
select results_eq(format($$select estado, valor, indicador_id from ganhos_indicacao where pedido_id = %L$$, :'p9'),
                  format($$values ('confirmado'::text, 100, %L::uuid)$$, :'ana'),
                  '9. pedido pago dentro do período -> ganho confirmado de 100 Kz');
select is((select count(*)::int from notificacoes_fila where cliente_id = :'ana' and codigo = 'N3'), 1,
          '9. N3 na fila');

-- 12. Mesmo pedido a mudar de estado duas vezes -> um só ganho
select testes.pagar(:'p9');
update pedidos set estado = 'entregue_pago' where id = :'p9';
select is((select count(*)::int from ganhos_indicacao where pedido_id = :'p9'), 1,
          '12. mesmo pedido actualizado de novo -> um só ganho');
select throws_ok(format($$update pedidos set estado = 'pendente' where id = %L$$, :'p9'),
                 'P0001', 'transicao_invalida', '12. pedido pago não volta atrás no ciclo');

-- 10. Pedido pago no dia 61 -> sem ganho
select testes.indicado(:'ana', 'Célia') as celia \gset
select testes.pedido(:'celia', testes.local('residencial')) as p10a \gset
select testes.pagar(:'p10a');
-- simula que o 1.º pedido foi entregue há 61 dias
update pedidos set entregue_em = now() - interval '61 days' where id = :'p10a';
update ligacoes_indicacao set expira_em = now() - interval '1 day' where indicado_id = :'celia';
select testes.pedido(:'celia', testes.local('residencial')) as p10b \gset
select testes.pagar(:'p10b');
select is((select count(*)::int from ganhos_indicacao where pedido_id = :'p10b'), 0,
          '10. pedido pago no dia 61 -> sem ganho');

-- 13. Mesmo dispositivo -> anulado / mesmo_dispositivo
select testes.pedido(:'ana', null, 'DISP-ANA-1') as p_ana \gset
select testes.indicado(:'ana', 'Conta Falsa') as falsa \gset
select testes.pedido(:'falsa', testes.local('residencial'), 'DISP-ANA-1') as p13 \gset
select testes.pagar(:'p13');
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, :'p13'),
                  $$values ('anulado'::text, 'mesmo_dispositivo'::text)$$,
                  '13. mesmo dispositivo -> anulado / mesmo_dispositivo');

-- 14 e 15. Colegas de casa: 1.º a 3.º confirmados, 4.º em verificação
select testes.local('residencial', -8.9000, 13.1500) as casa \gset
select testes.local('residencial', -8.90012, 13.1500) as casa_mesmo_predio \gset
select testes.cliente('Outro Indicador') as outro \gset
create temp table casa as
select n, testes.indicado(case when n % 2 = 0 then :'ana'::uuid else :'outro'::uuid end,
                          'Morador ' || n) as cliente,
          null::uuid as pedido
  from generate_series(1, 4) n;
update casa set pedido = testes.pedido(cliente, case when n = 4 then :'casa_mesmo_predio'::uuid
                                                     else :'casa'::uuid end,
                                        'DISP-CASA-' || n);
select testes.pagar(pedido) from (select pedido from casa order by n) s;
select is((select count(*)::int from casa c join ganhos_indicacao g on g.pedido_id = c.pedido
            where c.n <= 3 and g.estado = 'confirmado'), 3,
          '14. colegas de casa (mesmo local residencial), 1.º a 3.º -> confirmado');
select results_eq($$select g.estado, g.motivo from casa c join ganhos_indicacao g on g.pedido_id = c.pedido where c.n = 4$$,
                  $$values ('em_verificacao'::text, 'limite_local'::text)$$,
                  '15. 4.º indicado no mesmo local residencial -> em_verificacao / limite_local');

-- 16. Mesmo número de levantamento -> em_verificacao / numero_pagamento_partilhado
select testes.cliente('Indicador Número') as ind16 \gset
select testes.indicado(:'ind16', 'Indicado Número') as idd16 \gset
insert into pagamentos_indicacao (indicador_id, valor, tipo, metodo, numero_destino, estado)
values (:'ind16', 2000, 'levantamento', 'unitel_money', '923000111', 'rejeitado'),
       (:'idd16', 2000, 'levantamento', 'unitel_money', '923000111', 'rejeitado');
select testes.pedido(:'idd16', testes.local('empresa')) as p16 \gset
select testes.pagar(:'p16');
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, :'p16'),
                  $$values ('em_verificacao'::text, 'numero_pagamento_partilhado'::text)$$,
                  '16. mesmo número de levantamento -> em_verificacao / numero_pagamento_partilhado');

-- 17. Colegas de escritório (local empresa) -> confirmado, sem limite
select testes.local('empresa', -8.8300, 13.2400) as escritorio \gset
create temp table escritorio as
select n, testes.indicado(:'ana', 'Colega ' || n) as cliente, null::uuid as pedido
  from generate_series(1, 6) n;
update escritorio set pedido = testes.pedido(cliente, :'escritorio', 'DISP-ESC-' || n);
select testes.pagar(pedido) from (select pedido from escritorio order by n) s;
select is((select count(*)::int from escritorio e join ganhos_indicacao g on g.pedido_id = e.pedido
            where g.estado = 'confirmado'), 6,
          '17. 6 colegas de escritório (local empresa) -> todos confirmados');

-- 18. Soma semanal >= 10.000 Kz -> em_verificacao / limite_semanal; N4 só uma vez
select testes.cliente('Indicadora Forte') as forte \gset
select testes.ganhos(:'forte', 100, 100);   -- 100 x 100 Kz = 10.000 Kz esta semana
select testes.indicado(:'forte', 'Amigo 101') as a101 \gset
select testes.indicado(:'forte', 'Amigo 102') as a102 \gset
select testes.pedido(:'a101', testes.local('residencial')) as p18a \gset
select testes.pedido(:'a102', testes.local('residencial')) as p18b \gset
select testes.pagar(:'p18a');
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, :'p18a'),
                  $$values ('em_verificacao'::text, 'limite_semanal'::text)$$,
                  '18. soma semanal >= 10.000 Kz -> em_verificacao / limite_semanal');
select testes.pagar(:'p18b');
select is((select estado from ganhos_indicacao where pedido_id = :'p18b'), 'em_verificacao',
          '18. ganho seguinte também em verificação');
select is((select count(*)::int from notificacoes_fila where cliente_id = :'forte' and codigo = 'N4'), 1,
          '18. N4 só uma vez por semana');

-- 19. Embaixador acima de 10.000 Kz -> confirmado
select testes.cliente('Embaixadora') as emb \gset
update codigos_indicacao set nivel = 'embaixador' where cliente_id = :'emb';
select testes.ganhos(:'emb', 100, 100);
select testes.indicado(:'emb', 'Amigo E') as ae \gset
select testes.pedido(:'ae', testes.local('residencial')) as p19 \gset
select testes.pagar(:'p19');
select is((select estado from ganhos_indicacao where pedido_id = :'p19'), 'confirmado',
          '19. embaixador acima de 10.000 Kz -> confirmado');

-- 20. Estorno: ganho confirmado -> anulado; ganho pago -> mantém-se
select testes.indicado(:'ana', 'Estorno Um') as e1 \gset
select testes.pedido(:'e1', testes.local('residencial')) as p20a \gset
select testes.pagar(:'p20a');
update pedidos set estado = 'estornado' where id = :'p20a';
select results_eq(format($$select estado, motivo from ganhos_indicacao where pedido_id = %L$$, :'p20a'),
                  $$values ('anulado'::text, 'pedido_estornado'::text)$$,
                  '20. estorno com ganho confirmado -> anulado / pedido_estornado');

select testes.indicado(:'ana', 'Estorno Dois') as e2 \gset
select testes.pedido(:'e2', testes.local('residencial')) as p20b \gset
select testes.pagar(:'p20b');
update ganhos_indicacao set estado = 'pago' where pedido_id = :'p20b';
update pedidos set estado = 'estornado' where id = :'p20b';
select is((select estado from ganhos_indicacao where pedido_id = :'p20b'), 'pago',
          '20. estorno com ganho pago -> mantém-se pago');

-- 21. Interruptor desligado -> nenhum desconto, nenhum ganho
select testes.indicado(:'ana', 'Sem Programa') as sp \gset
select testes.funcionalidade('indicacao', false);
select testes.pedido(:'sp', testes.local('residencial')) as p21 \gset
select is((select desconto_indicacao from pedidos where id = :'p21'), 0,
          '21. interruptor desligado -> nenhum desconto');
select testes.pagar(:'p21');
select is((select count(*)::int from ganhos_indicacao where pedido_id = :'p21'), 0,
          '21. interruptor desligado -> nenhum ganho');
select testes.funcionalidade('indicacao', true);

-- Revisão de ganhos (6.6)
select testes.funcionario('Verificadora', array['indicacoes.verificar']) as verif \gset
select testes.funcionario('Sem Permissão', array['indicacoes.ver']) as semperm \gset
select id as g18a from ganhos_indicacao where pedido_id = :'p18a' \gset
select id as g18b from ganhos_indicacao where pedido_id = :'p18b' \gset

select testes.entrar_funcionario(:'semperm');
select throws_ok(format($$select rever_ganho(%L, 'confirmar')$$, :'g18a'), '42501', 'sem_permissao',
                 'rever ganho exige indicacoes.verificar');
select testes.entrar_funcionario(:'verif');
select throws_ok(format($$select rever_ganho(%L, 'anular', '  ')$$, :'g18a'), 'P0001', 'motivo_obrigatorio',
                 'anular exige motivo escrito');
select lives_ok(format($$select rever_ganho(%L, 'anular', 'Pedidos repetidos à mesma hora')$$, :'g18a'),
                'anular com motivo escrito');
select results_eq(format($$select estado, motivo, nota_revisao from ganhos_indicacao where id = %L$$, :'g18a'),
                  $$values ('anulado'::text, 'rejeitado_verificacao'::text, 'Pedidos repetidos à mesma hora'::text)$$,
                  'anulação por verificação guarda motivo');
select ok(exists (select 1 from auditoria where acao = 'ganho_indicacao_anulado' and ref_id = :'g18a'
                    and detalhe like '%Pedidos repetidos%' and funcionario_nome = 'Verificadora'),
          'anulação por verificação fica na auditoria com o motivo');
select lives_ok(format($$select rever_ganho(%L, 'confirmar')$$, :'g18b'), 'confirmar ganho em verificação');
select ok((select estado = 'confirmado' and confirmado_em is not null from ganhos_indicacao where id = :'g18b'),
          'confirmar em verificação -> confirmado com confirmado_em');
select testes.sair();

-- Auditoria dos ganhos criados
select ok((select count(*) from auditoria where acao = 'ganho_indicacao_criado') >= 10,
          'criação de ganhos auditada');

select * from finish();
rollback;
