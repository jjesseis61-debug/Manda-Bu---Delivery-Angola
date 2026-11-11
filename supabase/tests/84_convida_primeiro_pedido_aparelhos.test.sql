-- Convida: sem comissão no 1.º pedido do convidado (a partir do 2.º) e registo de aparelhos.
begin;
\ir _helpers.psql
select plan(11);
update parametros set comissao_primeiro_pedido = false, max_indicados_por_local = 3,
                      max_descontos_por_local = 3, raio_mesmo_local_m = 25, alerta_contas_por_aparelho = 3 where unico;
select testes.funcionalidade('indicacao', true);

select testes.def('ana', testes.cliente('Ana Convida'));
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno'));
select testes.def('casa', testes.ponto('residencial'));

-- 1) 1.º pedido pago: sem comissão; 2.º: com comissão
select testes.def('p1', testes.pedido(testes.u('bruno'), testes.u('casa')));
select testes.pagar(testes.u('p1'));
select is((select count(*)::int from ganhos_indicacao where pedido_id = testes.u('p1')), 0,
          '1.º pedido do convidado: sem comissão');
select is((select primeiro_pedido_id from ligacoes_indicacao where indicado_id = testes.u('bruno')), testes.u('p1')::uuid,
          'o 1.º pedido arranca o período na mesma');
select testes.def('p2', testes.pedido(testes.u('bruno'), testes.u('casa')));
select testes.pagar(testes.u('p2'));
select is((select estado from ganhos_indicacao where pedido_id = testes.u('p2')), 'confirmado',
          '2.º pedido: comissão confirmada');

-- 2) Com o parâmetro ligado volta a pagar no 1.º
update parametros set comissao_primeiro_pedido = true where unico;
select testes.def('carla', testes.indicado(testes.u('ana'), 'Carla'));
select testes.def('p3', testes.pedido(testes.u('carla'), testes.ponto('residencial')));
select testes.pagar(testes.u('p3'));
select is((select count(*)::int from ganhos_indicacao where pedido_id = testes.u('p3')), 1,
          'parâmetro ligado: comissão logo no 1.º pedido');
update parametros set comissao_primeiro_pedido = false where unico;

-- 3) Aviso N2 diz que começa no 2.º pedido
select ok((select corpo from texto_notificacao('N2', '{"indicado_nome":"Rui","ganho_por_pedido":600,"duracao_dias":60}'))
          like '%a partir do 2.º%', 'N2 explica que as comissões começam no 2.º pedido');

-- 4) Aparelhos: cada conta regista o seu; 3 contas no mesmo aparelho aparecem na vigilância
select testes.def('c1', testes.cliente('Conta Um'));
select testes.def('c2', testes.cliente('Conta Dois'));
select testes.def('c3', testes.cliente('Conta Três'));
create function testes.aparelho(p_cli uuid, p_inst text, p_ap text) returns void language plpgsql as $$
begin
  perform testes.entrar(p_cli);
  set local role authenticated;
  perform registar_aparelho(p_inst, p_ap, 'android', 'Tecno Spark');
  reset role;
  perform testes.sair();
end $$;
select testes.aparelho(testes.u('c1'), 'inst-aaaaaaaa', 'android-xyz');
select testes.aparelho(testes.u('c2'), 'inst-bbbbbbbb', 'android-xyz');
select testes.aparelho(testes.u('c1'), 'inst-aaaaaaaa', 'android-xyz'); -- repetido: só actualiza
select is((select count(*)::int from aparelhos_conta where aparelho_id = 'android-xyz'), 2, 'uma linha por conta e instalação');

select testes.def('vigia', testes.funcionario('Vigia', array['indicacoes.verificar']));
select testes.entrar_funcionario(testes.u('vigia'));
set local role authenticated;
select is((select count(*)::int from aparelhos_partilhados() where chave = 'android-xyz'), 0, 'com 2 contas ainda não alerta');
reset role; select testes.sair();

select testes.aparelho(testes.u('c3'), 'inst-cccccccc', 'android-xyz');
select testes.entrar_funcionario(testes.u('vigia'));
set local role authenticated;
select is((select contas from aparelhos_partilhados() where chave = 'android-xyz'), 3, 'com 3 contas aparece na vigilância');
reset role; select testes.sair();

-- 5) Permissões: o cliente não lê a tabela nem a lista; sem sessão de cliente não regista
select testes.entrar(testes.u('c1'));
set local role authenticated;
select is((select count(*)::int from aparelhos_conta), 0, 'o cliente não lê a tabela de aparelhos');
select throws_ok('select * from aparelhos_partilhados()', '42501', null, 'o cliente não vê a vigilância');
reset role; select testes.sair();
select testes.entrar_funcionario(testes.u('vigia'));
set local role authenticated;
select throws_ok($$select registar_aparelho('inst-zzzzzzzz', null, 'web')$$, '42501', null, 'só clientes registam aparelhos');
reset role; select testes.sair();

select * from finish();
rollback;
