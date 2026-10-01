-- I2 · Servidor da app do cliente: registo, cardápio e preço no servidor,
-- amigos convidados, tokens de push e textos das notificações.
begin;
\ir _helpers.psql
select plan(37);

-- ---------------------------------------------------------------------------
-- 1. Registo do cliente
-- ---------------------------------------------------------------------------
select is(testes.erro($$select registar_cliente('Sem Sessão')$$), '42501:sem_sessao', 'registo exige sessão');

with u as (insert into auth.users (id, phone) values (gen_random_uuid(), '244923000111') returning id)
select testes.def('u_rui', id) from u;
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('e_empresa', testes.erro($$select registar_cliente('Rui Lda', 'Empresa')$$));
select testes.def('rui', registar_cliente('  Rui Manuel  '));
select testes.def('rui_2', registar_cliente('Outro Nome'));
select testes.def('perfil_rui', meu_perfil());
reset role;
select is(testes.v('e_empresa'), 'P0001:nif_obrigatorio', 'cliente Empresa exige NIF');
select results_eq(format($$select nome, telefone, tipo from clientes where id = %L$$, testes.u('rui')),
                  $$values ('Rui Manuel'::text, '923000111'::text, 'Particular'::text)$$,
                  'registo cria o cliente com o telefone confirmado (normalizado)');
select is(testes.u('rui_2'), testes.u('rui'), 'registar de novo devolve o mesmo cliente');
select ok(testes.v('perfil_rui')::jsonb ->> 'codigo' ~ '^MB-[0-9]{4,5}$'
          and testes.v('perfil_rui')::jsonb ->> 'primeiro_nome' = 'Rui'
          and (testes.v('perfil_rui')::jsonb ->> 'cliente_novo')::boolean,
          'meu_perfil: código, primeiro nome e cliente novo');

-- Cliente já registado pelo operador (sem utilizador) e com compras no sistema anterior
insert into clientes (nome, telefone) values ('Teresa Balcão', '923 000 222');
select testes.def('teresa', (select id from clientes where nome = 'Teresa Balcão'));
insert into vendas (cliente_id, valor_total) values (testes.u('teresa'), 1500);
with u as (insert into auth.users (id, phone) values (gen_random_uuid(), '+244 923 000 222') returning id)
select testes.def('u_teresa', id) from u;
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_teresa'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('teresa_app', registar_cliente('Teresa'));
select testes.def('perfil_teresa', meu_perfil());
reset role;
select is(testes.u('teresa_app'), testes.u('teresa'), 'telefone já conhecido: liga ao cliente existente, sem duplicar');
select is((select count(*)::int from clientes where normalizar_telefone(telefone) = '923000222'), 1, 'um só cliente com esse telefone');
select is((testes.v('perfil_teresa')::jsonb ->> 'cliente_novo')::boolean, false, 'histórico do balcão conta: cliente não novo');
select ok(exists (select 1 from codigos_indicacao where cliente_id = testes.u('teresa')), 'cliente ligado recebe código de convite');
select testes.sair();

-- ---------------------------------------------------------------------------
-- 2. Cardápio e preço calculado no servidor
-- ---------------------------------------------------------------------------
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Talatona', 'Própria', 700, 'Fixo') returning id)
select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco, do_dia) values ('Muamba de galinha', 2500, true) returning id)
select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco) values ('Sumo de múcua', 500) returning id)
select testes.def('sumo', id) from m;
with m as (insert into cardapio (nome, preco, disponivel) values ('Calulu', 3000, false) returning id)
select testes.def('calulu', id) from m;
select testes.def('casa_rui', testes.ponto('residencial', null, null, testes.u('zona')));
update pontos_entrega set criado_por_cliente = testes.u('rui') where id = testes.u('casa_rui');
select testes.def('sem_zona', testes.ponto('residencial'));
update pontos_entrega set criado_por_cliente = testes.u('rui') where id = testes.u('sem_zona');
select testes.def('ponto_alheio', testes.ponto('residencial', null, null, testes.u('zona')));

select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('orc', orcamento_pedido(jsonb_build_array(
         jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2),
         jsonb_build_object('cardapio_id', testes.u('sumo'), 'qtd', 1)), testes.u('casa_rui')));
with x as (
  insert into pedidos (cliente_id, ponto_entrega_id, itens, subtotal, taxa_entrega)
  values (testes.u('rui'), testes.u('casa_rui'),
          jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2, 'preco_unitario', 1, 'nome', 'Barato'),
                            jsonb_build_object('cardapio_id', testes.u('sumo'), 'qtd', 1, 'preco_unitario', 1)),
          10, 0)
  returning id)
