-- Segurança do Convida e Ganha e dos pagamentos na entrega: comprovativo dos pagamentos electrónicos
-- (referência + foto, conferido antes de fechar a caixa), levantamento só para quem já comprou,
-- desconto só a partir do subtotal mínimo e limite por morada contado por quem convida
begin;
\ir _helpers.psql
select plan(27);

select testes.funcionalidade('indicacao', true);
select testes.funcionalidade('multi_cozinha', false);
update parametros set max_indicados_por_local = 3, max_descontos_por_local = 3, raio_mesmo_local_m = 25 where unico;
select testes.def('cz', cozinha_padrao());
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir', 'vendas.registar']));
select testes.def('estafeta', testes.funcionario('Estafeta', array['entregas.registar']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), testes.u('cz')),
                                                           (current_date, testes.u('estafeta'), testes.u('cz'));
select testes.def('cx', testes.caixa(testes.u('cz'), 'Balcão de teste'));
select testes.def('ana', testes.cliente('Ana Sousa'));

-- ---------------------------------------------------------------- comprovativos na entrega
create temp table ped as
select n, testes.pedido(testes.u('ana'), testes.ponto('residencial')) as id from generate_series(1, 4) n;
update pedidos set estado = 'em_entrega' where id in (select id from ped);
select testes.def('p1', id) from ped where n = 1;
select testes.def('p2', id) from ped where n = 2;
select testes.def('p3', id) from ped where n = 3;

-- o estafeta envia a foto do comprovativo de um pedido em entrega; não de um pedido que não existe
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('foto_ok', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('comprovativos', '%s/mcx-1.jpg')$$, testes.v('p1'))));
select testes.def('foto_inexistente', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('comprovativos', '%s/x.jpg')$$, gen_random_uuid())));
select testes.def('foto_ext', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('comprovativos', '%s/x.exe')$$, testes.v('p1'))));
reset role;
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('foto_cliente', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('comprovativos', '%s/c.jpg')$$, testes.v('p1'))));
reset role;
select testes.sair();
select is(testes.v('foto_ok'), 'sem_erro', 'o estafeta envia a foto do comprovativo do pedido em entrega');
select ok(testes.v('foto_inexistente') like '42501:%' and testes.v('foto_ext') like '42501:%',
          'não envia para um pedido que não existe nem ficheiros que não são imagens');
select ok(testes.v('foto_cliente') like '42501:%', 'o cliente não envia comprovativos');

select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('e_sem_ref', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
  testes.v('p1'), testes.v('cx'), jsonb_build_array(jsonb_build_object('metodo', 'Multicaixa Express', 'valor', 3000)))));
select testes.def('e_sem_foto', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
  testes.v('p1'), testes.v('cx'), jsonb_build_array(jsonb_build_object('metodo', 'Unitel Money', 'valor', 3000, 'referencia', 'UM-55120')))));
select testes.def('e_foto_alheia', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
  testes.v('p2'), testes.v('cx'), jsonb_build_array(jsonb_build_object('metodo', 'TPA', 'valor', 3000, 'referencia', 'TPA-0091',
                                                                       'comprovativo', testes.v('p1') || '/mcx-1.jpg')))));
select testes.def('e_metodo', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
  testes.v('p2'), testes.v('cx'), jsonb_build_array(jsonb_build_object('metodo', 'dinheiro', 'valor', 3000)))));
select testes.def('ok_p1', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
  testes.v('p1'), testes.v('cx'), jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', 1000),
                                                    jsonb_build_object('metodo', 'Multicaixa Express', 'valor', 2000,
                                                                       'referencia', ' mcx 4471 ', 'comprovativo', testes.v('p1') || '/mcx-1.jpg')))));
reset role;
select testes.def('k1', id) from comprovativos_pagamento where pedido_id = testes.u('p1');
select is(testes.v('e_sem_ref'), 'P0001:referencia_obrigatoria', 'pagamento electrónico sem referência -> recusado');
select is(testes.v('e_sem_foto'), 'P0001:comprovativo_obrigatorio', 'com referência mas sem foto do comprovativo -> recusado');
select is(testes.v('e_foto_alheia'), 'P0001:comprovativo_obrigatorio', 'a foto de outro pedido não serve');
select is(testes.v('e_metodo'), 'P0001:metodo_invalido', 'forma de pagamento fora da lista -> recusada (não escapa à caixa)');
select is(testes.v('ok_p1'), 'sem_erro', 'Dinheiro + Multicaixa com referência e foto -> entregue e pago');
select results_eq(format($$select metodo, valor::int, referencia, estado, registado_por from comprovativos_pagamento where pedido_id = %L$$, testes.v('p1')),
                  format($$values ('Multicaixa Express'::text, 2000, 'mcx 4471'::text, 'por_conferir'::text, %L::uuid)$$, testes.v('estafeta')),
                  'fica registado para conferir (só a parcela electrónica, com quem a registou)');

