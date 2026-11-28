-- Relatório da cozinha detalhado: valores conhecidos, comissão, período anterior, permissões
-- (o gerente só vê a sua cozinha) e o fecho do dia (N42).
begin;
\ir _helpers.psql
select plan(24);

-- Cozinha com 10% de comissão, um prato simples (2000) e um montável
with k as (insert into cozinhas (nome, responsavel, comissao_percent) values ('Cozinha Relatório', 'Rita', 10) returning id)
  select testes.def('k', id) from k;
with k as (insert into cozinhas (nome, responsavel) values ('Outra Cozinha', 'Olga') returning id)
  select testes.def('outra', id) from k;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Calulu', 2000) returning id)
  select testes.def('calulu', id) from m;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Sem saída', 1500) returning id)
  select testes.def('parado', id) from m;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaRel', 'Própria', 500, 'Fixo') returning id)
  select testes.def('zona', id) from z;
select testes.def('ana', testes.cliente('Ana Rel'));
select testes.def('bea', testes.cliente('Bea Rel'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));

select testes.def('caixa', testes.caixa(testes.u('k')));

-- Pedidos de hoje (Luanda): dois entregues (2 e 1 Calulu), um cancelado pela cozinha
create function testes.vendido(p_cli uuid, p_qtd int, p_metodo text, p_desconto int default 0) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, dispositivo_id, estado, itens, subtotal, taxa_entrega,
                       desconto_indicacao)
  values (p_cli, testes.u('casa'), testes.u('k'), 'servidor', 'pendente',
          jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('calulu'), 'nome', 'Calulu', 'qtd', p_qtd,
                                               'preco_unitario', 2000)),
          2000 * p_qtd, 500, p_desconto)
  returning id into v;
  update pedidos set estado = 'entregue_pago', subtotal = 2000 * p_qtd, taxa_entrega = 500, desconto_indicacao = p_desconto,
         hora_prometida = now() + interval '30 minutes', entregue_em = now(), caixa_id = testes.u('caixa'),
         parcelas = jsonb_build_array(jsonb_build_object('metodo', p_metodo, 'valor', 2000 * p_qtd + 500 - p_desconto))
   where id = v;
  return v;
end $$;
select testes.def('p1', testes.vendido(testes.u('ana'), 2, 'Dinheiro', 500));
select testes.def('p2', testes.vendido(testes.u('bea'), 1, 'Dinheiro'));
insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, dispositivo_id, subtotal, estado, cancelado_por, motivo_cancelamento)
values (testes.u('ana'), testes.u('casa'), testes.u('k'), 'servidor', 3000, 'cancelado', 'cozinha', 'Acabou um ingrediente');