select testes.def('p_rui', id) from x;
select testes.def('e_indisp', testes.erro(format($$select orcamento_pedido('[{"cardapio_id": "%s", "qtd": 1}]', %L)$$,
                                                 testes.v('calulu'), testes.u('casa_rui'))));
select testes.def('e_qtd', testes.erro(format($$select orcamento_pedido('[{"cardapio_id": "%s", "qtd": 0}]', %L)$$,
                                              testes.v('muamba'), testes.u('casa_rui'))));
select testes.def('e_alheio', testes.erro(format($$select orcamento_pedido('[{"cardapio_id": "%s", "qtd": 1}]', %L)$$,
                                                 testes.v('muamba'), testes.u('ponto_alheio'))));
select testes.def('e_sem_zona', testes.erro(format($$select orcamento_pedido('[{"cardapio_id": "%s", "qtd": 1}]', %L)$$,
                                                   testes.v('muamba'), testes.u('sem_zona'))));
select testes.def('e_vazio', testes.erro(format($$insert into pedidos (cliente_id, ponto_entrega_id) values (%L, %L)$$,
                                                testes.u('rui'), testes.u('casa_rui'))));
select testes.def('e_cardapio', testes.erro($$insert into cardapio (nome, preco) values ('Prato da app', 1)$$));
reset role;
select testes.sair();

select results_eq($$select (testes.v('orc')::jsonb ->> 'subtotal')::int, (testes.v('orc')::jsonb ->> 'taxa_entrega')::int,
                           (testes.v('orc')::jsonb ->> 'total')::int, testes.v('orc')::jsonb ->> 'zona_nome'$$,
                  $$values (5500, 700, 6200, 'Talatona'::text)$$,
                  'orçamento: 2 × 2.500 + 500 + taxa da zona 700 = 6.200');
select results_eq(format($$select subtotal::int, taxa_entrega::int, zona_id from pedidos where id = %L$$, testes.u('p_rui')),
                  format($$values (5500, 700, %L::uuid)$$, testes.u('zona')),
                  'pedido da app: subtotal, taxa e zona calculados no servidor (valores da app ignorados)');
select results_eq(format($$select i ->> 'nome', (i ->> 'preco_unitario')::int from pedidos p, jsonb_array_elements(p.itens) i
                            where p.id = %L order by 1$$, testes.u('p_rui')),
                  $$values ('Muamba de galinha'::text, 2500), ('Sumo de múcua'::text, 500)$$,
                  'nome e preço de cada item vêm do cardápio');
select is(testes.v('e_indisp'), 'P0001:item_indisponivel', 'item indisponível -> recusado');
select is(testes.v('e_qtd'), 'P0001:quantidade_invalida', 'quantidade 0 -> recusada');
select is(testes.v('e_alheio'), 'P0001:ponto_invalido', 'ponto de entrega de outro cliente -> recusado');
select is(testes.v('e_sem_zona'), 'P0001:ponto_sem_zona', 'ponto sem zona de entrega -> recusado');
select is(testes.v('e_vazio'), 'P0001:pedido_vazio', 'pedido sem itens -> recusado');
select matches(testes.v('e_cardapio'), '^42501', 'cliente não escreve no cardápio');

-- O operador não muda os itens nem os valores de um pedido
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('e_editar', testes.erro(format($$update pedidos set subtotal = 1 where id = %L$$, testes.u('p_rui'))));
reset role;
select testes.sair();
select matches(testes.v('e_editar'), '^42501', 'itens e valores do pedido não mudam depois de criado (nem pelo operador)');

-- Desconto de indicação no orçamento (C2): só depois da confirmação do servidor
select testes.funcionalidade('indicacao', true);
select testes.def('ana', testes.indicado(testes.u('rui'), 'Ana Maria'));
select testes.def('casa_ana', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa_ana'));
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('orc_ana', orcamento_pedido(jsonb_build_array(
         jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)), testes.u('casa_ana')));
reset role;
select testes.sair();
select results_eq($$select (testes.v('orc_ana')::jsonb ->> 'desconto')::int, testes.v('orc_ana')::jsonb ->> 'motivo_desconto',
                           (testes.v('orc_ana')::jsonb ->> 'total')::int$$,
                  $$values (500, 'ok'::text, 2700)$$,
                  'orçamento do indicado: −500 Kz confirmados pelo servidor (2.500 + 700 − 500)');

-- ---------------------------------------------------------------------------
-- 3. Amigos convidados (C1)
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
select results_eq($$select primeiro_nome, estado, dias_restantes from meus_amigos()$$,
                  $$values ('Ana'::text, 'aguarda_primeiro_pedido'::text, null::int)$$,
                  'amigo ligado: só o primeiro nome, à espera do 1.º pedido');
