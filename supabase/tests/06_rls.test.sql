-- Secção 13 · RLS (testes 31 e 32), executados com o papel "authenticated".
-- As consultas correm como cliente; os resultados vão para variáveis psql e as
-- asserções correm depois de "reset role".
begin;
\ir _helpers.psql
select plan(23);

select testes.funcionalidade('indicacao', true);

select testes.cliente('Alice A') as a \gset
select testes.cliente('Bento B') as b \gset

-- Dados do cliente B: é indicador de C, tem ganho, pagamento e endereço
select testes.indicado(:'b', 'Cátia C') as c \gset
select testes.local('residencial') as local_b \gset
insert into enderecos_cliente (cliente_id, local_id) values (:'b', :'local_b');
select testes.pedido(:'c', :'local_b') as pedido_c \gset
select testes.pagar(:'pedido_c');
select testes.pedido(:'b', :'local_b') as pedido_b \gset
insert into pagamentos_indicacao (indicador_id, valor, tipo, metodo, numero_destino)
values (:'b', 2000, 'levantamento', 'unitel_money', '923555666');

-- Dados do cliente A
select testes.local('residencial') as local_a \gset
insert into enderecos_cliente (cliente_id, local_id) values (:'a', :'local_a');
select testes.pedido(:'a', :'local_a') as pedido_a \gset

-- ---------------------------------------------------------------------------
-- 31. Cliente A não lê ganhos, pagamentos, ligações nem endereços do cliente B
-- ---------------------------------------------------------------------------
select testes.entrar(:'a');
set local role authenticated;
select
  (select count(*) from ganhos_indicacao where indicador_id = :'b')           as ganhos_b,
  (select count(*) from pagamentos_indicacao where indicador_id = :'b')       as pagamentos_b,
  (select count(*) from ligacoes_indicacao where indicador_id = :'b')         as ligacoes_b,
  (select count(*) from enderecos_cliente where cliente_id = :'b')            as enderecos_b,
  (select count(*) from locais_entrega where id = :'local_b')                 as locais_b,
  (select count(*) from pedidos where cliente_id = :'b')                      as pedidos_b,
  (select count(*) from saldo_indicacao where indicador_id = :'b')            as saldo_b,
  (select count(*) from codigos_indicacao where cliente_id = :'b')            as codigos_b,
  (select count(*) from enderecos_cliente)                                    as enderecos_meus,
  (select count(*) from pedidos)                                              as pedidos_meus,
  (select count(*) from funcionalidades)                                      as interruptores
\gset
select testes.erro('select * from notificacoes_fila') as erro_fila \gset
reset role;

select is(:ganhos_b,     0, '31. A não lê ganhos de B');
select is(:pagamentos_b, 0, '31. A não lê pagamentos de B');
select is(:ligacoes_b,   0, '31. A não lê ligações de B');
select is(:enderecos_b,  0, '31. A não lê endereços de B');
select is(:locais_b,     0, '31. A não lê locais de B');
select is(:pedidos_b,    0, 'A não lê pedidos de B');
select is(:saldo_b,      0, 'A não lê o saldo de B');
select is(:codigos_b,    0, 'A não lê o código de B');
select is(:enderecos_meus, 1, 'A lê o seu endereço');
select is(:pedidos_meus,   1, 'A lê o seu pedido');
select is(:interruptores, 10, 'A lê os interruptores');
select matches(:'erro_fila'::text, '^42501', 'fila de notificações só para o serviço');

-- B lê os seus próprios dados
select testes.entrar(:'b');
set local role authenticated;
select (select count(*) from ganhos_indicacao) as ganhos_meus_b \gset
reset role;
select is(:ganhos_meus_b, 1, 'B lê o seu ganho');

-- ---------------------------------------------------------------------------
-- 32. Cliente não escreve desconto_indicacao, credito_indicacao_usado nem ganhos
-- ---------------------------------------------------------------------------
select testes.entrar(:'a');
set local role authenticated;
select
  testes.erro(format('update pedidos set desconto_indicacao = 900 where id = %L', :'pedido_a')) as e_desconto,
  testes.erro(format('update pedidos set credito_indicacao_usado = 900 where id = %L', :'pedido_a')) as e_credito,
  testes.erro(format('update pedidos set entregue_em = now() where id = %L', :'pedido_a')) as e_entregue,
  testes.erro(format('update pedidos set estado = %L where id = %L', 'entregue_pago', :'pedido_a')) as e_estado,
  testes.erro(format('insert into pedidos (cliente_id, credito_indicacao_usado) values (%L, 5000)', :'a')) as e_ins_credito,
  testes.erro(format('insert into ganhos_indicacao (pedido_id, indicador_id, indicado_id, valor, estado)
                      values (%L, %L, %L, 100, %L)', :'pedido_a', :'a', :'b', 'confirmado')) as e_ins_ganho,
  testes.erro(format('update ganhos_indicacao set estado = %L where indicador_id = %L', 'pago', :'b')) as e_upd_ganho,
  testes.erro(format('insert into pagamentos_indicacao (indicador_id, valor, tipo) values (%L, 5000, %L)',
                     :'a', 'credito')) as e_ins_pagamento,
  testes.erro(format('update codigos_indicacao set nivel = %L where cliente_id = %L', 'embaixador', :'a')) as e_nivel,
  testes.erro('update parametros set ganho_por_pedido = 1000') as e_parametros
\gset
-- Inserir um pedido com desconto inventado é aceite, mas o servidor recalcula
insert into pedidos (cliente_id, local_id, desconto_indicacao) values (:'a', :'local_a', 700)
returning id as pedido_a2, desconto_indicacao as desconto_a2 \gset
reset role;

select matches(:'e_desconto'::text,      '^42501', '32. cliente não escreve desconto_indicacao');
select matches(:'e_credito'::text,       '^42501', '32. cliente não escreve credito_indicacao_usado');
select matches(:'e_entregue'::text,      '^42501', 'cliente não escreve entregue_em');
select is(:'e_estado'::text, 'sem_erro', 'cliente não muda o estado do pedido (RLS: 0 linhas)');
select is((select estado from pedidos where id = :'pedido_a'), 'pendente', 'pedido de A continua pendente');
select matches(:'e_ins_credito'::text,   '^42501', '32. cliente não cria pedido com credito_indicacao_usado');
select ok(:'e_ins_ganho' ~ '^42501' and :'e_upd_ganho' ~ '^42501' and :'e_ins_pagamento' ~ '^42501',
          '32. cliente não cria nem altera ganhos nem pagamentos');
select matches(:'e_nivel'::text, '^42501', 'cliente não muda o nível de indicador');
select is((select ganho_por_pedido from parametros), 100, 'cliente não muda parâmetros (RLS: 0 linhas)');
select is(:desconto_a2, 0, '32. desconto enviado pela app é recalculado pelo servidor (0)');

select * from finish();
rollback;
