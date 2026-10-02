-- Ajustes de I1: nomes, sincronização, estado do pedido só no servidor,
-- venda gerada na entrega e valores garantidos na ligação.
begin;
\ir _helpers.psql
select plan(32);

-- ---------------------------------------------------------------------------
-- Nomes e esquema
-- ---------------------------------------------------------------------------
select has_table('pontos_entrega', 'tabela pontos_entrega');
select hasnt_table('locais_entrega', 'locais_entrega já não existe');
select has_column('pedidos', 'ponto_entrega_id', 'pedidos.ponto_entrega_id');
select has_column('enderecos_cliente', 'ponto_entrega_id', 'enderecos_cliente.ponto_entrega_id');
select has_column('pedidos_grupo', 'ponto_entrega_id', 'pedidos_grupo.ponto_entrega_id');
select ok(not exists (select 1 from pg_tables where schemaname = 'public'
                        and tablename in ('indicacoes','recompensas_indicacao','config_indicacao')),
          'programa antigo não é criado');

-- Todas as tabelas novas têm os 6 campos de sincronização
select is(
  (select count(*)::int
     from unnest(array['parametros','funcionalidades','cozinhas','pontos_entrega','enderecos_cliente','pedidos',
                       'codigos_indicacao','ligacoes_indicacao','ganhos_indicacao','pagamentos_indicacao',
                       'perfil_destaques','preferencias_notificacao','avaliacoes','avaliacoes_pratos',
                       'fotos_avaliacao','palavras_filtradas','reconhecimentos_turno','pedidos_grupo',
                       'notificacoes_fila','contadores_zona']) t
     cross join unnest(array['id','dispositivo_id','criado_em','atualizado_em','sincronizado_em','deletado_em']) c
    where not exists (select 1 from information_schema.columns ic
                       where ic.table_schema = 'public' and ic.table_name = t and ic.column_name = c)),
  0, 'tabelas novas têm os 6 campos de sincronização');
select col_type_is('parametros', 'id', 'uuid', 'parametros.id é UUID');
select col_type_is('funcionalidades', 'id', 'uuid', 'funcionalidades.id é UUID');
select is((select count(*)::int from pg_description d join pg_class c on c.oid = d.objoid
            where c.relnamespace = 'public'::regnamespace and d.objsubid = 0
              and d.description like 'Sincronização:%'), 29,
          'estratégia de conflito registada nas 29 tabelas novas (21 de I1, 2 de I2, 2 de I9, 1 de I10, 1 de I11, 2 de I12)');

-- ---------------------------------------------------------------------------
-- Parâmetros e interruptores só por funções do servidor
-- ---------------------------------------------------------------------------
select testes.def('gestor', testes.funcionario('Gestora', array['plataforma.parametros']));
select testes.entrar_funcionario(testes.u('gestor'));
select throws_ok($$select alterar_parametros('{"id": "x"}')$$, 'P0001', 'parametro_invalido',
                 'alterar_parametros recusa campos que não são parâmetros');
select lives_ok($$select alterar_funcionalidade('indicacao', true)$$, 'interruptor ligado pela função');
select testes.sair();
select ok(exists (select 1 from auditoria where acao = 'funcionalidades_alterados'), 'mudança auditada');

-- ---------------------------------------------------------------------------
-- 5. Valores garantidos na ligação
-- ---------------------------------------------------------------------------
select testes.def('ana', testes.cliente('Ana Indicadora'));
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno'));
select results_eq(format($$select ganho_por_pedido_garantido, desconto_garantido
                             from ligacoes_indicacao where indicado_id = %L$$, testes.u('bruno')),
                  $$values (100, 500)$$, 'ligação guarda os valores em vigor (100 / 500)');

-- Os parâmetros mudam antes do 1.º pedido do Bruno
select testes.entrar_funcionario(testes.u('gestor'));
select lives_ok($$select alterar_parametros('{"ganho_por_pedido": 150, "desconto_indicado": 800}')$$,
                'parâmetros alterados para 150 / 800');
select testes.sair();
select is((select ganho_por_pedido from parametros), 150, 'parâmetro actual = 150');

select testes.def('p1', testes.pedido(testes.u('bruno'), testes.ponto('residencial')));
select is((select desconto_indicacao from pedidos where id = testes.u('p1')), 500,
          'desconto usa o valor garantido (500), não o parâmetro actual (800)');
select testes.pagar(testes.u('p1'));
select is((select valor from ganhos_indicacao where pedido_id = testes.u('p1')), 100,
          'ganho usa o valor garantido (100), não o parâmetro actual (150)');

-- Mudar o valor a meio dos 60 dias não altera os ganhos da ligação existente
update parametros set ganho_por_pedido = 300;
select testes.def('p2', testes.pedido(testes.u('bruno'), testes.ponto('residencial')));
select testes.pagar(testes.u('p2'));
select is((select valor from ganhos_indicacao where pedido_id = testes.u('p2')), 100,
          'valor alterado a meio do período: ligação existente continua a 100');

