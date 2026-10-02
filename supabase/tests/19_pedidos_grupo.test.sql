-- I6 · Pedidos de grupo: criar (C12), aderir (C13), N10/N11, fecho e taxa, O10
begin;
\ir _helpers.psql
select plan(33);

select testes.funcionalidade('pedidos_grupo', true);
select testes.funcionalidade('indicacao', true);
with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 301) returning id)
select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Muamba', 2000) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco) values ('Calulu', 3000) returning id) select testes.def('calulu', id) from m;

select testes.def('gil', testes.cliente('Gil Organizador'));
select testes.def('marta', testes.cliente('Marta Colega'));
select testes.def('rui', testes.indicado(testes.u('gil'), 'Rui Novo'));
select testes.def('escritorio', testes.ponto('empresa', -8.83, 13.24, testes.u('zona')));
update pontos_entrega set referencia = 'Edifício Kilamba, 3.º andar' where id = testes.u('escritorio');
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
select testes.def('outro', testes.ponto('empresa', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id)
values (testes.u('gil'), testes.u('escritorio')), (testes.u('gil'), testes.u('casa'));

-- ---------------------------------------------------------------------------
-- C12. Criar grupo
-- ---------------------------------------------------------------------------
select testes.entrar(testes.u('gil'));
set local role authenticated;
with g as (insert into pedidos_grupo (organizador_id, ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
           values (testes.u('marta'), testes.u('escritorio'), now() + interval '3 hours', now() + interval '2 hours', 'individual')
           returning id)
select testes.def('grupo', id) from g;
select testes.def('e_casa', testes.erro(format($$insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
  values (%L, now() + interval '3 hours', now() + interval '2 hours', 'individual')$$, testes.v('casa'))));
select testes.def('e_outro', testes.erro(format($$insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
  values (%L, now() + interval '3 hours', now() + interval '2 hours', 'individual')$$, testes.v('outro'))));
select testes.def('e_horas', testes.erro(format($$insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
  values (%L, now() + interval '3 hours', now() - interval '1 minute', 'individual')$$, testes.v('escritorio'))));
select testes.def('e_empresa', testes.erro(format($$insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
  values (%L, now() + interval '3 hours', now() + interval '2 hours', 'empresa')$$, testes.v('escritorio'))));
select testes.def('e_editar', testes.erro(format($$update pedidos_grupo set hora_entrega = now() where id = %L$$, testes.v('grupo'))));
reset role;
select testes.sair();

select results_eq(format($$select organizador_id, estado, empresa_id from pedidos_grupo where id = %L$$, testes.u('grupo')),
                  format($$values (%L::uuid, 'aberto'::text, null::uuid)$$, testes.u('gil')),
                  'C12: o cliente cria o grupo; o organizador é quem está na sessão');
select matches((select codigo_convite from pedidos_grupo where id = testes.u('grupo')), '^G-[0-9A-F]{6}$', 'C12: código do link');
select is(testes.v('e_casa'), 'P0001:grupo_ponto_invalido', 'C12: só no local de trabalho (ponto empresa)');
select is(testes.v('e_outro'), 'P0001:grupo_ponto_invalido', 'C12: só num endereço do próprio cliente');
select is(testes.v('e_horas'), 'P0001:grupo_horas_invalidas', 'C12: prazo de adesão no futuro e antes da hora de entrega');
select is(testes.v('e_empresa'), 'P0001:grupo_empresa_invalida', 'C12: modo empresa só para clientes Empresa');
select matches(testes.v('e_editar'), '^42501', 'o organizador não altera o grupo directamente');
select testes.def('codigo', (select codigo_convite from pedidos_grupo where id = testes.u('grupo')));

-- ---------------------------------------------------------------------------
-- C13. Aderir ao grupo
-- ---------------------------------------------------------------------------
select testes.entrar(testes.u('marta'));
set local role authenticated;
select testes.def('orc', orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)),
                                          null, null, testes.u('grupo')));
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('marta'), testes.u('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)))
           returning id)
select testes.def('p_marta', id) from x;
reset role;
select testes.sair();
select results_eq($$select (testes.v('orc')::jsonb ->> 'taxa_entrega')::int, (testes.v('orc')::jsonb ->> 'taxa_grupo_estimada')::int,
                           (testes.v('orc')::jsonb ->> 'total')::int$$,
                  $$values (0, 301, 2000)$$, 'orçamento no grupo: taxa a 0 até ao fecho, estimativa por pessoa');
