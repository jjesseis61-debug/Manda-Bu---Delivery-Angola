-- Relatório Fase 3: custo dos pratos (e das opções), margem, despesas e doses (esgotados/sobras).
begin;
\ir _helpers.psql
select plan(16);
select testes.funcionalidade('pratos_montaveis', true);

with k as (insert into cozinhas (nome, responsavel, comissao_percent) values ('Cozinha Margem', 'Rita', 10) returning id)
  select testes.def('k', id) from k;
with k as (insert into cozinhas (nome, responsavel) values ('Outra Margem', 'Olga') returning id)
  select testes.def('outra', id) from k;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('outra'), 'Prato da outra', 1500) returning id)
  select testes.def('prato_outra', id) from m;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Calulu', 2000) returning id)
  select testes.def('calulu', id) from m;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Monta', 0) returning id)
  select testes.def('monta', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('monta'), 'Base', 1, 2) returning id)
  select testes.def('g', id) from g;
with o as (insert into opcoes (grupo_id, nome, preco_extra) values (testes.u('g'), 'Arroz', 700) returning id)
  select testes.def('arroz', id) from o;
with o as (insert into opcoes (grupo_id, nome, preco_extra) values (testes.u('g'), 'Frango', 1200) returning id)
  select testes.def('frango', id) from o;

select testes.def('gerente', testes.funcionario('Gerente Margem', array['relatorios.exportar', 'cardapio.gerir']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('k'));
select testes.def('cli', testes.cliente('Cliente Margem'));
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('ZonaMargem', 'Própria', 500, 'Fixo') returning id)
  select testes.def('zona', id) from z;
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
select testes.def('caixa', testes.caixa(testes.u('k')));

-- 1) Custos (como o gerente da cozinha)
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select definir_custo_item(testes.u('calulu'), 1200);
select definir_custo_item(testes.u('arroz'), 300);
select definir_custo_item(testes.u('frango'), 800);
select is((select custo from custos_da_cozinha(testes.u('k')) where item_id = testes.u('calulu')), 1200, 'o gerente vê o custo do prato');
select is((select count(*)::int from custos_da_cozinha(testes.u('k')) where tipo = 'opcao' and custo is not null), 2, 'e o das opções');
select throws_ok(format('select definir_custo_item(%L, 100)', testes.u('prato_outra')),
                 '42501', null, 'não mexe nos custos de outra cozinha');
select isnt(lancar_despesa(testes.u('k'), testes.hoje(), 'Gás', 'Botija', 3000), null, 'lança uma despesa da cozinha');
reset role; select testes.sair();

-- O cliente nunca vê custos
select testes.entrar(testes.u('cli'));
set local role authenticated;
select is((select count(*)::int from custos_cardapio), 0, 'o cliente não lê a tabela de custos');
select throws_ok(format('select * from custos_da_cozinha(%L)', testes.u('k')), '42501', null, 'nem a lista de custos');
reset role; select testes.sair();

-- 2) Doses: Calulu com 3 doses hoje
update cardapio set doses_dia = 3 where id = testes.u('calulu');

-- 3) Vendas: 2 Calulu + 1 Calulu + 1 montável (Arroz + Frango)
-- Itens no formato que o servidor grava (preço unitário e opções completas)
create function testes.entregar(p_itens jsonb) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, dispositivo_id, itens, subtotal, taxa_entrega)
  values (testes.u('cli'), testes.u('casa'), testes.u('k'), 'servidor', p_itens,
          (select sum((i ->> 'qtd')::int * (i ->> 'preco_unitario')::int) from jsonb_array_elements(p_itens) i), 500)
  returning id into v;
  update pedidos set estado = 'entregue_pago', entregue_em = now(), caixa_id = testes.u('caixa'),
         parcelas = jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro',
                      'valor', subtotal + taxa_entrega - desconto_indicacao))
   where id = v;
  return v;
end $$;
select testes.entregar(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('calulu'), 'nome', 'Calulu', 'qtd', 2, 'preco_unitario', 2000)));
select testes.entregar(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('calulu'), 'nome', 'Calulu', 'qtd', 1, 'preco_unitario', 2000)));
select testes.entregar(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('monta'), 'nome', 'Monta (Arroz, Frango)',
         'qtd', 1, 'preco_unitario', 1900,
         'opcoes', jsonb_build_array(jsonb_build_object('id', testes.u('arroz'), 'nome', 'Arroz', 'preco_extra', 700),
                                     jsonb_build_object('id', testes.u('frango'), 'nome', 'Frango', 'preco_extra', 1200)))));

select is(registar_doses_dia(), 1, 'guarda o dia do prato com doses');
select results_eq(format($$select lancadas, vendidas, sobras, esgotou_em is not null from doses_historico where cardapio_id = %L$$, testes.u('calulu')),
                  $$values (3, 3, 0, true)$$, 'Calulu: 3 lançadas, 3 vendidas, 0 sobras, esgotou');
select is(registar_doses_dia(), 1, 'correr outra vez não duplica');

-- 4) Rentabilidade (como o gerente)
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select testes.def('r', rentabilidade_cozinha(testes.u('k'), testes.hoje(), testes.hoje())::text);
reset role; select testes.sair();

select is((testes.v('r')::jsonb ->> 'vendas_comida')::int, 7900, 'vendas de comida: 3 × 2000 + 1900');
select is((testes.v('r')::jsonb ->> 'cmv')::int, 4700, 'custo dos pratos: 3 × 1200 + 300 + 800');
select is((testes.v('r')::jsonb ->> 'cobertura_pct')::numeric, 100.0, 'todas as vendas têm custo');
select is((testes.v('r')::jsonb ->> 'margem_bruta')::int, 3200, 'margem bruta = 7900 − 4700');
select is((testes.v('r')::jsonb ->> 'despesas')::int, 3000, 'despesas do período');
select is((testes.v('r')::jsonb ->> 'resultado')::int, 7110 - 4700 - 3000,
          'resultado = a receber (7900 − 10%) − custo − despesas');
select is((testes.v('r')::jsonb #>> '{doses,0,dias_esgotou}')::int, 1, 'o relatório mostra o dia em que esgotou');

select * from finish();
rollback;
