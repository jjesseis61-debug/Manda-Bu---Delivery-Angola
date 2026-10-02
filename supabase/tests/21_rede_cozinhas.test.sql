-- I8 · Rede de cozinhas: selector do cliente, pedido na cozinha escolhida, grupo noutra
-- cozinha, cozinha pausada, relatório comparativo e O10 por cozinha
begin;
\ir _helpers.psql
select plan(17);

select testes.def('alexandra', cozinha_padrao());
insert into cozinhas (nome, responsavel, consentimento_publico, historia) values ('Cozinha do Kilamba', 'Joana', true, 'Desde 2010');
select testes.def('kilamba', (select id from cozinhas where nome = 'Cozinha do Kilamba'));
with z as (insert into zonas (nome, tipo, taxa) values ('Kilamba', 'Própria', 200) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Muamba', 2000) returning id) select testes.def('m_alex', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Mufete', 3500, testes.u('kilamba')) returning id)
select testes.def('m_kil', id) from m;

select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
select testes.def('trabalho', testes.ponto('empresa', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa')), (testes.u('ana'), testes.u('trabalho'));

-- multi_cozinha desligado: só a cozinha por defeito
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('lista_off', (select string_agg(nome, ',') from cozinhas_para_pedir()));
select testes.def('e_off', testes.erro(format($$select orcamento_pedido('[{"cardapio_id": "%s", "qtd": 1}]', %L, %L)$$,
                                              testes.v('m_kil'), testes.v('casa'), testes.v('kilamba'))));
reset role;
select is(testes.v('lista_off'), 'Cozinha da Alexandra', 'multi_cozinha desligado: o cliente só vê a cozinha por defeito');
select is(testes.v('e_off'), 'P0001:item_indisponivel', 'multi_cozinha desligado: pratos de outra cozinha não se pedem');

-- multi_cozinha ligado
select testes.funcionalidade('multi_cozinha', true);
select testes.funcionalidade('perfil_cozinha', true);
set local role authenticated;
select testes.def('lista_on', (select string_agg(nome || ':' || publica || ':' || pratos || ':' || coalesce(historia, '-'), ',')
                                 from cozinhas_para_pedir()));
with x as (insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens)
           values (testes.u('ana'), testes.u('casa'), testes.u('kilamba'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('m_kil'), 'qtd', 1)))
           returning id, cozinha_id, subtotal)
select testes.def('p_kil', id), testes.def('p_kil_cozinha', cozinha_id), testes.def('p_kil_sub', subtotal) from x;
select testes.def('e_misto', testes.erro(format($$select orcamento_pedido('[{"cardapio_id": "%s", "qtd": 1}]', %L, %L)$$,
                                                testes.v('m_alex'), testes.v('casa'), testes.v('kilamba'))));
reset role;
select is(testes.v('lista_on'), 'Cozinha da Alexandra:false:1:-,Cozinha do Kilamba:true:1:Desde 2010',
          'selector: cozinhas activas, a por defeito primeiro; perfil só com consentimento');
select is(testes.u('p_kil_cozinha'), testes.u('kilamba')::uuid, 'o pedido fica na cozinha escolhida');
select is(testes.v('p_kil_sub')::int, 3500, 'preço do cardápio dessa cozinha');
select is(testes.v('e_misto'), 'P0001:item_indisponivel', 'pratos de outra cozinha não entram no pedido');

-- Cozinha pausada não aceita pedidos
update cozinhas set estado = 'pausada' where id = testes.u('kilamba');
set local role authenticated;
select testes.def('lista_pausa', (select count(*) from cozinhas_para_pedir()));
select testes.def('e_pausa', testes.erro(format($$select orcamento_pedido('[{"cardapio_id": "%s", "qtd": 1}]', %L, %L)$$,
                                                testes.v('m_kil'), testes.v('casa'), testes.v('kilamba'))));
reset role;
select is(testes.v('lista_pausa')::int, 1, 'cozinha pausada sai do selector');
select is(testes.v('e_pausa'), 'P0001:cozinha_indisponivel', 'cozinha pausada não aceita pedidos');
update cozinhas set estado = 'activa' where id = testes.u('kilamba');

