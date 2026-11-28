-- Pedidos de grupo em casa (família, vizinhos, igreja) e «cada um paga a sua parte» antes da entrega,
-- com confirmação das Finanças; «quem recebe paga tudo» na entrega.
begin;
\ir _helpers.psql
select plan(22);

select testes.funcionalidade('pedidos_grupo', true);
with z as (insert into zonas (nome, tipo, taxa) values ('Viana G', 'Própria', 1200) returning id)
select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Funge G', 3000) returning id) select testes.def('funge', id) from m;

select testes.def('ana', testes.cliente('Ana Organizadora'));
select testes.def('bia', testes.cliente('Bia Prima'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));

-- Grupos em casa: família (cada um paga) e vizinhos (quem recebe paga); a empresa continua a exigir Trabalho
select testes.entrar(testes.u('ana'));
set local role authenticated;
with g as (insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento, tipo)
           values (testes.u('casa'), now() + interval '3 hours', now() + interval '2 hours', 'individual', 'familia') returning id)
select testes.def('g_fam', id) from g;
with g as (insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento, tipo)
           values (testes.u('casa'), now() + interval '3 hours', now() + interval '2 hours', 'quem_recebe', 'vizinhos') returning id)
select testes.def('g_viz', id) from g;
select testes.def('e_emp', testes.erro(format($$insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
  values (%L, now() + interval '3 hours', now() + interval '2 hours', 'empresa')$$, testes.v('casa'))));
select testes.def('e_tipo', testes.erro(format($$insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento, tipo)
  values (%L, now() + interval '3 hours', now() + interval '2 hours', 'individual', 'festa')$$, testes.v('casa'))));
reset role;
select is((select tipo || '/' || modo_pagamento from pedidos_grupo where id = testes.u('g_fam')), 'familia/individual', 'grupo de família em casa');
select is((select tipo || '/' || modo_pagamento from pedidos_grupo where id = testes.u('g_viz')), 'vizinhos/quem_recebe', 'grupo de vizinhos: quem recebe paga');
select is(testes.v('e_emp'), 'P0001:grupo_ponto_invalido', 'pagamento da empresa só num local de trabalho');
select ok(testes.v('e_tipo') like '23514:%', 'tipo de grupo desconhecido é recusado');

-- A Bia junta-se aos dois grupos
select testes.entrar(testes.u('bia'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('bia'), testes.u('g_fam'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1)))
           returning id)
select testes.def('p_fam', id) from x;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('bia'), testes.u('g_viz'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1)))
           returning id)
select testes.def('p_viz', id) from x;
select testes.def('m0', meu_pagamento_antes(testes.u('p_fam'))::text);
select testes.def('e_viz', testes.erro(format($$select pagar_antes(%L, 'multicaixa_express', 'MCX-1234')$$, testes.v('p_viz'))));
select testes.def('e_ref', testes.erro(format($$select pagar_antes(%L, 'multicaixa_express', ' 12 ')$$, testes.v('p_fam'))));
select testes.def('e_met', testes.erro(format($$select pagar_antes(%L, 'dinheiro', 'MCX-1234')$$, testes.v('p_fam'))));
select testes.def('e_col', testes.erro(format($$update pedidos set pago_antes = 3000 where id = %L$$, testes.v('p_fam'))));
select testes.def('pag1', pagar_antes(testes.u('p_fam'), 'multicaixa_express', 'mcx 1234'));
select testes.def('e_dois', testes.erro(format($$select pagar_antes(%L, 'unitel_money', 'UM-9999')$$, testes.v('p_fam'))));
select testes.def('m1', meu_pagamento_antes(testes.u('p_fam'))::text);
select testes.def('e_lista_cli', testes.erro($$select pagamentos_antes_lista()$$));
reset role;
select testes.sair();

