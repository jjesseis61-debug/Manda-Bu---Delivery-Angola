-- Avisos do cliente: sino (só os seus) e assinatura Web Push da PWA.
begin;
\ir _helpers.psql
select plan(11);

select testes.def('ana', testes.cliente('Ana Avisos'));
select testes.def('rui', testes.cliente('Rui Avisos'));
insert into notificacoes_fila (cliente_id, codigo, dados) values
  (testes.u('ana'), 'N16', jsonb_build_object('pedido_id', gen_random_uuid(), 'estado', 'confirmado', 'cozinha_nome', 'Viana')),
  (testes.u('ana'), 'N30', jsonb_build_object('texto', 'Olá Ana')),
  (testes.u('rui'), 'N30', jsonb_build_object('texto', 'Olá Rui'));

-- A) Sino
select testes.entrar(testes.u('ana'));
set local role authenticated;
select is((select count(*)::int from meus_avisos()), 2, 'a Ana vê só os seus 2 avisos');
select is(contar_avisos_novos(), 2, 'dois por ler');
select ok((select bool_and(corpo is not null) from meus_avisos()), 'os avisos vêm com o texto');
select is(marcar_avisos_vistos(), 2, 'marca os dois como vistos');
select is(contar_avisos_novos(), 0, 'nenhum por ler');
reset role; select testes.sair();
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('rui') and vista_em is null), 1,
          'os avisos do Rui não mudaram');

-- B) Push web
select testes.entrar(testes.u('ana'));
set local role authenticated;
select registar_push_web('https://fcm.googleapis.com/fcm/send/abc123',
                         'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U', 'tBHItJI5svbpez7KI4CCXg');
reset role; select testes.sair();
select is((select app from dispositivos_push where cliente_id = testes.u('ana') and activo), 'web', 'assinatura guardada como web');
select ok((select (token::jsonb -> 'keys' ->> 'auth') = 'tBHItJI5svbpez7KI4CCXg' from dispositivos_push
            where cliente_id = testes.u('ana') and app = 'web'), 'o token é o JSON da assinatura');
select ok((select 'web' = any(apps) from notificacoes_por_enviar(100) where cliente_id = testes.u('ana') limit 1),
          'o envio recebe a assinatura web com app = web');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select throws_ok($$select registar_push_web('http://inseguro', 'x', 'y')$$, 'P0001', 'token_invalido', 'recusa assinaturas inválidas');
select remover_push_web('https://fcm.googleapis.com/fcm/send/abc123');
reset role; select testes.sair();
select is((select count(*)::int from dispositivos_push where cliente_id = testes.u('ana') and activo), 0, 'desligar remove a assinatura');

select * from finish();
rollback;
