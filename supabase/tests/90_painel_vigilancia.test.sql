-- Painel de vigilância do Convida (#9)
begin;
\ir _helpers.psql
select plan(9);
select testes.funcionalidade('indicacao', true);

select testes.def('ana', testes.cliente('Ana Vigiada'));
select testes.def('b1', testes.indicado(testes.u('ana'), 'Bruno'));
select testes.def('b2', testes.indicado(testes.u('ana'), 'Beto'));
select testes.def('p1', testes.pedido(testes.u('b1'), testes.ponto('residencial')));
select testes.pagar(testes.u('p1'));
-- Um ganho anulado por mesmo telemóvel e outro em verificação (como o servidor os grava)
insert into ganhos_indicacao (pedido_id, indicador_id, indicado_id, valor, estado, motivo, dispositivo_id)
values (testes.pedido(testes.u('b2'), testes.ponto('residencial')), testes.u('ana'), testes.u('b2'), 390, 'anulado', 'mesmo_dispositivo', 'servidor'),
       (testes.pedido(testes.u('b2'), testes.ponto('residencial')), testes.u('ana'), testes.u('b2'), 390, 'em_verificacao', null, 'servidor');
insert into pagamentos_indicacao (indicador_id, valor, tipo, metodo, numero_destino, estado, dispositivo_id)
values (testes.u('ana'), 2500, 'levantamento', 'unitel_money', '923000000', 'pedido', 'servidor');
-- Pico de contas novas hoje
select testes.cliente('Conta ' || n) from generate_series(1, 6) n;

select testes.def('vigia', testes.funcionario('Vigia', array['indicacoes.verificar']));
select testes.entrar_funcionario(testes.u('vigia'));
set local role authenticated;
create temp table r as select painel_vigilancia(14) as j;
reset role; select testes.sair();

select is((select (j -> 'anulados' ->> 'n')::int from r), 1, 'conta os ganhos anulados');
select is((select j -> 'anulados' -> 'por_motivo' -> 0 ->> 'motivo' from r), 'mesmo_dispositivo', 'por motivo');
select is((select (j -> 'em_verificacao' ->> 'n')::int from r), 1, 'ganhos à espera de verificação');
select results_eq($$select (j -> 'levantamentos' ->> 'n')::int, (j -> 'levantamentos' ->> 'valor')::int from r$$,
                  $$values (1, 2500)$$, 'levantamentos pendentes');
select is((select jsonb_array_length(j -> 'serie') from r), 14, 'uma linha por dia');
select ok((select (j -> 'serie' -> 13 ->> 'pico')::boolean and (j -> 'serie' -> 13 ->> 'contas')::int >= 6 from r),
          'hoje: pico de contas novas');
select is((select j -> 'topo' -> 0 ->> 'nome' from r), 'Ana Vigiada', 'quem mais ganhou');

-- Permissões
select testes.entrar(testes.u('ana'));
set local role authenticated;
select throws_ok('select painel_vigilancia(14)', '42501', null, 'o cliente não vê o painel');
reset role; select testes.sair();
select testes.def('outro', testes.funcionario('Sem permissão', array['pedidos.gerir']));
select testes.entrar_funcionario(testes.u('outro'));
set local role authenticated;
select throws_ok('select painel_vigilancia(14)', '42501', null, 'nem quem não verifica indicações');
reset role; select testes.sair();

select * from finish();
rollback;
