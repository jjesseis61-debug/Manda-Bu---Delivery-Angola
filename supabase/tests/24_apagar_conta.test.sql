-- Apagar a conta: soft-delete recuperável 60 dias; purga aos 60 dias (pessoal de app, liberta o número,
-- guarda nome+NIF por obrigação fiscal) e aos 5 anos (nome+NIF). Dados financeiros ficam sempre.
begin;
\ir _helpers.psql
select plan(19);

select testes.def('ana', testes.cliente('Ana Sousa', 'Particular', '244923000111'));
update clientes set telefone = '923000111', nif = '123' where id = testes.u('ana');
select testes.def('u_ana', (select auth_user_id from clientes where id = testes.u('ana')));
insert into auth.sessions (user_id) values (testes.u('u_ana'));  -- uma sessão aberta
select testes.def('ponto', testes.ponto('residencial'));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('ponto'));
insert into dispositivos_push (cliente_id, token, plataforma) values (testes.u('ana'), 'ExponentPushToken[ana]', 'android');
select testes.def('pedido', testes.pedido(testes.u('ana'), testes.u('ponto')));

-- Com um pedido a meio não se apaga
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_curso', testes.erro('select apagar_conta()'));
reset role;
select is(testes.v('e_curso'), 'P0001:pedido_em_curso', 'com um pedido a meio, a conta não se apaga');

-- Pedido entregue: apaga-se (soft-delete recuperável)
select testes.pagar(testes.u('pedido'));
set local role authenticated;
select testes.def('e_apagar', testes.erro('select apagar_conta()'));
reset role;
select is(testes.v('e_apagar'), 'sem_erro', 'o cliente apaga a sua conta');

-- Os dados MANTÊM-SE (recuperável) e a conta fica suspensa, não apagada
select is((select nome from clientes where id = testes.u('ana')), 'Ana Sousa', 'o nome mantém-se (recuperável)');
select ok((select telefone = '923000111' and nif = '123' and auth_user_id is not null
             from clientes where id = testes.u('ana')), 'telefone, NIF e ligação à conta mantêm-se');
select ok((select suspensa_em is not null and purgar_em > now() + interval '59 days' and deletado_em is null
             from clientes where id = testes.u('ana')), 'conta suspensa recuperável (60 dias), não apagada');
select is((select count(*)::int from auth.users where id = testes.u('u_ana')), 1, 'o utilizador da Auth mantém-se para recuperar');
select is((select count(*)::int from auth.sessions where user_id = testes.u('u_ana')), 0, 'todas as sessões terminam (logout em todos os dispositivos)');
select is((select count(*)::int from enderecos_cliente where cliente_id = testes.u('ana') and deletado_em is null), 1, 'os endereços mantêm-se (recuperável)');
select is((select count(*)::int from dispositivos_push where cliente_id = testes.u('ana') and activo), 0, 'telemóveis deixam de receber push');
select ok(exists (select 1 from auditoria where acao = 'cliente_suspendeu_conta' and ref_id = testes.u('ana')), 'fica registado na auditoria');

-- Recuperar dentro dos 60 dias
set local role authenticated;
select testes.def('e_rec', testes.erro('select recuperar_conta()'));
reset role;
select is(testes.v('e_rec'), 'sem_erro', 'o cliente recupera a conta dentro dos 60 dias');
select ok((select suspensa_em is null and deletado_em is null from clientes where id = testes.u('ana')), 'conta recuperada e activa');

-- Apagar de novo e simular que passaram os 60 dias -> purga de app
set local role authenticated;
select apagar_conta();
reset role;
select testes.sair();
update clientes set purgar_em = now() - interval '1 day' where id = testes.u('ana');

-- Um cliente há muito desativado e sem pedidos há > 5 anos -> purga fiscal (nome+NIF)
select testes.def('velho', testes.cliente('Velho Cliente', 'Particular', '244924000222'));
update clientes set nif = '999', desativada_em = now() - interval '30 days' where id = testes.u('velho');

select lives_ok('select job_purgar_contas()', 'a purga automática corre');

-- 60 dias: pessoal de app sai, nome+NIF ficam (fiscal), número libertado
select ok((select telefone is null and auth_user_id is null and desativada_em is not null and deletado_em is not null
             and nome = 'Ana Sousa' and nif = '123' from clientes where id = testes.u('ana')),
          'purga 60d: telefone/ligação saem; nome e NIF ficam (fiscal)');
select is((select count(*)::int from auth.users where id = testes.u('u_ana')), 0, 'o número é libertado na Auth');
select is((select count(*)::int from vendas where pedido_id = testes.u('pedido')), 1, 'a venda do pedido fica para as contas');

-- 5 anos: nome e NIF saem
select is((select nome || '|' || coalesce(nif, '-') from clientes where id = testes.u('velho')),
          'Cliente removido|-', 'purga 5 anos: nome e NIF saem');

-- O mesmo telefone pode voltar a registar-se e começa do zero
with u as (insert into auth.users (id, phone) values (gen_random_uuid(), '244923000111') returning id)
select testes.def('u_novo', id) from u;
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_novo'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('novo', registar_cliente('Ana Nova'));
reset role;
select isnt(testes.u('novo'), testes.u('ana'), 'registo novo com o mesmo telefone cria outro cliente');

-- Sem sessão de cliente não se apaga nada
select testes.sair();
set local role authenticated;
select testes.def('e_sem', testes.erro('select apagar_conta()'));
reset role;
select is(testes.v('e_sem'), '42501:sem_sessao', 'sem sessão de cliente: recusado');

select * from finish();
rollback;