select testes.def('gerente', testes.funcionario('Gerente Rel', array['relatorios.exportar', 'pedidos.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('k'));
select testes.def('sem', testes.funcionario('Sem Relatórios', array['pedidos.gerir']));

-- 1) Valores (como o gerente da cozinha)
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('r', relatorio_cozinha_detalhado(testes.u('k'), testes.hoje(), testes.hoje())::text);
reset role; select testes.sair();

select is((testes.v('r')::jsonb #>> '{resumo,pedidos}')::int, 2, 'dois pedidos entregues');
select is((testes.v('r')::jsonb #>> '{resumo,vendas_brutas}')::int, 6000, 'vendas brutas = 3 Calulu');
select is((testes.v('r')::jsonb #>> '{resumo,ticket_medio}')::int, 3000, 'ticket médio');
select is((testes.v('r')::jsonb #>> '{resumo,desconto_convite}')::int, 500, 'desconto de convite');
select is((testes.v('r')::jsonb #>> '{resumo,taxas_entrega}')::int, 1000, 'taxas de entrega à parte');
select is((testes.v('r')::jsonb #>> '{resumo,comissao}')::int, 600, 'comissão de 10% sobre a comida');
select is((testes.v('r')::jsonb #>> '{resumo,a_receber_cozinha}')::int, 5400,
          'a receber pela cozinha: vendas − comissão (o desconto é da plataforma)');
select is((testes.v('r')::jsonb #>> '{resumo,cancelados}')::int, 1, 'um cancelado');
select is((testes.v('r')::jsonb #>> '{resumo,cancelados_cozinha}')::int, 1, 'cancelado pela cozinha');
select is((testes.v('r')::jsonb #>> '{resumo,clientes_novos}')::int, 2, 'dois clientes novos');
select is((testes.v('r')::jsonb #>> '{resumo,a_horas_pct}')::numeric, 100.0, 'todos a horas');
select is((testes.v('r')::jsonb #>> '{pratos,0,qtd}')::int, 3, 'Calulu: 3 vendidos');
select ok((testes.v('r')::jsonb -> 'sem_vendas') ? 'Sem saída', 'lista os pratos sem vendas');
select is((select (e ->> 'valor')::int from jsonb_array_elements(testes.v('r')::jsonb -> 'pagamentos') e
            where e ->> 'metodo' = 'Dinheiro'), 6500, 'dinheiro recebido (comida + entrega − desconto)');
select is((testes.v('r')::jsonb #>> '{cancelamentos_motivos,0,motivo}'), 'Acabou um ingrediente', 'motivo do cancelamento');
select is((testes.v('r')::jsonb #>> '{anterior,pedidos}')::int, 0, 'o período anterior não tem pedidos');

-- 1b) Convida por cozinha: 100% cozinha -> os 500 saem do valor; 50% -> 250
update cozinhas set convida_cozinha_percent = 100 where id = testes.u('k');
select is((resumo_cozinha(testes.u('k'), testes.hoje()::timestamp at time zone 'Africa/Luanda',
                          (testes.hoje() + 1)::timestamp at time zone 'Africa/Luanda') ->> 'a_receber_cozinha')::int,
          4900, 'Convida pago pela cozinha: 6000 − 600 − 500');
update cozinhas set convida_cozinha_percent = 50 where id = testes.u('k');
select is((resumo_cozinha(testes.u('k'), testes.hoje()::timestamp at time zone 'Africa/Luanda',
                          (testes.hoje() + 1)::timestamp at time zone 'Africa/Luanda') ->> 'convida_a_cargo_cozinha')::int,
          250, 'metade do Convida a cargo da cozinha');
update cozinhas set convida_cozinha_percent = 0 where id = testes.u('k');

-- 2) Permissões: o gerente não vê outra cozinha; sem relatorios.exportar não vê nada
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select throws_ok(format('select relatorio_cozinha_detalhado(%L, %L, %L)', testes.u('outra'), testes.hoje(), testes.hoje()),
                 '42501', null, 'o gerente não vê o relatório de outra cozinha');
reset role; select testes.sair();
select testes.entrar_funcionario(testes.u('sem'));
set local role authenticated;
select throws_ok(format('select relatorio_cozinha_detalhado(%L, %L, %L)', testes.u('k'), testes.hoje(), testes.hoje()),
                 '42501', null, 'sem relatorios.exportar não vê');
reset role; select testes.sair();

-- 2b) Comissão: o gerente (com cozinhas.gerir) não a muda; o admin da plataforma sim
select testes.def('gestor', testes.funcionario('Gestor Coz', array['cozinhas.gerir']));
select testes.def('plataforma', testes.funcionario('Plataforma', array['plataforma.parametros']));
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select throws_ok(format('update cozinhas set comissao_percent = 0 where id = %L', testes.u('k')),
                 '42501', null, 'quem gere cozinhas não altera a comissão');
reset role; select testes.sair();
select testes.entrar_funcionario(testes.u('plataforma'));
set local role authenticated;
select definir_comissao_cozinha(testes.u('k'), 12.5);
reset role; select testes.sair();
select is((select comissao_percent from cozinhas where id = testes.u('k')), 12.50, 'o admin da plataforma define a comissão');
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select throws_ok(format('update cozinhas set convida_cozinha_percent = 100 where id = %L', testes.u('k')),
                 '42501', null, 'quem gere cozinhas não muda quem paga o Convida');
reset role; select testes.sair();
update cozinhas set comissao_percent = 10 where id = testes.u('k');

-- 3) Fecho do dia: aviso N42 ao gerente da cozinha
select job_fecho_dia();
select ok(exists (select 1 from notificacoes_fila where codigo = 'N42' and funcionario_id = testes.u('gerente')
                   and dados ->> 'cozinha_id' = testes.v('k') and (dados ->> 'a_receber')::int = 5400),
          'o gerente recebe o fecho do dia com o valor a receber');

select * from finish();
rollback;
