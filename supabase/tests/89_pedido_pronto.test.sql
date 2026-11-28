-- Pedido "Pronto": a cozinha marca, o estafeta reservado é avisado e o relatório separa a espera.
begin;
\ir _helpers.psql
select plan(11);

with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Pronto', 'Rita') returning id)
  select testes.def('k', id) from k;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Muamba', 2000) returning id)
  select testes.def('muamba', id) from m;
select testes.def('gerente', testes.funcionario('Gerente Pronto', array['pedidos.gerir', 'relatorios.exportar']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('k'));
select testes.def('estafeta', testes.funcionario('Estafeta Rui', array['entregas.registar']));
select testes.def('cli', testes.cliente('Cliente Pronto'));
select testes.def('casa', testes.ponto('residencial'));
select testes.def('caixa', testes.caixa(testes.u('k')));

insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, dispositivo_id, itens, subtotal, taxa_entrega)
values (testes.u('cli'), testes.u('casa'), testes.u('k'), 'servidor',
        jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'nome', 'Muamba', 'qtd', 1, 'preco_unitario', 2000)),
        2000, 500)
returning id as p \gset
select testes.def('p', :'p'::uuid);
update pedidos set estado = 'confirmado', atribuido_a = testes.u('estafeta'), atribuido_em = now() where id = testes.u('p');

-- 1) Só em preparação
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
select throws_ok(format('select marcar_pedido_pronto(%L)', testes.u('p')), 'P0001', 'pedido_nao_em_preparacao',
                 'só se marca pronto um pedido em preparação');
reset role;
update pedidos set estado = 'em_preparacao' where id = testes.u('p');
set local role authenticated;
select lives_ok(format('select marcar_pedido_pronto(%L)', testes.u('p')), 'o gerente marca pronto');
reset role;
select ok((select pronto_em is not null from pedidos where id = testes.u('p')), 'grava a hora');
select is((select count(*)::int from notificacoes_fila where funcionario_id = testes.u('estafeta') and codigo = 'N32'
            and dados ->> 'titulo' = 'Pedido pronto ✅'), 1, 'o estafeta reservado é avisado');
set local role authenticated;
select lives_ok(format('select marcar_pedido_pronto(%L)', testes.u('p')), 'marcar outra vez não faz nada');
select ok((select pronto_em is not null from pedidos_operador() where pedido_id = testes.u('p')), 'a lista de pedidos mostra pronto');
reset role; select testes.sair();
select is((select count(*)::int from notificacoes_fila where funcionario_id = testes.u('estafeta') and codigo = 'N32'
            and dados ->> 'titulo' = 'Pedido pronto ✅'), 1, 'sem aviso repetido');

-- 2) À mão não se mexe
update pedidos set pronto_em = now() - interval '3 days' where id = testes.u('p');
select ok((select pronto_em > now() - interval '1 minute' from pedidos where id = testes.u('p')), 'pronto_em só pelo servidor');

-- 3) Quem não é da cozinha não marca
select testes.def('outro', testes.funcionario('Outro Gerente', array['pedidos.gerir']));
select testes.entrar_funcionario(testes.u('outro'));
set local role authenticated;
select throws_ok(format('select marcar_pedido_pronto(%L, false)', testes.u('p')), '42501', null, 'gerente de fora não mexe');
reset role; select testes.sair();

-- 4) Relatório: preparar e esperar separados
alter table pedidos disable trigger trg_pedidos_4_etapas;
update pedidos set estado = 'entregue_pago', caixa_id = testes.u('caixa'), entregador_id = testes.u('estafeta'),
       parcelas = jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', 2500)),
       confirmado_em = criado_em + interval '1 min', preparado_em = criado_em + interval '3 min',
       pronto_em = criado_em + interval '15 min', saiu_em = criado_em + interval '25 min',
       entregue_em = criado_em + interval '40 min', hora_prometida = criado_em + interval '45 min'
 where id = testes.u('p');
alter table pedidos enable trigger trg_pedidos_4_etapas;
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
create temp table r as select tempos_etapas_cozinha(testes.u('k'), current_date - 1, current_date + 1) as j;
reset role; select testes.sair();
select results_eq($$select e ->> 'chave', (e ->> 'mediana')::numeric from r, jsonb_array_elements(j -> 'etapas') e$$,
                  $$values ('confirmar', 1.0), ('comecar', 2.0), ('preparar', 12.0), ('esperar', 10.0), ('entregar', 15.0), ('total', 40.0)$$,
                  'preparar (12) e esperar o estafeta (10) separados');
select is((select (j ->> 'com_pronto')::int from r), 1, 'conta os pedidos com Pronto marcado');

select * from finish();
rollback;
