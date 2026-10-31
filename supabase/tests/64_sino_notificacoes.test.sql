-- Sino: o funcionário vê só as suas notificações, com texto renderizado, conta as novas e marca vistas.
begin;
\ir _helpers.psql
select plan(9);

select testes.def('f1', testes.funcionario('Gerente 1', array['pedidos.gerir']));
select testes.def('f2', testes.funcionario('Gerente 2', array['pedidos.gerir']));
select testes.def('ana', testes.cliente('Ana Sousa'));

-- Notificações: 2 para f1, 1 para f2 (N32 = aviso a funcionário, texto vem de dados)
insert into notificacoes_fila (funcionario_id, codigo, dados) values
  (testes.u('f1'), 'N32', jsonb_build_object('titulo', 'Aviso', 'corpo', 'Primeiro aviso')),
  (testes.u('f1'), 'N32', jsonb_build_object('titulo', 'Aviso', 'corpo', 'Segundo aviso')),
  (testes.u('f2'), 'N32', jsonb_build_object('titulo', 'Aviso', 'corpo', 'Do outro gerente'));

-- f1 vê só as suas, com texto, e conta as novas
select testes.entrar_funcionario(testes.u('f1'));
set local role authenticated;
select testes.def('n', (select count(*)::int from minhas_notificacoes()));
select testes.def('corpos', (select string_agg(corpo, '|' order by corpo) from minhas_notificacoes()));
select testes.def('novas', contar_notificacoes_novas()::text);
reset role;
select testes.sair();

select is(testes.v('n')::int, 2, 'o funcionário vê só as suas 2 notificações');
select is(testes.v('corpos'), 'Primeiro aviso|Segundo aviso', 'texto renderizado e sem as de outro funcionário');
select is(testes.v('novas')::int, 2, 'contador: 2 novas');

-- Marcar todas como vistas
select testes.entrar_funcionario(testes.u('f1'));
set local role authenticated;
select testes.def('marcou', marcar_notificacoes_vistas()::text);
select testes.def('novas2', contar_notificacoes_novas()::text);
reset role;
select testes.sair();
select is(testes.v('marcou')::int, 2, 'marcou as 2 como vistas');
select is(testes.v('novas2')::int, 0, 'depois de ver, 0 novas');

-- Chega uma nova: volta a contar 1; marcar por id baixa para 0
insert into notificacoes_fila (funcionario_id, codigo, dados)
  values (testes.u('f1'), 'N32', jsonb_build_object('titulo', 'Aviso', 'corpo', 'Terceiro aviso'));
select testes.entrar_funcionario(testes.u('f1'));
set local role authenticated;
select testes.def('novas3', contar_notificacoes_novas()::text);
select testes.def('marcou1', marcar_notificacoes_vistas(array[(select id from minhas_notificacoes() where corpo = 'Terceiro aviso')])::text);
select testes.def('novas4', contar_notificacoes_novas()::text);
reset role;
select testes.sair();
select is(testes.v('novas3')::int, 1, 'uma nova notificação volta a contar');
select is(testes.v('marcou1')::int, 1, 'marcar por id marca só essa');
select is(testes.v('novas4')::int, 0, 'e fica a 0');

-- Um cliente (sem funcionário) não tem notificações de funcionário
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('cli', contar_notificacoes_novas()::text);
reset role;
select testes.sair();
select is(testes.v('cli')::int, 0, 'quem não é funcionário não vê notificações de funcionário');

select * from finish();
rollback;
