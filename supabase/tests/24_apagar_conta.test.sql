-- Apagar a conta pela app: dados pessoais e utilizador da Auth saem, as contas da empresa ficam
begin;
\ir _helpers.psql
select plan(11);

select testes.def('ana', testes.cliente('Ana Sousa', 'Particular', '244923000111'));
update clientes set telefone = '923000111', nif = '123' where id = testes.u('ana');
select testes.def('u_ana', (select auth_user_id from clientes where id = testes.u('ana')));
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

-- Pedido entregue: apaga-se
select testes.pagar(testes.u('pedido'));
set local role authenticated;
select testes.def('e_apagar', testes.erro('select apagar_conta()'));
reset role;
select is(testes.v('e_apagar'), 'sem_erro', 'o cliente apaga a sua conta');
select is((select nome || '|' || coalesce(telefone, '-') || '|' || coalesce(nif, '-') || '|' || coalesce(auth_user_id::text, '-')
             from clientes where id = testes.u('ana')),
          'Cliente removido|-|-|-', 'nome, telefone, NIF e ligação à conta saem');
select ok((select deletado_em is not null from clientes where id = testes.u('ana')), 'cliente marcado como apagado');
select is((select count(*)::int from auth.users where id = testes.u('u_ana')), 0, 'o utilizador da Auth (com o telefone) é apagado');
select is((select count(*)::int from enderecos_cliente where cliente_id = testes.u('ana') and deletado_em is null), 0, 'endereços apagados');
select is((select count(*)::int from dispositivos_push where cliente_id = testes.u('ana') and activo), 0, 'telemóveis deixam de receber push');
select is((select count(*)::int from vendas where pedido_id = testes.u('pedido')), 1, 'a venda do pedido fica para as contas');
select ok(exists (select 1 from auditoria where acao = 'cliente_apagou_conta' and ref_id = testes.u('ana')), 'fica registado na auditoria');

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