-- a mesma referência não serve para outro pedido (mesmo com espaços ou maiúsculas diferentes)
insert into storage.objects (bucket_id, name) values ('comprovativos', testes.v('p2') || '/mcx-2.jpg');
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('e_repetida', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
  testes.v('p2'), testes.v('cx'), jsonb_build_array(jsonb_build_object('metodo', 'Multicaixa Express', 'valor', 3000,
                                                                       'referencia', 'MCX4471', 'comprovativo', testes.v('p2') || '/mcx-2.jpg')))));
select testes.def('ok_p2', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, %L)$$,
  testes.v('p2'), testes.v('cx'), jsonb_build_array(jsonb_build_object('metodo', 'Multicaixa Express', 'valor', 3000,
                                                                       'referencia', 'MCX4472', 'comprovativo', testes.v('p2') || '/mcx-2.jpg')))));
select testes.def('e_tabela', testes.erro(format($$update comprovativos_pagamento set estado = 'conferido' where pedido_id = %L$$, testes.v('p1'))));
select testes.def('e_conferir_estafeta', testes.erro(format($$select conferir_comprovativo(%L, true)$$, testes.v('k1'))));
reset role;
select testes.def('k2', id) from comprovativos_pagamento where pedido_id = testes.u('p2');
select is(testes.v('e_repetida'), 'P0001:referencia_repetida', 'a mesma referência noutro pedido -> recusada');
select is(testes.v('ok_p2'), 'sem_erro', 'outra referência -> aceite');
select ok(testes.v('e_tabela') like '42501:%' and testes.v('e_conferir_estafeta') like '42501:%sem_permissao%',
          'o estafeta não confere nem altera comprovativos');

-- conferência no fecho da caixa
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('res', resumo_caixa(testes.u('cx')));
select testes.def('e_fechar', testes.erro(format($$select fechar_caixa(%L, 1000)$$, testes.v('cx'))));
select testes.def('e_nota', testes.erro(format($$select conferir_comprovativo(%L, false, '  ')$$,
  testes.v('k2'))));
select conferir_comprovativo(testes.u('k1'), true);
select conferir_comprovativo(testes.u('k2'), false,
                             'Referência não aparece no extracto');
select testes.def('vistos', (select count(*) from comprovativos_pagamento));
select testes.def('fecho', fechar_caixa(testes.u('cx'), 1000));
select testes.def('e_depois', testes.erro(format($$select conferir_comprovativo(%L, true)$$, testes.v('k2'))));
reset role;
select ok((testes.v('res')::jsonb ->> 'electronico')::numeric = 5000 and (testes.v('res')::jsonb ->> 'por_conferir')::int = 2
          and jsonb_array_length(testes.v('res')::jsonb -> 'comprovativos') = 2
          and (testes.v('res')::jsonb -> 'comprovativos' -> 0 ->> 'caminho') = testes.v('p1') || '/mcx-1.jpg',
          'o resumo da caixa lista os pagamentos electrónicos com referência e foto');
select is((testes.v('res')::jsonb ->> 'esperado')::numeric, 1000::numeric, 'o dinheiro esperado continua a ser só o Dinheiro');
select ok(testes.v('e_fechar') like 'P0001:comprovativos_por_conferir%', 'não fecha a caixa com pagamentos por conferir');
select is(testes.v('e_nota'), 'P0001:nota_obrigatoria', 'rejeitar exige uma nota');
select is(testes.v('vistos'), '2', 'o gerente vê os comprovativos da sua cozinha');
select ok((testes.v('fecho')::jsonb ->> 'por_conferir')::int = 0 and (testes.v('fecho')::jsonb ->> 'rejeitados')::int = 1
          and (testes.v('fecho')::jsonb ->> 'valor_rejeitado')::numeric = 3000 and not (testes.v('fecho')::jsonb ? 'comprovativos'),
          'depois de conferir fecha; o fecho guarda o pagamento rejeitado (3 000 Kz)');