select results_eq(format($$select ponto_entrega_id, zona_id, taxa_entrega::int from pedidos where id = %L$$, testes.u('p_marta')),
                  format($$values (%L::uuid, %L::uuid, 0)$$, testes.u('escritorio'), testes.u('zona')),
                  'pedido no grupo: ponto e zona do grupo');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N10' and cliente_id = testes.u('gil')),
          format('Marta juntou-se ao teu grupo das %s. Já são 1.',
                 (select to_char(hora_entrega at time zone 'Africa/Luanda', 'HH24"h"MI') from pedidos_grupo where id = testes.u('grupo'))),
          'N10 ao organizador, com a hora do grupo');

-- O indicado novo usa o desconto no ponto do grupo
select testes.entrar(testes.u('rui'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('rui'), testes.u('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('calulu'), 'qtd', 1)))
           returning id)
select testes.def('p_rui', id) from x;
select testes.def('detalhe', grupo_detalhe(testes.v('codigo')));
reset role;
select testes.sair();
select is((select desconto_indicacao::int from pedidos where id = testes.u('p_rui')), 500, 'indicado novo: desconto no pedido de grupo');
select is(testes.v('detalhe')::jsonb -> 'participantes',
          '[{"nome": "Marta", "estado": "pendente", "sou_eu": false}, {"nome": "Rui", "estado": "pendente", "sou_eu": true}]'::jsonb,
          'C13: participantes por primeiro nome e estado');
select ok(testes.v('detalhe')::jsonb ->> 'local' = 'Edifício Kilamba, 3.º andar'
          and (testes.v('detalhe')::jsonb ->> 'taxa_estimada')::int = 151
          and not (testes.v('detalhe')::text ~* 'cliente_id|telefone'),
          'C13: local do grupo, taxa estimada por pessoa, sem ids de clientes nem telefones');

-- O organizador também pede
select testes.entrar(testes.u('gil'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, grupo_id, itens)
           values (testes.u('gil'), testes.u('grupo'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2)))
           returning id)
select testes.def('p_gil', id) from x;
select testes.def('meus', (select count(*) from meus_grupos()));
reset role;
select testes.sair();
select is(testes.v('meus')::int, 1, 'C13: os meus grupos');

-- ---------------------------------------------------------------------------
-- N11, fecho e taxa dividida (301 Kz por 3: 101 + 100 + 100)
-- ---------------------------------------------------------------------------
update pedidos_grupo set prazo_adesao = now() + interval '10 minutes' where id = testes.u('grupo');
select job_grupos();
select job_grupos();
select is((select count(*)::int from notificacoes_fila where codigo = 'N11' and dados ->> 'grupo_id' = testes.v('grupo')), 3,
          'N11 ao organizador e aos participantes, uma vez');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N11' and cliente_id = testes.u('marta')),
          format('O grupo das %s fecha em 15 minutos.',
                 (select to_char(hora_entrega at time zone 'Africa/Luanda', 'HH24"h"MI') from pedidos_grupo where id = testes.u('grupo'))),
          'N11: texto');
select is((select dados ->> 'codigo_grupo' from notificacoes_fila where codigo = 'N11' and cliente_id = testes.u('marta')),
          testes.v('codigo'), 'N11 leva o código do grupo para a app abrir o grupo');
select is((select array_agg(distinct codigo order by codigo) from notificacoes_por_enviar(1000) where codigo in ('N10', 'N11')),
          array['N10', 'N11'], 'N10 e N11 seguem para envio');

select testes.entrar(testes.u('marta'));
select is(testes.erro(format('select fechar_grupo(%L)', testes.v('grupo'))), '42501:sem_permissao', 'só o organizador fecha o grupo');
select testes.sair();
update pedidos_grupo set prazo_adesao = now() - interval '1 minute' where id = testes.u('grupo');
select job_grupos();
select is((select estado from pedidos_grupo where id = testes.u('grupo')), 'fechado', 'prazo passado: grupo fechado pelo job');
select results_eq(format($$select taxa_entrega::int from pedidos where grupo_id = %L order by taxa_entrega desc$$, testes.u('grupo')),
                  $$values (101), (100), (100)$$, 'taxa dividida pelos participantes (soma igual à taxa da zona)');
select ok(exists (select 1 from auditoria where acao = 'grupo_fechado' and ref_id = testes.u('grupo')), 'fecho auditado');

select testes.def('ana', testes.cliente('Ana Atrasada'));
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_tarde', testes.erro(format($$insert into pedidos (cliente_id, grupo_id, itens)
  values (%L, %L, '[{"cardapio_id": "%s", "qtd": 1}]')$$, testes.v('ana'), testes.v('grupo'), testes.v('muamba'))));
