-- I3 · Servidor da app do operador: entrada dos funcionários, painel (O1),
-- verificação (O2), levantamentos (O3), embaixadores (O4), entregas (E1) e caixas.
begin;
\ir _helpers.psql
select plan(28);

-- ---------------------------------------------------------------------------
-- 1. Entrada dos funcionários (telefone + SMS)
-- ---------------------------------------------------------------------------
select testes.def('admin', testes.funcionario('Admin', array[]::text[]));
update funcionarios set administrador_principal = true where id = testes.u('admin');
select testes.def('chefe', testes.funcionario('Chefe', array['indicacoes.ver']));
insert into funcionarios (nome, cargo) values ('Marta Entregadora', 'Entregadora');
select testes.def('marta', (select id from funcionarios where nome = 'Marta Entregadora'));
insert into funcionarios (nome) values ('Outro');
select testes.def('outro', (select id from funcionarios where nome = 'Outro'));
insert into direcoes (nome, permissoes) values ('Entregas', '{"entregas.registar": true}');
update funcionarios set direcao_id = (select id from direcoes where nome = 'Entregas') where id = testes.u('marta');

select testes.entrar_funcionario(testes.u('chefe'));
select is(testes.erro(format($$select definir_telefone_funcionario(%L, '923 111 000')$$, testes.v('marta'))),
          '42501:sem_permissao', 'só o administrador principal regista o telefone de um funcionário');
select testes.entrar_funcionario(testes.u('admin'));
select lives_ok(format($$select definir_telefone_funcionario(%L, '+244 923 111 000')$$, testes.u('marta')),
                'administrador regista o telefone');
select is(testes.erro(format($$select definir_telefone_funcionario(%L, '923111000')$$, testes.v('outro'))),
          '23505:duplicate key value violates unique constraint "funcionarios_telefone_key"',
          'o mesmo telefone não serve dois funcionários');
select testes.sair();
select is((select telefone from funcionarios where id = testes.u('marta')), '923111000', 'telefone guardado normalizado');

with u as (insert into auth.users (id, phone) values (gen_random_uuid(), '244923111000') returning id)
select testes.def('u_marta', id) from u;
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_marta'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('ligado', ligar_funcionario());
select testes.def('eu', meu_funcionario());
reset role;
select is(testes.u('ligado'), testes.u('marta')::uuid, 'primeiro login por SMS liga a conta ao funcionário');
select ok(testes.v('eu')::jsonb ->> 'nome' = 'Marta Entregadora'
          and testes.v('eu')::jsonb -> 'permissoes' = '["entregas.registar"]'::jsonb,
          'meu_funcionario: nome e permissões efectivas do organograma');

with u as (insert into auth.users (id, phone) values (gen_random_uuid(), '244999999999') returning id)
select testes.def('u_estranho', id) from u;
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_estranho'), 'role', 'authenticated')::text, true);
select is(ligar_funcionario(), null, 'telefone que não é de nenhum funcionário: sem acesso');

select testes.entrar_funcionario(testes.u('admin'));
select definir_telefone_funcionario(testes.u('marta'), '923 111 001');
select testes.sair();
select is((select auth_user_id from funcionarios where id = testes.u('marta')), null,
          'telefone mudado: a conta antiga deixa de entrar como este funcionário');
update funcionarios set auth_user_id = testes.u('u_marta') where id = testes.u('marta');

-- ---------------------------------------------------------------------------
-- 2. Cenário do programa: Ana indica Bruno; Bruno faz um pedido pago
-- ---------------------------------------------------------------------------
select testes.funcionalidade('indicacao', true);
select testes.def('ana', testes.cliente('Ana Indicadora', 'Particular', '923200001'));
select testes.def('bruno', testes.indicado(testes.u('ana'), 'Bruno Silva'));
select testes.def('p1', testes.pedido(testes.u('bruno'), testes.ponto('residencial')));
select testes.pagar(testes.u('p1'));

