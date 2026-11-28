-- Validade do saldo do Convida (12 meses, gastam-se primeiro os mais antigos) e relatório dos expirados
begin;
\ir _helpers.psql
select plan(14);
update parametros set validade_saldo_meses = 12, aviso_expiracao_dias = 30 where unico;
select testes.funcionalidade('indicacao', true);

select testes.def('ana', testes.cliente('Ana Saldo', 'Particular', '923111222'));
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno'));
select testes.def('casa', testes.ponto('residencial'));
create function testes.ganho(p_valor int, p_quando timestamptz) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into ganhos_indicacao (pedido_id, indicador_id, indicado_id, valor, estado, confirmado_em, dispositivo_id)
  values (testes.pedido(testes.u('bruno'), testes.u('casa')), testes.u('ana'), testes.u('bruno'), p_valor,
          'confirmado', p_quando, 'servidor')
  returning id into v;
  return v;
end $$;
-- 1000 há 14 meses, 500 há 13 meses (já passaram a validade); 700 há 11 meses e 20 dias (expira daqui a ~10 dias)
select testes.ganho(1000, now() - interval '14 months');
select testes.ganho(500, now() - interval '13 months');
select testes.ganho(700, now() - interval '11 months 20 days');
-- Usou 600 em refeições
insert into pagamentos_indicacao (indicador_id, valor, tipo, estado, dispositivo_id)
values (testes.u('ana'), 600, 'credito', 'pago', 'servidor');

select is(saldo_disponivel_de(testes.u('ana')), 1600, 'saldo antes: 2200 − 600');
select is(saldo_a_expirar(testes.u('ana')), 900, 'expira 1500 antigos − 600 já usados (os antigos gastam-se primeiro)');

-- 1) O job regista a expiração e avisa
select is(job_expirar_saldos(), 1, 'uma expiração registada');
select is(saldo_disponivel_de(testes.u('ana')), 700, 'o saldo desce para 700');
select results_eq($$select valor, ganhos_antigos, usado, saldo_antes from expiracoes_saldo where indicador_id = testes.u('ana')$$,
                  $$values (900, 1500, 600, 1600)$$, 'guarda o valor e o porquê');
select ok(exists (select 1 from notificacoes_fila where cliente_id = testes.u('ana') and dados ->> 'tipo' = 'saldo_expirado'),
          'avisa o cliente que expirou');
select ok(exists (select 1 from notificacoes_fila where cliente_id = testes.u('ana') and dados ->> 'tipo' = 'saldo_a_expirar'
                   and (dados ->> 'valor')::int = 700), 'e que 700 expiram em breve');
select is(job_expirar_saldos(), 0, 'correr outra vez não expira de novo');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('ana') and dados ->> 'tipo' = 'saldo_a_expirar'),
          1, 'nem repete o aviso');

-- 2) O cliente vê o saldo, o que expira em breve e quando
select testes.entrar(testes.u('ana'));
set local role authenticated;
select results_eq($$select saldo_disponivel, a_expirar_em_breve, total_expirado from saldo_indicacao where indicador_id = testes.u('ana')$$,
                  $$values (700, 700, 900)$$, 'a app mostra saldo, a expirar e expirado');
select ok((select proxima_expiracao between now() + interval '9 days' and now() + interval '11 days'
             from saldo_indicacao where indicador_id = testes.u('ana')), 'e a data em que o resto expira');
reset role; select testes.sair();

-- Outro cliente não vê o de ninguém
select testes.def('rui', testes.cliente('Rui Curioso'));
select testes.entrar(testes.u('rui'));
set local role authenticated;
select is(saldo_a_expirar(testes.u('ana'), now() + interval '1 year'), 0, 'outro cliente não sabe quanto a Ana tem a expirar');
reset role; select testes.sair();

-- 3) Relatório
select testes.def('vigia', testes.funcionario('Vigia Saldo', array['indicacoes.verificar']));
select testes.entrar_funcionario(testes.u('vigia'));
set local role authenticated;
create temp table r as select relatorio_saldos_expirados(testes.hoje() - 30, testes.hoje()) as j;
reset role; select testes.sair();
select results_eq($$select (j -> 'resumo' ->> 'total')::int, (j -> 'lista' -> 0 ->> 'telefone'), (j -> 'a_expirar' ->> 'd30')::int from r$$,
                  $$values (900, '923111222', 700)$$, 'relatório: total expirado, quem e o que expira nos próximos 30 dias');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select throws_ok(format('select relatorio_saldos_expirados(%L, %L)', testes.hoje() - 30, testes.hoje()), '42501', null,
                 'o cliente não vê o relatório');
reset role; select testes.sair();

select * from finish();
rollback;