reset role;
select testes.sair();
select is(testes.v('e_tarde'), 'P0001:grupo_fechado', 'depois do fecho já não se adere');

-- ---------------------------------------------------------------------------
-- O10
-- ---------------------------------------------------------------------------
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
select testes.entrar(testes.u('gil'));
select is(testes.erro('select grupos_operador()'), '42501:sem_permissao', 'O10 exige pedidos.gerir ou entregas.registar');
select testes.entrar_funcionario(testes.u('gerente'));
select testes.def('o10', grupos_operador((select (hora_entrega at time zone 'Africa/Luanda')::date from pedidos_grupo where id = testes.u('grupo'))));
select ok(testes.v('o10')::jsonb -> 0 -> 'resumo' = '[{"nome": "Calulu", "qtd": 1}, {"nome": "Muamba", "qtd": 3}]'::jsonb
          and jsonb_array_length(testes.v('o10')::jsonb -> 0 -> 'pedidos') = 3
          and (testes.v('o10')::jsonb -> 0 ->> 'total_a_pagar')::int = 2000 + 3000 - 500 + 4000 + 301,
          'O10: pedidos juntos, resumo dos pratos para a preparação e total a receber');
select is(mudar_estado_grupo(testes.u('grupo'), 'em_preparacao'), 3, 'O10: todos os pedidos em preparação de uma vez');
select testes.sair();
select is((select estado from pedidos_grupo where id = testes.u('grupo')), 'em_preparacao', 'o grupo acompanha os pedidos');
select testes.pagar(id) from pedidos where grupo_id = testes.u('grupo');
select is((select estado from pedidos_grupo where id = testes.u('grupo')), 'entregue', 'todos entregues: grupo entregue');

-- ---------------------------------------------------------------------------
-- Modo empresa: a taxa fica toda no pedido da empresa
-- ---------------------------------------------------------------------------
select testes.def('empresa', testes.cliente('Kilamba Lda', 'Empresa'));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('empresa'), testes.u('escritorio'));
select testes.entrar(testes.u('empresa'));
set local role authenticated;
with g as (insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
           values (testes.u('escritorio'), now() + interval '3 hours', now() + interval '2 hours', 'empresa') returning id, empresa_id)
select testes.def('g2', id), testes.def('g2_empresa', empresa_id) from g;
insert into pedidos (cliente_id, grupo_id, itens)
values (testes.u('empresa'), testes.u('g2'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)));
reset role;
select testes.entrar(testes.u('marta'));
set local role authenticated;
insert into pedidos (cliente_id, grupo_id, itens)
values (testes.u('marta'), testes.u('g2'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('calulu'), 'qtd', 1)));
reset role;
select testes.entrar(testes.u('empresa'));
select fechar_grupo(testes.u('g2'));
select testes.sair();
select is(testes.u('g2_empresa'), testes.u('empresa')::uuid, 'modo empresa: o grupo regista a empresa que paga');
select results_eq(format($$select cliente_id, taxa_entrega::int from pedidos where grupo_id = %L order by taxa_entrega desc$$, testes.u('g2')),
                  format($$values (%L::uuid, 301), (%L::uuid, 0)$$, testes.u('empresa'), testes.u('marta')),
                  'modo empresa: a taxa fica toda no pedido da empresa');

-- ---------------------------------------------------------------------------
-- Cancelar o grupo
-- ---------------------------------------------------------------------------
select testes.entrar(testes.u('gil'));
set local role authenticated;
with g as (insert into pedidos_grupo (ponto_entrega_id, hora_entrega, prazo_adesao, modo_pagamento)
           values (testes.u('escritorio'), now() + interval '3 hours', now() + interval '2 hours', 'individual') returning id)
select testes.def('g3', id) from g;
reset role;
select testes.entrar(testes.u('marta'));
set local role authenticated;
insert into pedidos (cliente_id, grupo_id, itens)
values (testes.u('marta'), testes.u('g3'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)));
reset role;
select testes.entrar(testes.u('gil'));
select is(cancelar_grupo(testes.u('g3'), 'Reunião adiada'), 1, 'o organizador cancela o grupo e os pedidos por preparar');
select testes.sair();
select results_eq(format($$select estado, motivo_cancelamento from pedidos where grupo_id = %L$$, testes.u('g3')),
                  $$values ('cancelado'::text, 'Reunião adiada'::text)$$, 'pedido do grupo cancelado com o motivo');

select testes.funcionalidade('pedidos_grupo', false);
select testes.entrar(testes.u('gil'));
select is((select count(*)::int from meus_grupos()), 0, 'interruptor desligado: sem grupos na app');
select testes.sair();

select * from finish();
rollback;