-- O1. Painel
select testes.entrar_funcionario(testes.u('marta'));
select is(testes.erro($$select painel_programa(hoje_luanda(), hoje_luanda())$$), '42501:sem_permissao',
          'painel exige indicacoes.ver');
select testes.entrar_funcionario(testes.u('chefe'));
select testes.def('painel', painel_programa(hoje_luanda() - 6, hoje_luanda()));
select testes.sair();
select results_eq($$select (testes.v('painel')::jsonb ->> 'ganhos')::int, (testes.v('painel')::jsonb ->> 'descontos')::int,
                           (testes.v('painel')::jsonb ->> 'custo')::int, (testes.v('painel')::jsonb ->> 'vendas_indicacao')::int,
                           (testes.v('painel')::jsonb ->> 'clientes_novos')::int,
                           (testes.v('painel')::jsonb ->> 'indicadores_activos')::int$$,
                  $$values (100, 500, 600, 2500, 1, 1)$$,
                  'O1: ganhos 100 + descontos 500 = custo 600; vendas de indicação 2.500; 1 cliente novo; 1 indicador activo');
select is(testes.v('painel')::jsonb -> 'top' -> 0 ->> 'nome', 'Ana Indicadora', 'O1: top indicadores com o nome real (interno)');

-- O2. Verificação
select testes.def('verif', testes.funcionario('Verificadora', array['indicacoes.verificar']));
update parametros set limite_verificacao_semanal = 0;
select testes.def('p2', testes.pedido(testes.u('bruno'), testes.ponto('residencial')));
select testes.pagar(testes.u('p2'));
select testes.entrar_funcionario(testes.u('chefe'));
select is(testes.erro('select * from ganhos_em_verificacao()'), '42501:sem_permissao', 'O2 exige indicacoes.verificar');
select testes.entrar_funcionario(testes.u('verif'));
select results_eq($$select indicador_nome, indicado_nome, motivo, valor from ganhos_em_verificacao()$$,
                  $$values ('Ana Indicadora'::text, 'Bruno Silva'::text, 'limite_semanal'::text, 100)$$,
                  'O2: ganho em verificação com indicador, indicado e motivo');
select is(confirmar_ganhos_indicador(testes.u('ana')), 1, 'O2: "Confirmar todos" confirma os ganhos do indicador');
select testes.sair();
select is((select estado from ganhos_indicacao where pedido_id = testes.u('p2')), 'confirmado', 'ganho confirmado');
select is((select (texto_notificacao('N3', dados)).corpo from notificacoes_fila
            where codigo = 'N3' and cliente_id = testes.u('ana') and dados ->> 'pedido_id' = testes.v('p2')),
          '+100 Kz: o pedido de Bruno foi entregue. Saldo desta semana: 200 Kz.',
          'N3 de um ganho confirmado na verificação leva o nome do amigo e o saldo da semana');
update parametros set limite_verificacao_semanal = 10000;

-- O3. Levantamentos
update parametros set levantamento_minimo = 100;
select testes.pagar(testes.pedido(testes.u('ana'), testes.ponto('residencial')));
select testes.def('tesoureira', testes.funcionario('Tesoureira', array['indicacoes.aprovar_pagamentos']));
select testes.entrar(testes.u('ana'));
select testes.def('lev', pedir_levantamento(200, 'unitel_money', '923200001'));
select testes.entrar_funcionario(testes.u('verif'));
select is(testes.erro('select * from levantamentos_operador()'), '42501:sem_permissao', 'O3 exige indicacoes.aprovar_pagamentos');
select testes.entrar_funcionario(testes.u('tesoureira'));
select results_eq($$select indicador_nome, valor, estado, primeiro_levantamento from levantamentos_operador('pedido')$$,
                  $$values ('Ana Indicadora'::text, 200, 'pedido'::text, true)$$,
                  'O3: pedido de levantamento, marcado como primeiro levantamento');
select testes.sair();

