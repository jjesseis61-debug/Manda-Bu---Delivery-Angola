-- C14 · Definições de notificações: o cliente desliga N5 e N7 pela app, só no seu perfil
begin;
\ir _helpers.psql
select plan(6);

select testes.funcionalidade('indicacao', true);
select testes.def('ana', testes.cliente('Ana'));
select testes.def('bia', testes.cliente('Bia'));

select results_eq(format($$select lembrete_almoco, destaques from preferencias_notificacao where cliente_id = %L$$, testes.u('ana')),
                  $$values (true, true)$$, 'C14: N5 e N7 ligadas por defeito');

select testes.entrar(testes.u('ana'));
set local role authenticated;
update preferencias_notificacao set lembrete_almoco = false, destaques = false, atualizado_em = now()
 where cliente_id = cliente_actual();
select testes.def('vistas', (select count(*) from preferencias_notificacao));
update preferencias_notificacao set lembrete_almoco = false where cliente_id = testes.u('bia');
select testes.def('e_outra_coluna', testes.erro(format(
  $$update preferencias_notificacao set cliente_id = %L where cliente_id = cliente_actual()$$, testes.v('bia'))));
reset role;
select testes.sair();

select results_eq(format($$select lembrete_almoco, destaques from preferencias_notificacao where cliente_id = %L$$, testes.u('ana')),
                  $$values (false, false)$$, 'C14: o cliente desliga N5 e N7 pela app');
select is(testes.v('vistas')::int, 1, 'C14: o cliente só vê as suas preferências');
select is((select lembrete_almoco from preferencias_notificacao where cliente_id = testes.u('bia')), true,
          'C14: não altera as preferências de outro cliente');
select matches(testes.v('e_outra_coluna'), '^42501', 'C14: só lembrete_almoco e destaques são editáveis');

-- Com a preferência desligada, o job não enfileira N5
select testes.entrar(testes.u('ana'));
select registar_partilha();
select testes.sair();
select job_n5_lembrete();
select is((select count(*)::int from notificacoes_fila where codigo = 'N5' and cliente_id = testes.u('ana')), 0,
          'C14: lembrete desligado -> N5 não enfileirada');

select * from finish();
rollback;
