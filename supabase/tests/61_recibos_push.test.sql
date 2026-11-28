-- Receipts do Expo (limpeza de tokens inválidos): guardar tickets, verificar os que já têm idade,
-- e concluir (desactivar o token inválido + apagar o recibo).
begin;
\ir _helpers.psql
select plan(11);

select has_table('recibos_push', 'tabela recibos_push existe');
select has_column('recibos_push', 'ticket_id', 'recibos_push tem ticket_id');
select has_column('recibos_push', 'token', 'recibos_push tem token');

-- Guardar os tickets ok
select is(registar_recibos_push('[{"ticket_id":"T1","token":"tok-a"},{"ticket_id":"T2","token":"tok-b"}]'::jsonb),
          2, 'registar_recibos_push guarda os 2 recibos');
select is(registar_recibos_push('[{"ticket_id":"","token":"x"},{"token":"y"}]'::jsonb),
          0, 'registar ignora entradas sem ticket_id ou token');

-- Só os tickets com idade suficiente são verificados
select is((select count(*)::int from recibos_por_verificar()), 0, 'recibos acabados de criar ainda não são verificados');
insert into recibos_push (ticket_id, token, criado_em) values ('T3', 'tok-fantasma', now() - interval '1 hour');
select is((select count(*)::int from recibos_por_verificar()), 1, 'recibo antigo entra na verificação');

-- Concluir desactiva o token inválido e apaga o recibo
select testes.def('cli', testes.cliente('Cli Push'));
insert into dispositivos_push (cliente_id, token, plataforma, activo)
  values (testes.u('cli'), 'tok-fantasma', 'android', true);
select is(concluir_recibos(array(select id from recibos_push where ticket_id = 'T3'), array['tok-fantasma']),
          1, 'concluir_recibos desactiva o token inválido');
select is((select activo from dispositivos_push where token = 'tok-fantasma'), false, 'o token ficou inactivo');
select is((select count(*)::int from recibos_push where ticket_id = 'T3'), 0, 'o recibo verificado foi apagado');

-- Barreira: as apps não podem chamar (só o service_role, pelo cron de envio)
set local role authenticated;
select matches(testes.erro($$select registar_recibos_push('[]'::jsonb)$$), '^42501', 'authenticated não pode registar recibos');
reset role;

select finish();
rollback;