-- O4. Embaixadores
select testes.def('gestor', testes.funcionario('Gestora', array['plataforma.parametros']));
update parametros set limiar_embaixador = 1;
select testes.entrar_funcionario(testes.u('gestor'));
select results_eq($$select nome, nivel, indicados_activos, elegivel from embaixadores()$$,
                  $$values ('Ana Indicadora'::text, 'normal'::text, 1, true)$$,
                  'O4: indicador elegível a Embaixador');
select testes.entrar_funcionario(testes.u('marta'));
select is(testes.erro('select * from embaixadores()'), '42501:sem_permissao', 'O4 exige plataforma.parametros');
select testes.sair();

-- ---------------------------------------------------------------------------
-- 3. E1: entregas e caixas
-- ---------------------------------------------------------------------------
select testes.def('p_pend', testes.pedido(testes.u('ana'), testes.ponto('residencial')));
select testes.def('p_conf', testes.pedido(testes.u('ana'), testes.ponto('residencial')));
update pedidos set estado = 'confirmado' where id = testes.u('p_conf');
select testes.def('caixa', testes.caixa());
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));

select testes.entrar_funcionario(testes.u('marta'));
select results_eq(format($$select pedido_id, cliente_nome, a_pagar from pedidos_operador() where pedido_id in (%L, %L)$$,
                         testes.u('p_pend'), testes.u('p_conf')),
                  format($$values (%L::uuid, 'Ana Indicadora'::text, 3000)$$, testes.u('p_conf')),
                  'E1: o entregador vê os pedidos confirmados (não os pendentes), com o nome e o valor a receber');
set local role authenticated;
select testes.def('caixas_marta', (select count(*) from caixa where fechamento is null));
reset role;
select is(testes.v('caixas_marta')::int, 1, 'E1: o entregador vê as caixas abertas');
select testes.entrar_funcionario(testes.u('gerente'));
select is((select count(*)::int from pedidos_operador() where pedido_id in (testes.u('p_pend'), testes.u('p_conf'))), 2,
          'quem tem pedidos.gerir vê também os pendentes');
select testes.entrar(testes.u('ana'));
select is(testes.erro('select * from pedidos_operador()'), '42501:sem_permissao', 'cliente não vê a fila de pedidos');
set local role authenticated;
select testes.def('caixas_cliente', (select count(*) from caixa));
reset role;
select is(testes.v('caixas_cliente')::int, 0, 'cliente não vê caixas');
select testes.sair();

-- ---------------------------------------------------------------------------
-- 4. O6: cozinhas e cardápio escritos pela app do operador ficam na auditoria
-- ---------------------------------------------------------------------------
select testes.def('gestora_cozinhas', testes.funcionario('Gestora Cozinhas', array['cozinhas.gerir']));
select testes.entrar_funcionario(testes.u('gestora_cozinhas'));
set local role authenticated;
update cozinhas set consentimento_publico = true where nome = 'Cozinha da Alexandra';
insert into cardapio (nome, preco, do_dia) values ('Calulu de peixe', 3000, true);
reset role;
select ok(exists (select 1 from auditoria where acao = 'cozinhas_alterada' and funcionario_nome = 'Gestora Cozinhas'
                    and detalhe::jsonb -> 'consentimento_publico' = '{"de": false, "para": true}'::jsonb),
          'O6: consentimento público alterado fica na auditoria com o antes e o depois');
select ok(exists (select 1 from auditoria where acao = 'cardapio_criada' and funcionario_nome = 'Gestora Cozinhas'
                    and detalhe::jsonb ->> 'nome' = 'Calulu de peixe'),
          'O6: prato novo no cardápio fica na auditoria');
select testes.entrar_funcionario(testes.u('marta'));
set local role authenticated;
select testes.def('e_marta_cardapio', testes.erro($$insert into cardapio (nome, preco) values ('Prato da Marta', 100)$$));
reset role;
select testes.sair();
select matches(testes.v('e_marta_cardapio'), '^42501', 'O6: sem cozinhas.gerir não se escreve no cardápio');

select * from finish();
rollback;