-- Grupo noutra cozinha: os pedidos do grupo são dessa cozinha
select testes.funcionalidade('pedidos_grupo', true);
set local role authenticated;
with g as (insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento, cozinha_id)
           values (testes.u('trabalho'), now() + interval '3 hours', now() + interval '2 hours', 'individual', testes.u('kilamba'))
           returning id, cozinha_id)
select testes.def('grupo', id), testes.def('grupo_cozinha', cozinha_id) from g;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('ana'), testes.u('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('m_kil'), 'qtd', 2)))
           returning cozinha_id, subtotal)
select testes.def('pg_cozinha', cozinha_id), testes.def('pg_sub', subtotal) from x;
reset role;
select is(testes.u('grupo_cozinha'), testes.u('kilamba')::uuid, 'grupo criado na cozinha escolhida');
select testes.entrar(testes.u('ana'));
select is(grupo_detalhe((select codigo_convite from pedidos_grupo where id = testes.u('grupo'))) ->> 'cozinha_nome',
          'Cozinha do Kilamba', 'C13: o grupo diz a cozinha');
select results_eq($$select testes.u('pg_cozinha'), testes.v('pg_sub')::int$$, format($$values (%L::uuid, 7000)$$, testes.u('kilamba')),
                  'pedido no grupo: cozinha e cardápio do grupo, sem a app indicar a cozinha');
select testes.sair();

-- Relatório comparativo
select testes.pagar(testes.u('p_kil'));
select testes.def('p_alex', testes.pedido(testes.u('ana'), testes.u('casa')));
select testes.pagar(testes.u('p_alex'));
select testes.def('bia', testes.cliente('Bia Lima'));
select testes.pagar(testes.pedido(testes.u('bia'), testes.u('casa')));
select testes.def('gestor', testes.funcionario('Gestor', array['relatorios.exportar', 'pedidos.gerir']));
select testes.entrar(testes.u('ana'));
select is(testes.erro('select relatorio_comparativo(hoje_luanda(), hoje_luanda())'), '42501:sem_permissao',
          'relatório comparativo exige relatorios.exportar');
select testes.entrar_funcionario(testes.u('gestor'));
select testes.def('comp', relatorio_comparativo(hoje_luanda() - 1, hoje_luanda()));
select testes.def('o10', grupos_operador((select (hora_entrega at time zone 'Africa/Luanda')::date from pedidos_grupo where id = testes.u('grupo'))));
select testes.sair();
select results_eq($$select (e ->> 'nome'), (e ->> 'pedidos')::int, (e ->> 'vendas')::int, (e ->> 'ticket_medio')::int,
                           (e ->> 'clientes')::int, (e ->> 'clientes_novos')::int
                      from jsonb_array_elements(testes.v('comp')::jsonb) e order by e ->> 'nome'$$,
                  $$values ('Cozinha da Alexandra'::text, 2, 6000, 3000, 2, 2), ('Cozinha do Kilamba'::text, 1, 3700, 3700, 1, 1)$$,
                  'comparativo: pedidos, vendas, ticket médio, clientes e clientes novos por cozinha');
select is((select e ->> 'nome' from jsonb_array_elements(testes.v('comp')::jsonb) e limit 1), 'Cozinha da Alexandra',
          'comparativo ordenado por vendas');
select ok((select bool_and(e -> 'media_avaliacao' = 'null'::jsonb) from jsonb_array_elements(testes.v('comp')::jsonb) e),
          'média de avaliação só com o mínimo de avaliações');
select is(testes.v('o10')::jsonb -> 0 ->> 'cozinha_nome', 'Cozinha do Kilamba', 'O10 diz a cozinha do grupo');

-- multi_cozinha desligado de novo: pedidos voltam à cozinha por defeito
select testes.funcionalidade('multi_cozinha', false);
select testes.entrar(testes.u('ana'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens)
           values (testes.u('ana'), testes.u('casa'), testes.u('kilamba'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('m_alex'), 'qtd', 1)))
           returning cozinha_id)
select testes.def('p_off', cozinha_id) from x;
reset role;
select testes.sair();
select is(testes.u('p_off'), testes.u('alexandra')::uuid, 'interruptor desligado: o pedido vai para a cozinha por defeito');

select * from finish();
rollback;
