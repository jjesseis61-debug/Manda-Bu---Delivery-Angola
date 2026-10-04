-- Secção 13 · RLS (testes 31 e 32), executados com o papel "authenticated".
-- As consultas correm como cliente/operador e guardam os resultados com
-- testes.def(); as asserções correm depois de "reset role" (as funções do
-- pgTAP escrevem em tabelas temporárias do dono da sessão).
begin;
\ir _helpers.psql
select plan(29);

select testes.funcionalidade('indicacao', true);

select testes.def('a', testes.cliente('Alice A'));
select testes.def('b', testes.cliente('Bento B'));

-- Dados do cliente B: é indicador de C, tem ganho, pagamento e endereço
select testes.def('c', testes.indicado(testes.u('b'), 'Cátia C'));
select testes.def('ponto_b', testes.ponto('residencial'));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('b'), testes.u('ponto_b'));
select testes.def('pedido_c', testes.pedido(testes.u('c'), testes.u('ponto_b')));
select testes.pagar(testes.u('pedido_c'));
select testes.def('pedido_b', testes.pedido(testes.u('b'), testes.u('ponto_b')));
insert into pagamentos_indicacao (indicador_id, valor, tipo, metodo, numero_destino)
values (testes.u('b'), 2000, 'levantamento', 'unitel_money', '923555666');

-- Dados do cliente A
-- Pedidos criados pela app usam o cardápio e um ponto com zona (I2)
with z as (insert into zonas (nome, tipo, taxa) values ('Zona A', 'Própria', 500) returning id)
select testes.def('zona_a', id) from z;
with m as (insert into cardapio (nome, preco) values ('Muamba', 2500) returning id)
select testes.def('item_a', id) from m;
select testes.def('ponto_a', testes.ponto('residencial', null, null, testes.u('zona_a')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('a'), testes.u('ponto_a'));
select testes.def('pedido_a', testes.pedido(testes.u('a'), testes.u('ponto_a')));

-- ---------------------------------------------------------------------------
-- 31. Cliente A não lê ganhos, pagamentos, ligações nem endereços do cliente B
-- ---------------------------------------------------------------------------
select testes.entrar(testes.u('a'));
set local role authenticated;
select testes.def('ganhos_b',       (select count(*) from ganhos_indicacao where indicador_id = testes.u('b')));
select testes.def('pagamentos_b',   (select count(*) from pagamentos_indicacao where indicador_id = testes.u('b')));
select testes.def('ligacoes_b',     (select count(*) from ligacoes_indicacao where indicador_id = testes.u('b')));
select testes.def('enderecos_b',    (select count(*) from enderecos_cliente where cliente_id = testes.u('b')));
select testes.def('pontos_b',       (select count(*) from pontos_entrega where id = testes.u('ponto_b')));
select testes.def('pedidos_b',      (select count(*) from pedidos where cliente_id = testes.u('b')));
select testes.def('saldo_b',        (select count(*) from saldo_indicacao where indicador_id = testes.u('b')));
select testes.def('codigos_b',      (select count(*) from codigos_indicacao where cliente_id = testes.u('b')));
select testes.def('clientes_todos', (select count(*) from clientes));
select testes.def('enderecos_meus', (select count(*) from enderecos_cliente));
select testes.def('pedidos_meus',   (select count(*) from pedidos));
select testes.def('interruptores',  (select count(*) from funcionalidades));
select testes.def('erro_fila',      testes.erro('select * from notificacoes_fila'));
reset role;

select is(testes.v('ganhos_b')::int,     0, '31. A não lê ganhos de B');
select is(testes.v('pagamentos_b')::int, 0, '31. A não lê pagamentos de B');
select is(testes.v('ligacoes_b')::int,   0, '31. A não lê ligações de B');
select is(testes.v('enderecos_b')::int,  0, '31. A não lê endereços de B');
select is(testes.v('pontos_b')::int,     0, '31. A não lê pontos de entrega de B');
select is(testes.v('pedidos_b')::int,    0, 'A não lê pedidos de B');
select is(testes.v('saldo_b')::int,      0, 'A não lê o saldo de B');
select is(testes.v('codigos_b')::int,    0, 'A não lê o código de B');
select is(testes.v('clientes_todos')::int, 0, 'tabelas base com RLS: cliente não lista clientes');
select is(testes.v('enderecos_meus')::int, 1, 'A lê o seu endereço');
select is(testes.v('pedidos_meus')::int,   1, 'A lê o seu pedido');
select is(testes.v('interruptores')::int, 20, 'A lê os interruptores');
select matches(testes.v('erro_fila'), '^42501', 'fila de notificações só para o serviço');

-- B lê os seus próprios dados
select testes.entrar(testes.u('b'));
set local role authenticated;
select testes.def('ganhos_meus_b', (select count(*) from ganhos_indicacao));
reset role;
select is(testes.v('ganhos_meus_b')::int, 1, 'B lê o seu ganho');

-- ---------------------------------------------------------------------------
-- 32. Cliente não escreve desconto_indicacao, credito_indicacao_usado nem ganhos
-- ---------------------------------------------------------------------------
select testes.entrar(testes.u('a'));
set local role authenticated;
select testes.def('e_desconto', testes.erro(format(
  'update pedidos set desconto_indicacao = 900 where id = %L', testes.u('pedido_a'))));
select testes.def('e_credito', testes.erro(format(
  'update pedidos set credito_indicacao_usado = 900 where id = %L', testes.u('pedido_a'))));
select testes.def('e_entregue', testes.erro(format(
  'update pedidos set entregue_em = now() where id = %L', testes.u('pedido_a'))));
select testes.def('e_estado', testes.erro(format(
  'update pedidos set estado = %L where id = %L', 'entregue_pago', testes.u('pedido_a'))));
select testes.def('e_ins_credito', testes.erro(format(
  'insert into pedidos (cliente_id, credito_indicacao_usado) values (%L, 5000)', testes.u('a'))));
select testes.def('e_ins_ganho', testes.erro(format(
  'insert into ganhos_indicacao (pedido_id, indicador_id, indicado_id, valor, estado) values (%L, %L, %L, 100, %L)',
  testes.u('pedido_a'), testes.u('a'), testes.u('b'), 'confirmado')));
select testes.def('e_upd_ganho', testes.erro(format(
  'update ganhos_indicacao set estado = %L where indicador_id = %L', 'pago', testes.u('b'))));
select testes.def('e_ins_pagamento', testes.erro(format(
  'insert into pagamentos_indicacao (indicador_id, valor, tipo) values (%L, 5000, %L)', testes.u('a'), 'credito')));
select testes.def('e_nivel', testes.erro(format(
  'update codigos_indicacao set nivel = %L where cliente_id = %L', 'embaixador', testes.u('a'))));
select testes.def('e_parametros', testes.erro('update parametros set ganho_por_pedido = 1000'));
-- Inserir um pedido com desconto inventado é aceite, mas o servidor recalcula
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens, desconto_indicacao)
           values (testes.u('a'), testes.u('ponto_a'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('item_a'), 'qtd', 1)), 700)
           returning desconto_indicacao)
