-- Teste das fotografias do Início com grupo de controlo: grupo fixo por cliente, visitas e tempo até
-- ao primeiro «Adicionar», interruptor, e o resultado por grupo pelos pedidos reais.
begin;
\ir _helpers.psql
select plan(14);

-- Clientes de teste: o primeiro que cai em A e o primeiro em B
do $$
declare
  c uuid;
  i int;
begin
  for i in 1..40 loop
    c := testes.cliente('Teste fotos ' || i);
    if variante_experiencia('fotos_inicio', c) = 'A' and testes.v('ca') is null then perform testes.def('ca', c); end if;
    if variante_experiencia('fotos_inicio', c) = 'B' and testes.v('cb') is null then perform testes.def('cb', c); end if;
  end loop;
end $$;
select ok(testes.u('ca') is not null and testes.u('cb') is not null, 'em 40 clientes há gente nos dois grupos');
select is(variante_experiencia('fotos_inicio', testes.u('ca')), variante_experiencia('fotos_inicio', testes.u('ca')), 'o grupo de cada cliente é sempre o mesmo');

-- Interruptor desligado: não regista e a app fica com o desenho novo (B)
select testes.funcionalidade('teste_fotos_inicio', false);
select testes.entrar(testes.u('ca'));
set local role authenticated;
select testes.def('off', coalesce(visita_experiencia('fotos_inicio'), 'nulo'));
reset role;
select is(testes.v('off'), 'nulo', 'desligado: sem grupo');
select is((select count(*)::int from experiencia_visitas), 0, 'desligado: nada registado');

-- Ligado: duas visitas e dois tempos (fica o mais rápido, sem contar mais visitas)
select testes.funcionalidade('teste_fotos_inicio', true);
set local role authenticated;
select testes.def('g1', visita_experiencia('fotos_inicio'));
select testes.def('g2', visita_experiencia('fotos_inicio'));
select testes.def('t1', visita_experiencia('fotos_inicio', 40));
select testes.def('t2', visita_experiencia('fotos_inicio', 25));
select testes.def('t3', visita_experiencia('fotos_inicio', 90));
select testes.def('e_tabela', testes.erro($$select count(*) from experiencia_visitas$$));
select testes.def('e_exp', testes.erro($$select visita_experiencia('outra')$$));
select testes.def('e_res', testes.erro($$select resultado_experiencia('fotos_inicio', current_date - 1, current_date + 1)$$));
reset role;
select is(testes.v('g1'), 'A', 'ligado: devolve o grupo do cliente');
select is((select visitas from experiencia_visitas where cliente_id = testes.u('ca')), 2, 'duas visitas no mesmo dia');
select is((select segundos_ate_adicionar from experiencia_visitas where cliente_id = testes.u('ca')), 25, 'fica o tempo mais rápido do dia');
select ok(testes.v('e_tabela') like '42501:%', 'a tabela não se lê directamente');
select ok(testes.v('e_exp') like '22023:%', 'experiência desconhecida é recusada');
select ok(testes.v('e_res') like '42501:%', 'o resultado exige analista.usar');

-- Visitante (sem sessão): nada
select testes.sair();
grant usage on schema testes to anon; -- só nesta transacção (rollback)
set local role anon;
select testes.def('anon', testes.erro($$select visita_experiencia('fotos_inicio')$$));
reset role;
select ok(testes.v('anon') like '42501:%', 'visitante sem conta não chama a função');

-- Resultado: o cliente B visita e faz um pedido hoje; o A tem um pedido cancelado (não conta)
select testes.entrar(testes.u('cb'));
set local role authenticated;
select visita_experiencia('fotos_inicio');
select visita_experiencia('fotos_inicio', 12);
reset role;
insert into pedidos (cliente_id, subtotal, estado) values (testes.u('cb'), 4500, 'entregue_pago');
insert into pedidos (cliente_id, subtotal, estado) values (testes.u('ca'), 3000, 'cancelado');
select testes.def('ana', testes.funcionario('Ana Analista', array['analista.usar']));
select testes.entrar_funcionario(testes.u('ana'));
set local role authenticated;
select testes.def('res', resultado_experiencia('fotos_inicio', testes.hoje() - 1, testes.hoje() + 1)::text);
reset role;
select is((testes.v('res')::jsonb #>> '{grupos,B,conversao_pct}')::numeric, 100.0, 'B: o dia de visita acabou em pedido');
select is((testes.v('res')::jsonb #>> '{grupos,A,dias_com_pedido}')::int, 0, 'A: o pedido cancelado não conta');
select is(testes.v('res')::jsonb #>> '{grupos,B,valor_medio}', '4500', 'valor médio do pedido do grupo B');

select * from finish();
rollback;
