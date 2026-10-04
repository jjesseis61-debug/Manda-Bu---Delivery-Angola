-- N16 (estado do pedido ao cliente), N17 (pedido novo à cozinha) e segredo do envio
begin;
\ir _helpers.psql
select plan(13);

select testes.funcionalidade('multi_cozinha', false);
select testes.def('cz', cozinha_padrao());
with z as (insert into zonas (nome, tipo, taxa) values ('Viana', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Chocos', 6000) returning id) select testes.def('chocos', id) from m;
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir', 'vendas.registar']));
select testes.def('outro', testes.funcionario('Gerente doutra cozinha', array['pedidos.gerir']));
with c as (insert into cozinhas (nome, responsavel) values ('Cozinha do Kilamba', 'Rosa') returning id) select testes.def('outra', id) from c;
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), testes.u('cz')),
                                                           (current_date, testes.u('outro'), testes.u('outra'));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('ponto', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('ponto'));

-- Pedido novo: aviso à cozinha
select testes.entrar(testes.u('ana'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('ana'), testes.u('ponto'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 2))) returning id)
select testes.def('p', id) from x;
reset role;
select testes.sair();
select is((select count(*)::int from notificacoes_fila where codigo = 'N17' and funcionario_id = testes.u('gerente')), 1,
          'N17: o gerente da cozinha é avisado do pedido novo');
select is((select count(*)::int from notificacoes_fila where codigo = 'N17' and funcionario_id = testes.u('outro')), 0,
          'N17: o gerente de outra cozinha não');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N17' and funcionario_id = testes.u('gerente')),
          format('Novo pedido: 2× Chocos · Viana · %s.', formatar_kz(13000)), 'N17: pratos, bairro e total');

-- Estados: confirmado, saiu, entregue
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select mudar_estado_pedido(testes.u('p'), 'confirmado', null, null, null);
select mudar_estado_pedido(testes.u('p'), 'em_preparacao', null, null, null);
select mudar_estado_pedido(testes.u('p'), 'em_entrega', null, null, null);
reset role;
select testes.pagar(testes.u('p'));
select is((select array_agg(dados ->> 'estado' order by criado_em, dados ->> 'estado') from notificacoes_fila where codigo = 'N16' and cliente_id = testes.u('ana')),
          array['confirmado', 'em_entrega', 'entregue_pago'], 'N16: confirmado, saiu para entrega e entregue (em preparação não avisa)');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N16' and dados ->> 'estado' = 'confirmado'),
          format('A %s recebeu o teu pedido e já o está a preparar.', (select trim(nome) from cozinhas where id = testes.u('cz'))),
          'N16: texto do confirmado com o nome da cozinha');
select is((select dados ->> 'pedido_id' from notificacoes_fila where codigo = 'N16' and dados ->> 'estado' = 'em_entrega'),
          testes.v('p'), 'N16 leva o pedido para a app abrir o ecrã do pedido');

-- Cancelamentos: pela cliente (sem aviso) e pela cozinha (com motivo)
select testes.entrar(testes.u('ana'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('ana'), testes.u('ponto'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 1))) returning id)
select testes.def('p2', id) from x;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('ana'), testes.u('ponto'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 1))) returning id)
select testes.def('p3', id) from x;
select cancelar_pedido(testes.u('p2'), 'Mudei de ideias');
reset role;
select testes.sair();
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select mudar_estado_pedido(testes.u('p3'), 'cancelado', 'Acabou o peixe', null, null);
reset role;
select testes.sair();   -- o corpo da N16 é construído pelo envio (serviço), não por uma sessão de cliente
select is((select count(*)::int from notificacoes_fila where codigo = 'N16' and dados ->> 'pedido_id' = testes.v('p2')), 0,
          'a cliente que cancela não recebe aviso');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N16' and dados ->> 'pedido_id' = testes.v('p3')),
          'Lamentamos: tivemos de cancelar o teu pedido de Chocos pelo seguinte motivo: acabou o peixe. Não tens nada a pagar.',
          'cancelado pela cozinha: assume, diz o prato e o motivo, e que não há nada a pagar');

-- Envio: N16/N17 saem sem interruptor; ficam velhos ao fim de 2 horas
select ok(exists (select 1 from notificacoes_por_enviar(1000) where codigo = 'N16')
          and exists (select 1 from notificacoes_por_enviar(1000) where codigo = 'N17'), 'N16 e N17 seguem para envio sem interruptor');
select ok(not notificacao_valida('N16', now() - interval '3 hours'), 'aviso de estado com mais de 2 horas já não se envia');

-- Pedido de grupo não avisa a cozinha um a um
select testes.funcionalidade('pedidos_grupo', true);
select testes.def('esc', testes.ponto('empresa', -8.83, 13.24, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('esc'));
select testes.entrar(testes.u('ana'));
set local role authenticated;
with g as (insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
           values (testes.u('esc'), now() + interval '3 hours', now() + interval '2 hours', 'individual') returning id)
select testes.def('g', id) from g;
insert into pedidos (cliente_id, grupo_id, itens) values (testes.u('ana'), testes.u('g'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('chocos'), 'qtd', 1)));
reset role;
select testes.sair();
select is((select count(*)::int from notificacoes_fila where codigo = 'N17' and funcionario_id = testes.u('gerente')), 3, 'pedido de grupo não gera N17 (só os 3 pedidos normais)');

-- Segredo do envio: só o servidor
select ok(segredo_envio_valido((select valor from segredos_servidor where chave = 'envio_notificacoes'))
          and not segredo_envio_valido('errado') and not segredo_envio_valido(''), 'o segredo do envio confere');
select ok(not has_function_privilege('authenticated', 'segredo_envio_valido(text)', 'execute')
          and not has_table_privilege('authenticated', 'segredos_servidor', 'select')
          and has_function_privilege('service_role', 'segredo_envio_valido(text)', 'execute'),
          'só o service_role confirma o segredo; ninguém o lê pela API');

select * from finish();
rollback;
