-- Secção 13 · Ligação (testes 1 a 4)
begin;
\ir _helpers.psql
select plan(9);

select testes.cliente('Ana Indicadora') as ana \gset
select testes.cliente('Bruno Novo') as bruno \gset
select testes.cliente('Carla Outra') as carla \gset
select testes.cliente('Dário Antigo') as dario \gset

-- Programa desligado
select is(testes.ligar(:'bruno', :'ana'), 'programa_inactivo', 'interruptor desligado -> programa_inactivo');

select testes.funcionalidade('indicacao', true);

-- 1. Código inexistente
select testes.entrar(:'bruno');
select is(ligar_indicacao('MB-999999'), 'codigo_inexistente', '1. código inexistente -> codigo_inexistente');

-- 2. Próprio código
select testes.entrar(:'ana');
select is(ligar_indicacao(testes.codigo(:'ana')), 'proprio_codigo', '2. próprio código -> proprio_codigo');

-- Ligação válida (aceita minúsculas e espaços)
select testes.entrar(:'bruno');
select is(ligar_indicacao('  ' || lower(testes.codigo(:'ana')) || ' '), 'ok', 'ligação válida');
select is((select indicador_id from ligacoes_indicacao where indicado_id = :'bruno'), :'ana'::uuid,
          'ligação indicado -> indicador criada');
select is((select count(*)::int from notificacoes_fila where cliente_id = :'ana' and codigo = 'N2'), 1,
          'N2 enfileirada para o indicador');

-- 3. Segundo código para o mesmo cliente
select is(testes.ligar(:'bruno', :'carla'), 'ja_ligado', '3. segundo código -> ja_ligado');

-- 4. Cliente com pedido pago tenta ligar-se
select testes.pagar(testes.pedido(:'dario'));
select is(testes.ligar(:'dario', :'ana'), 'cliente_nao_novo', '4. cliente com pedido pago -> cliente_nao_novo');

-- Cliente com compras no sistema anterior (vendas) também não é novo
select testes.cliente('Eva Loja') as eva \gset
insert into vendas (cliente_id, valor_total) values (:'eva', 2500);
select is(testes.ligar(:'eva', :'ana'), 'cliente_nao_novo', 'cliente com vendas anteriores -> cliente_nao_novo');

select * from finish();
rollback;