select testes.sair();
select testes.def('p_ana', testes.pedido(testes.u('ana'), testes.u('casa_ana')));
select testes.pagar(testes.u('p_ana'));
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
select results_eq($$select primeiro_nome, estado, dias_restantes, pedidos_com_ganho, ganho_total from meus_amigos()$$,
                  $$values ('Ana'::text, 'activo'::text, 60, 1, 100)$$,
                  'depois do 1.º pedido pago: activo, 60 dias, 1 ganho de 100 Kz');
select testes.sair();

-- ---------------------------------------------------------------------------
-- 4. Tokens de push
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('e_token', testes.erro($$select registar_token_push('abc', 'android')$$));
select registar_token_push('ExponentPushToken[rui-1]', 'android');
select testes.def('e_ler_tokens', testes.erro('select * from dispositivos_push'));
reset role;
select testes.sair();
select is(testes.v('e_token'), 'P0001:token_invalido', 'token que não é da Expo -> recusado');
select results_eq($$select cliente_id, activo from dispositivos_push where token = 'ExponentPushToken[rui-1]'$$,
                  format($$values (%L::uuid, true)$$, testes.u('rui')), 'token registado para o cliente');
select matches(testes.v('e_ler_tokens'), '^42501', 'a app não lê a tabela de tokens');

-- O mesmo telemóvel passa para outra conta
select testes.entrar(testes.u('ana'));
set local role authenticated;
select registar_token_push('ExponentPushToken[rui-1]', 'android');
reset role;
select is((select cliente_id from dispositivos_push where token = 'ExponentPushToken[rui-1]'), testes.u('ana')::uuid,
          'token reatribuído à conta que entrou no telemóvel');
set local role authenticated;
select remover_token_push('ExponentPushToken[rui-1]');
reset role;
select testes.sair();
select is((select activo from dispositivos_push where token = 'ExponentPushToken[rui-1]'), false, 'sair da conta desactiva o token');

-- ---------------------------------------------------------------------------
-- 5. Notificações
-- ---------------------------------------------------------------------------
select is((select (texto_notificacao('N2', dados)).corpo from notificacoes_fila
            where codigo = 'N2' and cliente_id = testes.u('rui')),
          'Ana entrou com o teu código! Ganhas 100 Kz em cada pedido durante 60 dias.',
          'N2: nome do amigo e valores garantidos da ligação');
select is((texto_notificacao('N3', '{"valor": 100, "indicado_nome": "João", "saldo_semana": 1300}')).corpo,
          '+100 Kz: o pedido de João foi entregue. Saldo desta semana: 1.300 Kz.', 'N3: texto da secção 11');
select is((texto_notificacao('N4', '{"limite": 10000}')).corpo,
          'Passaste os 10.000 Kz esta semana. Os próximos ganhos ficam em verificação e são pagos assim que confirmarmos os pedidos.',
          'N4: texto da secção 11');
select is((texto_notificacao('N8', '{"valor": 5000, "metodo": "multicaixa_express", "referencia": "MCX-1"}')).corpo,
          'Pagámos 5.000 Kz por Multicaixa Express. Referência: MCX-1.', 'N8: texto da secção 11');

select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
set local role authenticated;
select registar_token_push('ExponentPushToken[rui-2]', 'ios');
reset role;
select testes.sair();
select results_eq($$select codigo, tokens from notificacoes_pendentes() where cliente_id = testes.u('rui') order by codigo$$,
                  $$values ('N2'::text, array['ExponentPushToken[rui-2]']), ('N3'::text, array['ExponentPushToken[rui-2]'])$$,
                  'pendentes: N2 e N3 do indicador, com os tokens activos');
select testes.funcionalidade('indicacao', false);
select is((select count(*)::int from notificacoes_pendentes()), 0, 'interruptor desligado: nada para enviar');
select testes.funcionalidade('indicacao', true);
select is(marcar_notificacoes_enviadas(array(select id from notificacoes_pendentes())),
          (select count(*)::int from notificacoes_fila where codigo in ('N2','N3','N4','N8') and enviada_em is null),
          'marcar como enviadas');
select is((select count(*)::int from notificacoes_pendentes()), 0, 'depois de enviadas não voltam a sair');
select is(desactivar_tokens_push(array['ExponentPushToken[rui-2]']), 1, 'token rejeitado pela Expo é desactivado');
select ok(not has_function_privilege('authenticated', 'notificacoes_pendentes(integer)', 'execute')
          and not has_function_privilege('authenticated', 'marcar_notificacoes_enviadas(uuid[])', 'execute'),
          'funções do serviço de envio não são chamáveis pelas apps');

select * from finish();
rollback;
