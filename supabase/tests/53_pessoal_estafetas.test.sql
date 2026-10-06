-- Cadastro de pessoal pelo administrador principal (criar/editar/estafeta) e mapa de
-- acompanhamento dos estafetas para o despacho (posicoes_estafetas).
begin;
\ir _helpers.psql
select plan(8);

-- Administrador principal e um operador de despacho (pedidos.gerir, sem ser admin)
select testes.def('admin', testes.funcionario('Dona Admin', array[]::text[]));
update funcionarios set administrador_principal = true where id = testes.u('admin');
select testes.def('op', testes.funcionario('Despacho', array['pedidos.gerir']));

-- ---------------------------------------------------------------------------
-- A) Pessoal
-- ---------------------------------------------------------------------------
-- O admin cria um estafeta
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('rui', criar_funcionario('Rui Estafeta', 'Estafeta', '923111222', true));
reset role;
select testes.sair();
-- Simula o primeiro login do Rui (liga uma conta ao funcionário, como faz ligar_funcionario)
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000aa');
update funcionarios set auth_user_id = '00000000-0000-0000-0000-0000000000aa' where id = testes.u('rui');
select ok(tem_permissao_de(testes.u('rui'), 'entregas.registar'),
          'criar_funcionario com estafeta=true dá a permissão entregas.registar');

-- Aparece na lista do admin, marcado como estafeta e activo
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('lista_rui', (select (estafeta and activo)::text from listar_pessoal() where id = testes.u('rui')));
reset role;
select testes.sair();
select is(testes.v('lista_rui'), 'true', 'listar_pessoal mostra o estafeta activo');

-- Um não-administrador não pode criar
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select testes.def('e_cria', testes.erro($$select criar_funcionario('Intruso', null, null, true)$$));
reset role;
select testes.sair();
select ok(testes.v('e_cria') like '42501%', 'criar_funcionario: só o administrador principal');

-- Editar a tirar "estafeta" retira a permissão individual
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select editar_funcionario(testes.u('rui'), 'Rui Estafeta', 'Estafeta', false, true);
reset role;
select testes.sair();
select ok(not tem_permissao_de(testes.u('rui'), 'entregas.registar'),
          'editar_funcionario com estafeta=false retira a permissão');

-- O administrador principal não pode ser desactivado
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('e_admin_off', testes.erro(format(
  $$select editar_funcionario(%L, 'Dona Admin', null, null, false)$$, testes.u('admin'))));
reset role;
select testes.sair();
select ok(testes.v('e_admin_off') like 'P0001%', 'o administrador principal não se desactiva');

-- ---------------------------------------------------------------------------
-- B) Mapa de acompanhamento dos estafetas (despacho: pedidos.gerir)
-- ---------------------------------------------------------------------------
select testes.funcionalidade('acompanhamento_entrega', true);
-- Repor o Rui como estafeta activo e pô-lo a caminho com um pedido
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select editar_funcionario(testes.u('rui'), 'Rui Estafeta', 'Estafeta', true, true);
reset role;
select testes.sair();

select testes.def('cli', testes.cliente('Cliente Mapa'));
select testes.def('ped', testes.pedido(testes.u('cli')));
update pedidos set estado = 'em_entrega', entregador_id = testes.u('rui') where id = testes.u('ped');

-- O estafeta envia a posição (API real da app)
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select registar_posicao_entrega(-8.84, 13.23, null);
reset role;
select testes.sair();

-- O despacho vê 1 estafeta no mapa
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select testes.def('mapa', posicoes_estafetas(cozinha_padrao()));
reset role;
select testes.sair();
select is(jsonb_array_length(testes.v('mapa')::jsonb), 1, 'o despacho vê 1 estafeta a caminho no mapa');

-- Um estafeta (sem pedidos.gerir) não vê o mapa de despacho
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('e_mapa_rui', testes.erro(format($$select posicoes_estafetas(%L)$$, cozinha_padrao())));
reset role;
select testes.sair();
select ok(testes.v('e_mapa_rui') like '42501%', 'posicoes_estafetas exige pedidos.gerir');

-- Com o interruptor desligado, não há acompanhamento
select testes.funcionalidade('acompanhamento_entrega', false);
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select testes.def('mapa_off', posicoes_estafetas(cozinha_padrao()));
reset role;
select testes.sair();
select is(jsonb_array_length(testes.v('mapa_off')::jsonb), 0, 'interruptor desligado: mapa vazio');

select * from finish();
rollback;
