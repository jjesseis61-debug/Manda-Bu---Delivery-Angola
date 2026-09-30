-- Secção 13 · Desconto (testes 5 a 8)
begin;
\ir _helpers.psql
select plan(12);

select testes.funcionalidade('indicacao', true);
select testes.cliente('Ana Indicadora') as ana \gset

-- 5. Indicado novo, local residencial livre -> 500 Kz, mesmo que a app envie outro valor
select testes.indicado(:'ana', 'Bruno') as bruno \gset
select testes.local('residencial') as l_bruno \gset
select testes.entrar(:'bruno');
select results_eq($$select valor, motivo from meu_desconto_indicacao('$$ || :'l_bruno' || $$')$$,
                  $$values (500, 'ok')$$, '5. servidor confirma o desconto antes do pedido (C2)');
select testes.sair();
select testes.pedido(:'bruno', :'l_bruno', null, 9999) as p5 \gset
select is((select desconto_indicacao from pedidos where id = :'p5'), 500,
          '5. desconto de 500 Kz calculado pelo servidor (app enviou 9999)');

select testes.cliente('Sem Ligação') as sem \gset
select testes.pedido(:'sem', :'l_bruno', null, 700) as p5b \gset
select is((select desconto_indicacao from pedidos where id = :'p5b'), 0,
          '5. cliente sem ligação -> 0, mesmo que a app envie 700');

-- 6. 4.º desconto no mesmo local residencial -> 0 Kz
select testes.local('residencial', -8.8000, 13.2000) as casa \gset
-- mesmo prédio, pin a ~10 m (dentro do raio de 25 m)
select testes.local('residencial', -8.80009, 13.2000) as casa_vizinha \gset

create temp table moradores as
select n, testes.indicado(:'ana', 'Morador ' || n) as cliente from generate_series(1, 4) n;
create temp table pedidos_casa as
select n, testes.pedido(cliente, :'casa') as pedido from moradores where n <= 3 order by n;
select testes.pagar(pedido) from pedidos_casa;

select is((select count(*)::int from pedidos p join pedidos_casa c on c.pedido = p.id
            where p.desconto_indicacao = 500), 3,
          '6. 1.º a 3.º descontos no mesmo local residencial aplicados');
select testes.pedido(cliente, :'casa_vizinha') as p6 from moradores where n = 4 \gset
select is((select desconto_indicacao from pedidos where id = :'p6'), 0,
          '6. 4.º desconto no mesmo local residencial -> 0 Kz');
select testes.entrar(cliente) from moradores where n = 4;
select is((select motivo from meu_desconto_indicacao(:'casa')), 'limite_local',
          '6. app recebe o motivo para mostrar "número máximo de vezes nesta morada"');
select testes.sair();

-- 7. Local empresa com 10 indicados -> todos com desconto
select testes.local('empresa', -8.8100, 13.2300) as escritorio \gset
create temp table colegas as
select n, testes.indicado(:'ana', 'Colega ' || n) as cliente from generate_series(1, 10) n;
create temp table pedidos_escritorio (n int, pedido uuid, desconto int);
do $$
declare
  r record; p uuid;
begin
  for r in select * from colegas order by n loop
    p := testes.pedido(r.cliente, (select id from locais_entrega where tipo = 'empresa'
                                                             and lat = -8.8100 and lng = 13.2300));
    insert into pedidos_escritorio
    select r.n, p, desconto_indicacao from pedidos where id = p;
    perform testes.pagar(p);
  end loop;
end $$;
select is((select count(*)::int from pedidos_escritorio where desconto = 500), 10,
          '7. local empresa com 10 indicados -> todos com desconto');

-- 8. 1.º pedido cancelado -> desconto disponível no pedido seguinte
select testes.indicado(:'ana', 'Dina') as dina \gset
select testes.local('residencial') as l_dina \gset
select testes.pedido(:'dina', :'l_dina') as p8a \gset
select is((select desconto_indicacao from pedidos where id = :'p8a'), 500, '8. 1.º pedido com desconto');
select testes.pedido(:'dina', :'l_dina') as p8dup \gset
select is((select desconto_indicacao from pedidos where id = :'p8dup'), 0,
          '8. não há desconto em dois pedidos em curso ao mesmo tempo');
update pedidos set estado = 'cancelado' where id in (:'p8a', :'p8dup');
select testes.pedido(:'dina', :'l_dina') as p8b \gset
select is((select desconto_indicacao from pedidos where id = :'p8b'), 500,
          '8. 1.º pedido cancelado -> desconto disponível no seguinte');

-- Depois do 1.º pedido pago, o desconto já foi usado
select testes.pagar(:'p8b');
select is((select desconto_usado from ligacoes_indicacao where indicado_id = :'dina'), true,
          'desconto marcado como usado no 1.º pedido pago');
select testes.pedido(:'dina', :'l_dina') as p8c \gset
select is((select desconto_indicacao from pedidos where id = :'p8c'), 0,
          'segundo pedido pago não tem desconto');

select * from finish();
rollback;