-- Nova ligação fica com os valores novos
select testes.def('carla', testes.indicado(testes.u('ana'), 'Carla'));
select results_eq(format($$select ganho_por_pedido_garantido, desconto_garantido
                             from ligacoes_indicacao where indicado_id = %L$$, testes.u('carla')),
                  $$values (300, 800)$$, 'nova ligação guarda os valores novos (300 / 800)');
select testes.def('p3', testes.pedido(testes.u('carla'), testes.ponto('residencial')));
select testes.pagar(testes.u('p3'));
select results_eq(format($$select x.desconto_indicacao, g.valor from pedidos x
                             join ganhos_indicacao g on g.pedido_id = x.id where x.id = %L$$, testes.u('p3')),
                  $$values (800, 300)$$, 'nova ligação: desconto 800 e ganho 300');

-- ---------------------------------------------------------------------------
-- 3. Anti-fraude: linhas criadas pelo servidor não contam como mesmo dispositivo
-- ---------------------------------------------------------------------------
select testes.def('dora', testes.indicado(testes.u('ana'), 'Dora'));
select testes.def('p_ana', testes.pedido(testes.u('ana'), null, 'servidor'));
select testes.def('p4', testes.pedido(testes.u('dora'), testes.ponto('residencial'), 'servidor'));
select testes.pagar(testes.u('p4'));
select is((select estado from ganhos_indicacao where pedido_id = testes.u('p4')), 'confirmado',
          'dispositivo_id = servidor não dispara o sinal de mesmo dispositivo');

-- ---------------------------------------------------------------------------
-- 1. Estado só no servidor e venda gerada na entrega
-- ---------------------------------------------------------------------------
with z as (insert into zonas (nome, tipo) values ('Kilamba', 'Própria') returning id)
select testes.def('zona', id) from z;
select testes.def('ponto_z', testes.ponto('residencial', null, null, testes.u('zona')));
select testes.def('eva', testes.indicado(testes.u('ana'), 'Eva'));
insert into pedidos (cliente_id, ponto_entrega_id, itens, subtotal, taxa_entrega, parcelas)
values (testes.u('eva'), testes.u('ponto_z'),
        '[{"nome": "Muamba de galinha", "qtd": 2, "preco_unitario": 2500}]', 5000, 700,
        '[{"metodo": "Dinheiro", "valor": 4900}]');
select testes.def('pv', (select id from pedidos where cliente_id = testes.u('eva')));
select testes.def('entregador', testes.funcionario('Entregador', array['entregas.registar']));
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));

select testes.entrar_funcionario(testes.u('entregador'));
select throws_ok(format($$select mudar_estado_pedido(%L, 'cancelado')$$, testes.u('pv')), '42501', 'sem_permissao',
                 'entregador não cancela pedidos');
select lives_ok(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L)$$, testes.u('pv'), testes.caixa()),
                'entregador marca entregue e pago');
select lives_ok(format($$select marcar_pagador_distinto(%L, true)$$, testes.u('pv')),
                'entregador marca "pago por outra pessoa"');
select testes.sair();

select results_eq(
  format($$select origem, cliente_id, valor_antes_desconto::int, desconto_aplicado::int, valor_total::int,
                  taxa_entrega::int, qtd::int, zona_nome, entrega, credito
             from vendas where pedido_id = %L$$, testes.u('pv')),
  format($$values ('App cliente'::text, %L::uuid, 5700, 800, 4900, 700, 2, 'Kilamba'::text, true, false)$$, testes.u('eva')),
  'entregue_pago gera a venda (origem App cliente; total = subtotal + taxa − desconto)');
select is((select parcelas from vendas where pedido_id = testes.u('pv')),
          '[{"metodo": "Dinheiro", "valor": 4900}]'::jsonb, 'venda leva as parcelas do pedido');

update pedidos set estado = 'entregue_pago' where id = testes.u('pv');
select is((select count(*)::int from vendas where pedido_id = testes.u('pv')), 1,
          'repetir o estado não duplica a venda');

select testes.entrar_funcionario(testes.u('gerente'));
select lives_ok(format($$select mudar_estado_pedido(%L, 'estornado', 'Cliente devolveu')$$, testes.u('pv')),
                'gerente estorna o pedido');
select testes.sair();
select results_eq(
  format($$select origem, valor_total::int from vendas where pedido_id = %L order by valor_total desc$$, testes.u('pv')),
  $$values ('App cliente'::text, 4900), ('App cliente (estorno)'::text, -4900)$$,
  'estorno gera venda de compensação (vendas continua append-only)');

-- Crédito de indicação entra nas parcelas da venda
select testes.def('pc', testes.pedido(testes.u('ana'), testes.ponto('empresa')));
select testes.entrar(testes.u('ana'));
select lives_ok(format($$select usar_credito(%L, 300)$$, testes.u('pc')), 'Ana usa 300 Kz de crédito');
select testes.sair();
select testes.pagar(testes.u('pc'));
select ok((select parcelas @> '[{"metodo": "Crédito indicação", "valor": 300}]'
             from vendas where pedido_id = testes.u('pc')),
          'crédito de indicação aparece como parcela da venda');

select * from finish();
rollback;
