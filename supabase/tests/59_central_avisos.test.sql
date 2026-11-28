-- Central de Avisos: texto livre (N31/N32), pré-visualização e envio segmentado
-- (clientes todos / por zona / funcionários por permissão), registo e barreira de permissão.
begin;
\ir _helpers.psql
select plan(12);

-- Fixtures (como superutilizador)
select testes.def('coz', (select cozinha_padrao()));
select testes.def('gestor', testes.funcionario('Gestor Avisos', array['avisos.enviar']));
select testes.def('cli1', testes.cliente('Cliente Um'));
select testes.def('cli2', testes.cliente('Cliente Dois'));
insert into dispositivos_push (cliente_id, token, plataforma) values (testes.u('cli1'), 'TOK-C1', 'android');
insert into dispositivos_push (cliente_id, token, plataforma) values (testes.u('cli2'), 'TOK-C2', 'android');

-- zona + pedido do cli1 nessa zona (para o público "por zona")
with z as (insert into zonas (nome) values ('Maianga') returning id)
select testes.def('zona', id) from z;
insert into pedidos (cliente_id, zona_id) values (testes.u('cli1'), testes.u('zona'));

-- estafeta com entregas.registar + dispositivo (para o público "por permissão")
select testes.def('estafeta', testes.funcionario('Estafeta', array['entregas.registar']));
insert into dispositivos_push (funcionario_id, token, plataforma) values (testes.u('estafeta'), 'TOK-F1', 'android');

-- texto_notificacao usa o texto livre do dados para os códigos de aviso
select is((select corpo  from texto_notificacao('N31', jsonb_build_object('titulo','T','corpo','Olá'))), 'Olá', 'N31 usa o corpo do dados');
select is((select titulo from texto_notificacao('N31', jsonb_build_object('titulo','T','corpo','Olá'))), 'T',   'N31 usa o título do dados');

-- como gestor com avisos.enviar
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select is(pre_visualizar_aviso('clientes_todos', '{}'::jsonb), 2, 'clientes_todos = 2 clientes com dispositivo');
select is(pre_visualizar_aviso('clientes_zona', jsonb_build_object('zona_id', testes.u('zona'))), 1, 'clientes_zona = 1 (só o cli1 pediu na zona)');
select is(pre_visualizar_aviso('func_permissao', jsonb_build_object('permissao','entregas.registar')), 1, 'func_permissao entregas.registar = 1 estafeta');
select testes.def('env',   (select enviar_aviso('clientes_todos','Promo','Texto da promo')::text));
select testes.def('env_f', (select enviar_aviso('func_permissao','Equipa','Reunião', jsonb_build_object('permissao','entregas.registar'))::text));
select testes.def('e_vazio', testes.erro($$select enviar_aviso('clientes_todos','x','   ')$$));
reset role;

-- sem a permissão não envia
select testes.def('ze', testes.funcionario('Zé Sem Permissão', array[]::text[]));
select testes.entrar_funcionario(testes.u('ze'));
set local role authenticated;
select testes.def('e_perm', testes.erro($$select enviar_aviso('clientes_todos','x','y')$$));
reset role;

select is((testes.v('env')::jsonb ->> 'total'), '2', 'aviso a clientes_todos enfileirou 2');
select is((select count(*)::int from notificacoes_fila where codigo = 'N31' and dados->>'corpo' = 'Texto da promo'), 2,
          'fila tem 2 avisos N31 (clientes) com o texto certo');
select is((testes.v('env_f')::jsonb ->> 'total'), '1', 'aviso a func_permissao enfileirou 1');
select is((select count(*)::int from notificacoes_fila where codigo = 'N32'), 1, 'fila tem 1 aviso N32 (funcionários)');
select is((select count(*)::int from avisos), 2, 'dois avisos registados no histórico');
select matches(testes.v('e_vazio'), '22023', 'corpo vazio é recusado');
select matches(testes.v('e_perm'), '42501', 'sem avisos.enviar não envia');

select * from finish();
rollback;