select testes.def('desconto_a2', desconto_indicacao) from x;
reset role;

select matches(testes.v('e_desconto'),    '^42501', '32. cliente não escreve desconto_indicacao');
select matches(testes.v('e_credito'),     '^42501', '32. cliente não escreve credito_indicacao_usado');
select matches(testes.v('e_entregue'),    '^42501', 'cliente não escreve entregue_em');
select matches(testes.v('e_estado'),      '^42501', 'cliente não muda o estado do pedido');
select is((select estado from pedidos where id = testes.u('pedido_a')), 'pendente', 'pedido de A continua pendente');
select matches(testes.v('e_ins_credito'), '^42501', '32. cliente não cria pedido com credito_indicacao_usado');
select ok(testes.v('e_ins_ganho') ~ '^42501' and testes.v('e_upd_ganho') ~ '^42501'
          and testes.v('e_ins_pagamento') ~ '^42501',
          '32. cliente não cria nem altera ganhos nem pagamentos');
select matches(testes.v('e_nivel'),       '^42501', 'cliente não muda o nível de indicador');
select matches(testes.v('e_parametros'),  '^42501', 'cliente não muda parâmetros');
select is(testes.v('desconto_a2')::int, 0, '32. desconto enviado pela app é recalculado pelo servidor (0)');

-- ---------------------------------------------------------------------------
-- Estado do pedido e configuração só no servidor, mesmo para operadores
-- ---------------------------------------------------------------------------
select testes.def('operador', testes.funcionario('Operadora', array['pedidos.gerir','plataforma.parametros']));
select testes.entrar_funcionario(testes.u('operador'));
set local role authenticated;
select testes.def('e_op_estado', testes.erro(format(
  'update pedidos set estado = %L where id = %L', 'confirmado', testes.u('pedido_a'))));
select testes.def('e_op_param', testes.erro('update parametros set ganho_por_pedido = 1000'));
select testes.def('e_op_func', testes.erro($$update funcionalidades set activa = true where chave = 'destaques'$$));
select testes.def('e_op_mudar', testes.erro(format(
  'select mudar_estado_pedido(%L, %L)', testes.u('pedido_a'), 'confirmado')));
reset role;
select matches(testes.v('e_op_estado'), '^42501', 'operador não escreve o estado directamente (fila de saída)');
select ok(testes.v('e_op_param') ~ '^42501' and testes.v('e_op_func') ~ '^42501',
          'operador não escreve parâmetros nem interruptores directamente');
select is(testes.v('e_op_mudar'), 'sem_erro', 'operador muda o estado pela função do servidor');
select is((select estado from pedidos where id = testes.u('pedido_a')), 'confirmado', 'estado alterado no servidor');

-- Segunda barreira: mesmo que um privilégio seja concedido por engano, as tabelas
-- escritas só pelo servidor recusam escritas de dispositivos
grant insert on ganhos_indicacao to authenticated;
select testes.entrar(testes.u('a'));
set local role authenticated;
select testes.def('e_guarda', testes.erro(format(
  'insert into ganhos_indicacao (pedido_id, indicador_id, indicado_id, valor, estado) values (%L, %L, %L, 100, %L)',
  testes.u('pedido_a'), testes.u('a'), testes.u('b'), 'confirmado')));
reset role;
select matches(testes.v('e_guarda'), 'escrita_so_no_servidor', 'trigger recusa escrita vinda de dispositivo');

select * from finish();
rollback;
