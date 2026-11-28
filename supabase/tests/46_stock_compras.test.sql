-- Agente de stock e compras: saldos, consumo, cobertura e validades ainda em stock (FIFO); preços por fornecedor;
-- compras do dia; reconciliação das distribuições; procura; planos (job, pedido na app, limite, permissões);
-- plano validado com N28; marcar compras; erros; interruptor
begin;
\ir _helpers.psql
select plan(17);

select testes.funcionalidade('agente_compras', true);
select testes.funcionalidade('multi_cozinha', true);
select testes.def('cz', cozinha_padrao());
with c as (insert into cozinhas (nome, responsavel) values ('Cozinha do Kilamba', 'Rosa') returning id) select testes.def('outra', id) from c;
select testes.def('sara', testes.funcionario('Sara Stock', array['stock.gerir']));
select testes.def('olga', testes.funcionario('Olga Stock', array['stock.gerir']));
select testes.def('gil', testes.funcionario('Gil Gerente', array['pedidos.gerir']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('sara'), testes.u('cz')),
                                                           (current_date, testes.u('olga'), testes.u('outra')),
                                                           (current_date, testes.u('gil'), testes.u('cz'));
with p as (insert into produtos (nome, categoria, tipo_estoque, categoria_medida, unidade_compra, custo)
           values ('Arroz agulha', 'Mercearia', 'Longo Prazo', 'Peso', 'kg', 1100) returning id) select testes.def('arroz', id) from p;
with p as (insert into produtos (nome, categoria, tipo_estoque, categoria_medida, unidade_compra, custo)
           values ('Óleo de palma', 'Mercearia', 'Longo Prazo', 'Volume', 'l', 2500) returning id) select testes.def('oleo', id) from p;
with p as (insert into produtos (nome, categoria, tipo_estoque, categoria_medida, unidade_compra, custo)
           values ('Feijão', 'Mercearia', 'Longo Prazo', 'Peso', 'kg', 900) returning id) select testes.def('feijao', id) from p;

-- Arroz: 20 kg há 20 dias (Mercado A, 1000 Kz/kg, validade daqui a 3 dias) e 10 kg há 3 dias (Mercado B,
-- 1200 Kz/kg, validade daqui a 5 dias); consumo de 1 kg por dia nos últimos 20 dias -> saldo 10 kg
insert into estoque_longo_prazo (cozinha_id, produto_id, tipo, quantidade, custo_total, fornecedor, validade, data) values
  (testes.u('cz'), testes.u('arroz'), 'Entrada', 20000, 20000, 'Mercado A', current_date + 3, now() - interval '20 days'),
  (testes.u('cz'), testes.u('arroz'), 'Entrada', 10000, 12000, 'Mercado B', current_date + 5, now() - interval '3 days'),
  (testes.u('cz'), testes.u('oleo'), 'Entrada', 5000, 12500, 'Mercado A', null, now() - interval '10 days'),
  (testes.u('outra'), testes.u('feijao'), 'Entrada', 8000, 7200, 'Mercado C', null, now() - interval '2 days');
insert into estoque_longo_prazo (cozinha_id, produto_id, tipo, quantidade, data)
select testes.u('cz'), testes.u('arroz'), 'Consumo', 1000, now() - make_interval(days => i) from generate_series(1, 20) i;

-- Ferramentas
select testes.def('saldos', stk_saldos(testes.u('cz')));
create function pg_temp.saldo(p text) returns jsonb language sql as $$
  select e from jsonb_array_elements(testes.v('saldos')::jsonb) e where e ->> 'produto_id' = testes.v(p);
$$;
select ok(jsonb_array_length(testes.v('saldos')::jsonb) = 2 and pg_temp.saldo('feijao') is null
          and (pg_temp.saldo('arroz') ->> 'saldo')::numeric = 10000 and (pg_temp.saldo('arroz') ->> 'consumo_28d')::numeric = 20000
          and (pg_temp.saldo('arroz') ->> 'dias_de_cobertura')::numeric between 10 and 11
          and pg_temp.saldo('arroz') ->> 'unidade_base' = 'g' and (pg_temp.saldo('arroz') ->> 'unidade_compra_em_base')::numeric = 1000,
          'saldos da cozinha: arroz com 10 kg, consumo de 4 semanas e cerca de 10 dias de cobertura (o feijão é de outra cozinha)');
select ok(jsonb_array_length(pg_temp.saldo('arroz') -> 'validades_em_stock') = 1
          and (pg_temp.saldo('arroz') -> 'validades_em_stock' -> 0 ->> 'validade')::date = current_date + 5
          and (pg_temp.saldo('arroz') -> 'validades_em_stock' -> 0 ->> 'quantidade_ainda_em_stock')::numeric = 10000,
          'validades: só a da entrada que ainda está em stock (a mais antiga já foi consumida)');
select ok(pg_temp.saldo('oleo') ->> 'dias_de_cobertura' is null and (pg_temp.saldo('oleo') ->> 'saldo')::numeric = 5000
          and pg_temp.saldo('oleo') ->> 'unidade_base' = 'ml', 'produto sem consumo: sem cobertura calculada');
select testes.def('precos', stk_precos(testes.u('arroz')));
select ok(jsonb_array_length(testes.v('precos')::jsonb -> 'compras') = 2
          and (testes.v('precos')::jsonb -> 'compras' -> 0 ->> 'preco_por_unidade_compra')::numeric = 1200
          and testes.v('precos')::jsonb -> 'compras' -> 0 ->> 'fornecedor' = 'Mercado B'
          and (testes.v('precos')::jsonb -> 'compras' -> 1 ->> 'preco_por_unidade_compra')::numeric = 1000,
          'preços por unidade de compra e fornecedor, do mais recente para o mais antigo');
select is((select count(*)::int from jsonb_array_elements(stk_consumo_diario(testes.u('cz'), testes.u('arroz'), 7) -> 'dias') d
            where (d ->> 'consumo')::numeric = 1000), 6, 'consumo dia a dia (os 6 dias anteriores a hoje com 1 kg)');

-- Distribuição de ontem: 2 kg enviados, 0,5 kg devolvidos, 1 kg consumido -> 0,5 kg sem explicação
insert into distribuicoes (cozinha_id, produto_id, quantidade, unidade, quantidade_devolvida, criado_em)
values (testes.u('cz'), testes.u('arroz'), 2, 'kg', 0.5, now() - interval '1 day');
select is((stk_reconciliacao(testes.u('cz'), 7) -> 0 ->> 'diferenca_nao_explicada')::numeric, 500.0,
          'reconciliação: enviado − devolvido − quebra − consumido = 500 g sem explicação');

insert into estoque_diario (cozinha_id, produto, qtd_comprada, custo_total, data) values (testes.u('cz'), 'Peixe carapau', 5, 15000, current_date);
insert into vendas (cozinha_id, produto, qtd, valor_total, data) values (testes.u('cz'), 'Calulu', 3, 10500, now());
with b as (insert into pratos_base (nome, componentes, cozinha_id)
           values ('Calulu', jsonb_build_array(jsonb_build_object('produto_id', testes.v('arroz'), 'quantidade', 200, 'unidade', 'g')), testes.u('cz'))
           returning id)
insert into cardapio (cozinha_id, nome, preco, prato_base_id) select testes.u('cz'), 'Calulu', 3500, id from b;
insert into pre_encomendas (cozinha_id, produto, qtd, hora_prevista, status) values
  (testes.u('cz'), 'Calulu', 20, now() + interval '1 day', 'Pendente'),
  (testes.u('cz'), 'Muamba', 10, now() + interval '2 days', 'Cancelada');
select testes.def('procura', stk_procura(testes.u('cz')));
select ok((stk_compras_diarias(testes.u('cz'), 7) -> 'compras' -> 0 ->> 'produto') = 'Peixe carapau'
          and (stk_compras_diarias(testes.u('cz'), 7) -> 'pratos_vendidos_por_dia' -> 0 ->> 'pratos')::numeric = 3
          and jsonb_array_length(testes.v('procura')::jsonb -> 'encomendas_marcadas') = 1
          and (testes.v('procura')::jsonb -> 'receitas_dos_pratos_disponiveis' -> 0 -> 'por_porcao' -> 0 ->> 'quantidade_base')::numeric = 200,
          'compras do dia com os pratos vendidos; procura com as encomendas (sem as canceladas) e as receitas');

-- Planos: job diário, pedido na app, permissões
select is(job_planos_compras(), 2, 'job: um plano por cozinha com movimentos de stock');
select testes.entrar_funcionario(testes.u('gil'));
set local role authenticated;
select testes.def('e_gil', testes.erro(format($$select pedir_plano_compras(%L)$$, testes.v('cz'))));
reset role;
select testes.entrar_funcionario(testes.u('sara'));
set local role authenticated;
select testes.def('pedido', pedir_plano_compras(testes.u('cz')));
reset role;
select testes.sair();
select ok(testes.v('e_gil') like '42501:%'
          and testes.v('pedido') = (select id::text from planos_compras where cozinha_id = testes.u('cz') and origem = 'automatico')
          and (select count(*) from planos_compras where cozinha_id = testes.u('outra')) = 1,
          'só quem trata do stock pede; com um plano por preparar, não se cria outro');

-- Reserva e plano entregue
select testes.def('reserva', reservar_plano_compras(testes.u('pedido')));
select ok(testes.v('reserva')::jsonb ->> 'cozinha_id' = testes.v('cz')
          and jsonb_array_length(testes.v('reserva')::jsonb -> 'saldos') = 2
          and reservar_plano_compras(testes.u('pedido')) is null,
          'reserva o plano com os saldos e a procura (uma vez)');
select registar_plano_compras(testes.u('pedido'), 'pronto', jsonb_build_object(
  'resumo', 'O arroz chega para 10 dias; comprar peixe hoje.',
  'compras', jsonb_build_array(
    jsonb_build_object('produto_id', testes.v('arroz'), 'quantidade', 10, 'urgencia', 'esta_semana', 'custo_estimado', 10000,
                       'fornecedor', 'Mercado A', 'motivo', 'Cobertura de 10 dias; o Mercado A foi mais barato.'),
    jsonb_build_object('produto_id', null, 'produto_nome', 'Peixe carapau', 'quantidade', 5, 'unidade', 'kg', 'urgencia', 'hoje',
                       'motivo', 'Compra diária para o calulu.'),
    jsonb_build_object('produto_id', gen_random_uuid(), 'quantidade', 3, 'urgencia', 'hoje', 'motivo', 'produto que não existe'),
    jsonb_build_object('produto_id', testes.v('oleo'), 'quantidade', 0, 'urgencia', 'hoje', 'motivo', 'quantidade zero'),
    jsonb_build_object('produto_id', testes.v('oleo'), 'quantidade', 2, 'urgencia', 'ontem', 'motivo', 'urgência estranha')),
  'alertas', jsonb_build_array(
    jsonb_build_object('tipo', 'desvio', 'gravidade', 'alta', 'produto_id', testes.v('arroz'), 'texto', 'Faltam 500 g de arroz de ontem.'),
    jsonb_build_object('tipo', 'apagar', 'gravidade', 'alta', 'texto', 'tipo estranho'))),
  '[]', null);
select ok((select jsonb_array_length(compras) = 2 and compras -> 0 ->> 'produto' = 'Peixe carapau' and compras -> 1 ->> 'unidade' = 'kg'
                  and jsonb_array_length(alertas) = 1 and estado = 'pronto'
             from planos_compras where id = testes.u('pedido')),
          'guarda só as compras e alertas válidos (produto que não existe, quantidade zero ou tipo estranho não entram), urgentes primeiro');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N28' and funcionario_id = testes.u('sara')),
          format('Compras na %s: 1 produto a comprar hoje e 1 alerta grave. Abre o plano de compras.', (select trim(nome) from cozinhas where id = testes.u('cz'))),
          'N28 a quem trata do stock da cozinha');
