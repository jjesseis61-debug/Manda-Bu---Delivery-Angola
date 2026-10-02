-- Validade das notificações: o que passou do prazo não é enviado e sai da fila
begin;
\ir _helpers.psql
select plan(7);

select testes.funcionalidade('indicacao', true);
select testes.funcionalidade('pedidos_grupo', true);
select testes.def('ana', testes.cliente('Ana Sousa'));

insert into notificacoes_fila (cliente_id, codigo, dados, criado_em) values
  (testes.u('ana'), 'N5',  '{"prato_do_dia": "Muamba"}', now() - interval '30 minutes'),
  (testes.u('ana'), 'N5',  '{"prato_do_dia": "Calulu"}', now() - interval '5 hours'),
  (testes.u('ana'), 'N10', '{"hora": "12:30"}',          now() - interval '4 hours'),
  (testes.u('ana'), 'N3',  '{"valor": 100}',             now() - interval '3 days'),
  (testes.u('ana'), 'N3',  '{"valor": 200}',             now() - interval '8 days');

select is((select count(*)::int from notificacoes_por_enviar(1000) where codigo = 'N5'), 1,
          'N5 só segue nas 2 horas seguintes (o lembrete das 11h não chega à tarde)');
select is((select dados ->> 'prato_do_dia' from notificacoes_por_enviar(1000) where codigo = 'N5'), 'Muamba',
          'segue o N5 recente, não o antigo');
select is((select count(*)::int from notificacoes_por_enviar(1000) where codigo = 'N10'), 0,
          'N10 com mais de 3 horas já não segue');
select is((select count(*)::int from notificacoes_por_enviar(1000) where codigo = 'N3'), 1,
          'N3 segue durante 7 dias');

select is(descartar_notificacoes_expiradas(), 3, 'a limpeza tira da fila as 3 notificações expiradas');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('ana') and deletado_em is null), 2,
          'ficam na fila só as que ainda estão no prazo');
select ok(not has_function_privilege('authenticated', 'descartar_notificacoes_expiradas()', 'execute')
          and not has_function_privilege('anon', 'notificacao_valida(text, timestamptz)', 'execute'),
          'as funções da fila não são chamáveis pelas apps');

select * from finish();
rollback;
