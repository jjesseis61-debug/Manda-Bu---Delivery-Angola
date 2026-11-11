-- Relatório: tempo de cada etapa do pedido (horas no pedido e, nos antigos, pela auditoria).
begin;
\ir _helpers.psql
select plan(14);

with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Tempos', 'Rita') returning id)
  select testes.def('k', id) from k;
with k as (insert into cozinhas (nome, responsavel) values ('Outra Tempos', 'Olga') returning id)
  select testes.def('outra', id) from k;
with m as (insert into cardapio (cozinha_id, nome, preco) values (testes.u('k'), 'Muamba', 2000) returning id)
  select testes.def('muamba', id) from m;
select testes.def('gerente', testes.funcionario('Gerente Tempos', array['relatorios.exportar']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('gerente'), testes.u('k'));
select testes.def('alheio', testes.funcionario('Gerente Alheio', array['relatorios.exportar']));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('alheio'), testes.u('outra'));
select testes.def('estafeta', testes.funcionario('Estafeta Zé', array['entregas.registar']));
select testes.def('cli', testes.cliente('Cliente Tempos'));
select testes.def('casa', testes.ponto('residencial'));
select testes.def('caixa', testes.caixa(testes.u('k')));

create function testes.novo_pedido() returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, dispositivo_id, itens, subtotal, taxa_entrega)
  values (testes.u('cli'), testes.u('casa'), testes.u('k'), 'servidor',
          jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'nome', 'Muamba', 'qtd', 1, 'preco_unitario', 2000)),
          2000, 500)
  returning id into v;
  return v;
end $$;

-- 1) Pedido novo: cada transição grava a sua hora; à mão não se mexe
select testes.def('a', testes.novo_pedido());
update pedidos set estado = 'confirmado' where id = testes.u('a');
select ok((select confirmado_em is not null and saiu_em is null from pedidos where id = testes.u('a')), 'confirmar grava confirmado_em');
update pedidos set estado = 'em_preparacao' where id = testes.u('a');
update pedidos set estado = 'em_entrega' where id = testes.u('a');
select ok((select saiu_em is not null from pedidos where id = testes.u('a')), 'sair para entrega grava saiu_em');
update pedidos set confirmado_em = now() - interval '5 days' where id = testes.u('a');
select ok((select confirmado_em > now() - interval '1 minute' from pedidos where id = testes.u('a')), 'a hora não se altera à mão');
update pedidos set deletado_em = now() where id = testes.u('a'); -- fora do relatório

-- 2) Pedidos com horas conhecidas (B: horas no pedido; C: antigo, horas só na auditoria)
alter table pedidos disable trigger trg_pedidos_4_etapas;
select testes.def('b', testes.novo_pedido());
select testes.def('c', testes.novo_pedido());
update pedidos set estado = 'entregue_pago', caixa_id = testes.u('caixa'), entregador_id = testes.u('estafeta'),
       parcelas = jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', 2500))
 where id in (testes.u('b'), testes.u('c'));
-- B: 2 + 8 + 20 + 20 = 50 min, prometido para 45 → 5 min atrasado
-- (criado_em é protegido: as outras horas contam a partir dele)
update pedidos set confirmado_em = criado_em + interval '2 min',
       preparado_em = criado_em + interval '10 min', saiu_em = criado_em + interval '30 min',
       entregue_em = criado_em + interval '50 min', hora_prometida = criado_em + interval '45 min'
 where id = testes.u('b');
-- C: 4 + 6 + 10 + 8 = 28 min, a tempo
update pedidos set confirmado_em = null, preparado_em = null, saiu_em = null,
       entregue_em = criado_em + interval '28 min', hora_prometida = criado_em + interval '45 min'
 where id = testes.u('c');
alter table pedidos enable trigger trg_pedidos_4_etapas;
insert into auditoria (dispositivo_id, acao, detalhe, ref_id, ref_tipo, data)
values ('servidor', 'pedido_estado', '{"de":"pendente","para":"confirmado"}', testes.u('c'), 'pedidos', (select criado_em from pedidos where id = testes.u('c')) + interval '4 min'),
       ('servidor', 'pedido_estado', '{"de":"confirmado","para":"em_preparacao"}', testes.u('c'), 'pedidos', (select criado_em from pedidos where id = testes.u('c')) + interval '10 min'),
       ('servidor', 'pedido_estado', '{"de":"em_preparacao","para":"em_entrega"}', testes.u('c'), 'pedidos', (select criado_em from pedidos where id = testes.u('c')) + interval '20 min'),
       ('servidor', 'pedido_estado', 'texto antigo sem json', testes.u('c'), 'pedidos', (select criado_em from pedidos where id = testes.u('c')) + interval '21 min');

-- 3) Relatório (como o gerente da cozinha)
select testes.entrar_funcionario(testes.u('gerente'));
set local role authenticated;
create temp table r as select tempos_etapas_cozinha(testes.u('k'), current_date - 1, current_date + 1) as j;
reset role;
select is((select (j ->> 'pedidos')::int from r), 2, 'conta os 2 pedidos entregues (sem o apagado)');
select results_eq($$select e ->> 'chave', (e ->> 'mediana')::numeric from r, jsonb_array_elements(j -> 'etapas') e$$,
                  $$values ('confirmar', 3.0), ('comecar', 7.0), ('preparar', 15.0), ('entregar', 14.0), ('total', 39.0)$$,
                  'medianas por etapa (C pela auditoria)');
select is((select j ->> 'gargalo' from r), 'preparar', 'a etapa que mais pesa');
select is((select (e ->> 'p90')::numeric from r, jsonb_array_elements(j -> 'etapas') e where e ->> 'chave' = 'total'), 47.8,
          'p90 do total');
select results_eq($$select (j -> 'pontualidade' ->> 'a_tempo')::int, (j -> 'pontualidade' ->> 'atrasados')::int,
                           (j -> 'pontualidade' ->> 'atraso_mediano')::numeric from r$$,
                  $$values (1, 1, 5.0)$$, 'pontualidade: 1 a tempo, 1 atrasado 5 min');
select is((select (e ->> 'entregas')::int from r, jsonb_array_elements(j -> 'estafetas') e where e ->> 'nome' = 'Estafeta Zé'), 2,
          'entregas por estafeta');
select is((select (j -> 'mais_lentos' -> 0 ->> 'pedido_id')::uuid from r), testes.u('b')::uuid, 'o pedido mais lento primeiro');
select is((select j -> 'mais_lentos' -> 0 ->> 'etapa' from r), 'preparar', 'e onde perdeu tempo');
select ok((select jsonb_array_length(j -> 'por_hora') between 1 and 2 from r), 'agrupa por hora do dia');

-- 4) Permissões
select testes.sair();
select testes.entrar_funcionario(testes.u('alheio'));
set local role authenticated;
select throws_ok(format('select tempos_etapas_cozinha(%L, current_date - 1, current_date)', testes.u('k')), '42501', null,
                 'gerente de outra cozinha não vê');
reset role; select testes.sair();
select testes.entrar(testes.u('cli'));
set local role authenticated;
select throws_ok(format('select tempos_etapas_cozinha(%L, current_date - 1, current_date)', testes.u('k')), '42501', null,
                 'o cliente não vê');
reset role; select testes.sair();

select * from finish();
rollback;