select ok(not exists (select 1 from notificacoes_fila where codigo = 'N28' and funcionario_id in (testes.u('olga'), testes.u('gil'))),
          'nem o stock de outra cozinha nem o gerente sem stock.gerir são avisados');

-- Marcar compras
select testes.entrar_funcionario(testes.u('olga'));
set local role authenticated;
select testes.def('lista_olga', jsonb_array_length(planos_compras_lista()));
select testes.def('e_olga', testes.erro(format($$select marcar_compra(%L, 0, 'comprado')$$, testes.v('pedido'))));
reset role;
select testes.entrar_funcionario(testes.u('sara'));
set local role authenticated;
select testes.def('lista_sara', planos_compras_lista());
select marcar_compra(testes.u('pedido'), 0, 'comprado');
select testes.def('e_indice', testes.erro(format($$select marcar_compra(%L, 5, 'comprado')$$, testes.v('pedido'))));
reset role;
select testes.sair();
select ok(testes.v('lista_olga') = '1' and testes.v('e_olga') like '42501:%'
          and jsonb_array_length(testes.v('lista_sara')::jsonb) = 1,
          'cada um vê e marca só os planos das suas cozinhas');
select ok((select compras -> 0 ->> 'estado' = 'comprado' and compras -> 0 ->> 'decidido_por' = 'Sara Stock' from planos_compras where id = testes.u('pedido'))
          and testes.v('e_indice') = 'P0001:dados_invalidos'
          and exists (select 1 from auditoria where acao = 'compra_comprado' and funcionario_nome = 'Sara Stock'),
          'marcar como comprado guarda quem e quando (e fica na auditoria)');