select ok(testes.v('e_depois') like '%caixa_fechada%', 'com a caixa fechada já não se muda a conferência');
select ok((select count(*) from auditoria where acao in ('comprovativo_conferido', 'comprovativo_rejeitado')) = 2
          and exists (select 1 from auditoria where acao = 'comprovativo_rejeitado' and detalhe like '%extracto%'),
          'conferência e rejeição (com a nota) na auditoria');

-- ---------------------------------------------------------------- levantamento só para quem já comprou
update parametros set levantamento_minimo = 100 where unico;
select testes.def('rui', testes.cliente('Rui Indicador'));
select testes.ganhos(testes.u('rui'), 5, 100, now() - interval '1 hour');
select testes.entrar(testes.u('rui'));
select testes.def('e_lev', testes.erro($$select pedir_levantamento(300, 'unitel_money', '923400001')$$));
select testes.sair();
select testes.pagar(testes.pedido(testes.u('rui'), testes.ponto('residencial')));
select testes.entrar(testes.u('rui'));
select testes.def('ok_lev', testes.erro($$select pedir_levantamento(300, 'unitel_money', '923400001')$$));
select testes.sair();
select is(testes.v('e_lev'), 'P0001:sem_compra_propria', 'quem nunca comprou não levanta o dinheiro das indicações');
select is(testes.v('ok_lev'), 'sem_erro', 'depois de um pedido seu entregue e pago já levanta');

-- ---------------------------------------------------------------- desconto só a partir do subtotal mínimo
with z as (insert into zonas (nome, tipo, taxa) values ('Viana', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Arroz', 1000) returning id) select testes.def('arroz', id) from m;
with m as (insert into cardapio (nome, preco) values ('Chocos', 6000) returning id) select testes.def('chocos', id) from m;
select testes.def('bea', testes.indicado(testes.u('rui'), 'Beatriz'));
select testes.def('casa_bea', testes.ponto('residencial', -8.95, 13.30, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('bea'), testes.u('casa_bea'));
select testes.entrar(testes.u('bea'));
select testes.def('orc_pequeno', orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('arroz'), 'qtd', 1)), testes.u('casa_bea')));
select testes.def('orc_grande', orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('arroz'), 'qtd', 2)), testes.u('casa_bea')));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('bea'), testes.u('casa_bea'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('arroz'), 'qtd', 1))) returning id)
select testes.def('pp', id) from x;
reset role;
select testes.sair();
select ok((testes.v('orc_pequeno')::jsonb ->> 'desconto')::int = 0 and testes.v('orc_pequeno')::jsonb ->> 'motivo_desconto' = 'pedido_minimo'
          and (testes.v('orc_pequeno')::jsonb ->> 'desconto_subtotal_minimo')::int = 2000,
          'orçamento de 1 000 Kz: sem desconto, com o motivo e o mínimo (2 000 Kz) para a app explicar');
select ok((testes.v('orc_grande')::jsonb ->> 'desconto')::int = 500 and testes.v('orc_grande')::jsonb ->> 'motivo_desconto' = 'ok',
          'orçamento de 2 000 Kz: desconto de 500 Kz');
select is((select desconto_indicacao::int from pedidos where id = testes.u('pp')), 0, 'o pedido abaixo do mínimo fica sem desconto no servidor');

-- ---------------------------------------------------------------- limite por morada contado por quem convida
update parametros set desconto_subtotal_minimo = 0 where unico;
select testes.def('predio', testes.ponto('residencial', -8.90, 13.20));
select testes.def('vizinho', testes.cliente('Vizinho Indicador'));
create temp table amigos_rui as
select n, testes.indicado(testes.u('rui'), 'Amigo ' || n) as cliente from generate_series(1, 4) n;
select testes.pagar(testes.pedido(cliente, testes.u('predio'))) from amigos_rui where n <= 3;
select testes.def('quarto', testes.pedido(cliente, testes.u('predio'))) from amigos_rui where n = 4;
select testes.def('do_vizinho', testes.pedido(testes.indicado(testes.u('vizinho'), 'Amiga do vizinho'), testes.u('predio')));
select is((select desconto_indicacao::int from pedidos where id = testes.u('quarto')), 0,
          '4.º amigo da mesma pessoa no mesmo prédio -> sem desconto');
select is((select desconto_indicacao::int from pedidos where id = testes.u('do_vizinho')), 500,
          'amiga de outra pessoa no mesmo prédio -> com desconto (vizinhos não se bloqueiam)');

select * from finish();
rollback;