select is((testes.v('m0')::jsonb ->> 'pode')::boolean, true, 'família, cada um paga: pode pagar antes');
select is((testes.v('m0')::jsonb ->> 'falta')::int, 3000, 'falta pagar o prato (a taxa só se reparte no fecho)');
select is(testes.v('e_viz'), 'P0001:pagar_antes_indisponivel', 'quem recebe paga tudo: não há pagar antes');
select is(testes.v('e_ref'), 'P0001:referencia_invalida', 'referência curta é recusada');
select is(testes.v('e_met'), 'P0001:metodo_invalido', 'só Multicaixa Express ou Unitel Money');
select is((select pago_antes from pedidos where id = testes.u('p_fam')), 0, 'o cliente não escreve o pago antes directamente');
select is(testes.v('e_dois'), 'P0001:pagamento_ja_enviado', 'um pagamento de cada vez');
select is(testes.v('m1')::jsonb #>> '{ultimo,estado}', 'pendente', 'o cliente vê «a confirmar»');
select ok(testes.v('e_lista_cli') like '42501:%', 'o cliente não vê a lista das Finanças');

-- Finanças: rejeitar (com motivo), o cliente volta a enviar, confirmar
select testes.def('fin', testes.funcionario('Fina Finanças', array['financas.acertos']));
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('e_sem_motivo', testes.erro(format($$select decidir_pagamento_antes(%L, false)$$, testes.v('pag1'))));
select decidir_pagamento_antes(testes.u('pag1'), false, 'Não encontrámos esta referência no extracto');
reset role;
select testes.entrar(testes.u('bia'));
set local role authenticated;
select testes.def('pag2', pagar_antes(testes.u('p_fam'), 'multicaixa_express', 'MCX1234'));
reset role;
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select decidir_pagamento_antes(testes.u('pag2'), true);
select testes.def('lista', pagamentos_antes_lista()::text);
reset role;
select testes.sair();
select is(testes.v('e_sem_motivo'), 'P0001:motivo_obrigatorio', 'rejeitar exige o motivo');
select is((select pago_antes from pedidos where id = testes.u('p_fam')), 3000, 'confirmado: o pedido fica com 3.000 Kz pagos antes');
select is((select pedido_falta_pagar(p) from pedidos p where id = testes.u('p_fam')), 0, 'o estafeta já não tem nada a cobrar');
select is(jsonb_array_length(testes.v('lista')::jsonb), 2, 'a lista mostra o rejeitado e o confirmado');

-- Entrega sem cobrar nada: a venda leva «Pago antes»
update pedidos set caixa_id = testes.caixa(cozinha_id), estado = 'entregue_pago' where id = testes.u('p_fam');
select is((select estado from pedidos where id = testes.u('p_fam')), 'entregue_pago', 'entregue sem parcelas: já estava pago');
select is((select sum((x ->> 'valor')::int)::int from vendas v, jsonb_array_elements(v.parcelas) x
            where v.pedido_id = testes.u('p_fam') and x ->> 'metodo' = 'Pago antes'), 3000, 'a venda regista o «Pago antes»');

-- Pedido cancelado depois de pago antes: aparece para devolver
select testes.def('cid', testes.cliente('Cid Vizinho'));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('cid'), testes.u('casa'));
select testes.entrar(testes.u('cid'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('cid'), testes.u('g_fam'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('funge'), 'qtd', 1)))
           returning id)
select testes.def('p_cid', id) from x;
select testes.def('pag3', pagar_antes(testes.u('p_cid'), 'unitel_money', 'UM-777'));
select testes.def('e_reuso', testes.erro(format($$select pagar_antes(%L, 'unitel_money', 'MCX 1234')$$, testes.v('p_cid'))));
reset role;
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select decidir_pagamento_antes(testes.u('pag3'), true);
reset role;
update pedidos set estado = 'cancelado', motivo_cancelamento = 'Desistiu' where id = testes.u('p_cid');
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select testes.def('lista2', pagamentos_antes_lista()::text);
select devolver_pagamento_antes(testes.u('pag3'), 'UM-DEV-1');
reset role;
select testes.sair();
select is(testes.v('e_reuso'), 'P0001:pagamento_ja_enviado', 'um pagamento pendente de cada vez');
select is((select (x ->> 'a_devolver')::boolean from jsonb_array_elements(testes.v('lista2')::jsonb) x where x ->> 'id' = testes.v('pag3')),
          true, 'cancelado depois de pago: a devolver');
select is((select estado from pagamentos_antecipados where id = testes.u('pag3')), 'devolvido', 'devolução registada');

select * from finish();
rollback;