-- Erros, limite diário e interruptor
select testes.def('outro', (select id from planos_compras where cozinha_id = testes.u('outra')));
select registar_plano_compras(testes.u('outro'), 'erro', null, '[]', 'falha 1');
select registar_plano_compras(testes.u('outro'), 'erro', null, '[]', 'falha 2');
select testes.def('r3', registar_plano_compras(testes.u('outro'), 'erro', null, '[]', 'falha 3'));
update parametros set compras_pedidos_dia = 1 where unico;
select testes.entrar_funcionario(testes.u('sara'));
set local role authenticated;
select testes.def('novo', pedir_plano_compras(testes.u('cz')));
select testes.def('e_limite', testes.erro(format($$select pedir_plano_compras(%L)$$, testes.v('cz'))));
reset role;
select testes.sair();
select ok(testes.v('r3') = 'indisponivel' and testes.v('novo') is not null and testes.v('novo') <> testes.v('pedido')
          and testes.v('e_limite') = 'P0001:limite_diario',
          'três erros = indisponível; limite de pedidos por dia');

select testes.funcionalidade('agente_compras', false);
select ok(reservar_plano_compras() is null and job_planos_compras() = 0
          and not has_function_privilege('authenticated', 'stk_saldos(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'registar_plano_compras(uuid, text, jsonb, jsonb, text)', 'execute'),
          'interruptor desligado = parado; as ferramentas só o serviço as chama');

select * from finish();
rollback;
