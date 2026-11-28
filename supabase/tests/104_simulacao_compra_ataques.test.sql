-- Simulação de uma compra real de ponta a ponta (visitante → registo com convite → pedido →
-- operador → cozinha → estafeta → venda → ganho do Convida → reclamação) e, pelo caminho, os
-- ataques de um visitante, de um cliente e de um estafeta mal-intencionados (teste geral, 19/11/2026).
-- Cada verificação compara o obtido com uma expressão regular do esperado.
begin;
\ir _helpers.psql
select plan(48);
grant usage on schema testes to anon, authenticated;
grant execute on all functions in schema testes to anon, authenticated;
create temp table sim (n serial, parte text, etapa text, obtido text, esperado text);
grant all on sim to public; grant usage, select on sequence sim_n_seq to public;
create function pg_temp.reg(p text, e text, o text, x text) returns void language sql as $$ insert into sim (parte, etapa, obtido, esperado) values (p, e, o, x) $$;

-- ======================= PREPARAÇÃO (o operador já configurou) =======================
select testes.funcionalidade('indicacao', true);
select testes.funcionalidade('pratos_montaveis', true);
update parametros set desconto_indicado = 1000, desconto_subtotal_minimo = 5000 where unico;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Kilamba', 'Própria', 2000, 'Fixo') returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco, do_dia) values ('Muamba de galinha', 4000, true) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco) values ('Sumo de múcua', 500) returning id) select testes.def('sumo', id) from m;
select testes.def('ana', testes.cliente('Ana Indicadora', 'Particular', '923000001'));
select testes.def('operador', testes.funcionario('Operador', array['pedidos.gerir']));
select testes.def('estafeta', testes.funcionario('Estafeta', array['entregas.registar']));
select testes.def('caixa', testes.caixa());
select testes.def('cz', cozinha_padrao());
select testes.def('cod_ana', testes.codigo(testes.u('ana')));
insert into equipa_cozinha (funcionario_id, cozinha_id) values (testes.u('operador'), testes.u('cz'));

-- ======================= 1. VISITANTE (sem conta) =======================
set local role anon;
select testes.def('v_zonas', visitante_zonas()::text);
select testes.def('v_cardapio', visitante_cardapio(testes.u('cz'))::text);
select testes.def('v_prato', visitante_prato(testes.u('muamba'), substr(testes.v('cod_ana'), 3))::text);
select testes.def('v_ler_clientes', testes.erro('select count(*) from clientes'));
select testes.def('v_ler_pedidos', testes.erro('select count(*) from pedidos'));
select testes.def('v_registar', testes.erro($$select registar_cliente('Pirata')$$));
select testes.def('v_inserir_pedido', testes.erro($$insert into pedidos (cliente_id) values (gen_random_uuid())$$));
reset role;
select pg_temp.reg('Visitante', 'vê as zonas', (testes.v('v_zonas')::jsonb @> '[{"nome":"Kilamba"}]')::text, '^true$');
select pg_temp.reg('Visitante', 'vê o cardápio com a Muamba', (testes.v('v_cardapio') like '%Muamba de galinha%')::text, '^true$');
select pg_temp.reg('Visitante', 'link com só os números do código mostra o desconto', (testes.v('v_prato')::jsonb -> 'convite' ->> 'desconto'), '^1000$');
select pg_temp.reg('Ataque visitante', 'ler a tabela de clientes', left(testes.v('v_ler_clientes'), 5), '^42501');
select pg_temp.reg('Ataque visitante', 'ler a tabela de pedidos', left(testes.v('v_ler_pedidos'), 5), '^42501');
select pg_temp.reg('Ataque visitante', 'criar conta sem SMS', left(testes.v('v_registar'), 5), '^42501');
select pg_temp.reg('Ataque visitante', 'criar pedido sem conta', left(testes.v('v_inserir_pedido'), 5), '^42501');

-- ======================= 2. REGISTO + CONVITE =======================
with u as (insert into auth.users (id, phone) values (gen_random_uuid(), '244923000002') returning id) select testes.def('u_rui', id) from u;
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('rui', registar_cliente($$Rui '); drop table pedidos; --$$));
select testes.def('lig', ligar_indicacao(substr(testes.v('cod_ana'), 3)));
select testes.def('lig2', ligar_indicacao(testes.v('cod_ana')));
select testes.def('lig_proprio', ligar_indicacao(meu_perfil() ->> 'codigo'));
reset role;
select pg_temp.reg('Registo', 'conta criada (nome com SQL fica só texto)', (select nome from clientes where id = testes.u('rui')), '^Rui ''\); drop table pedidos; --$');
select pg_temp.reg('Registo', 'tabela de pedidos intacta', (to_regclass('public.pedidos') is not null)::text, '^true$');
select pg_temp.reg('Registo', 'código novo no formato MB + 4', ((select codigo from codigos_indicacao where cliente_id = testes.u('rui')) ~ '^MB[1-9][0-9]{3}$')::text, '^true$');
select pg_temp.reg('Convite', 'ligar escrevendo só os números', testes.v('lig'), '^ok$');
select pg_temp.reg('Ataque convite', 'ligar a segunda vez (trocar de padrinho)', testes.v('lig2'), '^(ja_ligado|proprio_codigo)$');
select pg_temp.reg('Ataque convite', 'usar o próprio código', testes.v('lig_proprio'), '^(ja_ligado|proprio_codigo)$');

-- Morada no Kilamba
select testes.def('casa_rui', testes.ponto('residencial', null, null, testes.u('zona')));
update pontos_entrega set criado_por_cliente = testes.u('rui') where id = testes.u('casa_rui');
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('rui'), testes.u('casa_rui'));
select testes.def('casa_ana', testes.ponto('residencial', null, null, testes.u('zona')));
update pontos_entrega set criado_por_cliente = testes.u('ana') where id = testes.u('casa_ana');

-- ======================= 3. COMPRA =======================
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('orc', orcamento_pedido(jsonb_build_array(
  jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2), jsonb_build_object('cardapio_id', testes.u('sumo'), 'qtd', 1)), testes.u('casa_rui'))::text);
-- A app manda preços falsos (1 Kz) e subtotal 10: o servidor tem de os ignorar
with x as (insert into pedidos (cliente_id, ponto_entrega_id, itens, subtotal, taxa_entrega, observacoes)
  values (testes.u('rui'), testes.u('casa_rui'),
    jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2, 'preco_unitario', 1, 'nome', 'Grátis'),
                      jsonb_build_object('cardapio_id', testes.u('sumo'), 'qtd', 1, 'preco_unitario', 1)),
    10, 0, '<script>alert(1)</script>') returning id)
select testes.def('pedido', id) from x;
-- Ataques do cliente durante a compra
select testes.def('a_pedido_por_outro', testes.erro(format($$insert into pedidos (cliente_id, ponto_entrega_id, itens) values (%L, %L, '[{"cardapio_id":"%s","qtd":1}]')$$, testes.u('ana'), testes.u('casa_ana'), testes.v('muamba'))));
select testes.def('a_qtd_negativa', testes.erro(format($$select orcamento_pedido('[{"cardapio_id":"%s","qtd":-5}]', %L)$$, testes.v('muamba'), testes.u('casa_rui'))));
select testes.def('a_qtd_enorme', testes.erro(format($$select orcamento_pedido('[{"cardapio_id":"%s","qtd":100000}]', %L)$$, testes.v('muamba'), testes.u('casa_rui'))));
select testes.def('a_prato_falso', testes.erro(format($$select orcamento_pedido('[{"cardapio_id":"%s","qtd":1}]', %L)$$, gen_random_uuid(), testes.u('casa_rui'))));
select testes.def('a_pago', testes.erro(format($$update pedidos set estado = 'entregue_pago' where id = %L$$, testes.u('pedido'))));
select testes.def('a_estado_rpc', testes.erro(format($$select mudar_estado_pedido(%L, '^entregue_pago$')$$, testes.u('pedido'))));
select testes.def('a_baixar_preco', testes.erro(format($$update pedidos set subtotal = 1 where id = %L$$, testes.u('pedido'))));
select testes.def('a_credito', testes.erro(format($$select usar_credito(%L, 50000)$$, testes.u('pedido'))));
reset role;
select pg_temp.reg('Compra', 'orçamento: 2×4.000 + 500 = 8.500; entrega 2.000', (testes.v('orc')::jsonb ->> 'subtotal') || ' / ' || (testes.v('orc')::jsonb ->> 'taxa_entrega'), '^8500 / 2000$');
select pg_temp.reg('Compra', 'desconto do convite aplicado', (select desconto_indicacao::int::text from pedidos where id = testes.u('pedido')), '^1000$');
select pg_temp.reg('Ataque compra', 'preço falso (1 Kz) ignorado: subtotal real', (select subtotal::int || ' / taxa ' || taxa_entrega::int from pedidos where id = testes.u('pedido')), '^8500 / taxa 2000$');
select pg_temp.reg('Ataque compra', 'nome falso do item ignorado', (select string_agg(i->>'nome', ', ' order by i->>'nome') from pedidos p, jsonb_array_elements(p.itens) i where p.id = testes.u('pedido')), '^Muamba de galinha, Sumo de múcua$');
select pg_temp.reg('Ataque compra', 'fazer pedido em nome de outro cliente', left(testes.v('a_pedido_por_outro'), 5), '^(P0001|42501)');
select pg_temp.reg('Ataque compra', 'quantidade negativa', testes.v('a_qtd_negativa'), '^(P0001|42501)');
select pg_temp.reg('Ataque compra', 'quantidade 100.000', testes.v('a_qtd_enorme'), '^(P0001|42501)');
select pg_temp.reg('Ataque compra', 'prato que não existe', testes.v('a_prato_falso'), '^(P0001|42501)');
select pg_temp.reg('Ataque compra', 'marcar o próprio pedido como pago', testes.v('a_pago') || ' → estado ' || (select estado from pedidos where id = testes.u('pedido')), '^42501.* → estado pendente$');
select pg_temp.reg('Ataque compra', 'mudar estado pela função do operador', left(testes.v('a_estado_rpc'), 5), '^42501');
select pg_temp.reg('Ataque compra', 'baixar o preço depois de criado', left(testes.v('a_baixar_preco'), 5) || ' → ' || (select subtotal::int from pedidos where id = testes.u('pedido')), '^42501 → 8500$');
select pg_temp.reg('Ataque compra', 'usar 50.000 Kz de saldo que não tem', testes.v('a_credito'), '^P0001:saldo_insuficiente$');

-- ======================= 4. OPERADOR, COZINHA E ESTAFETA =======================
select testes.entrar_funcionario(testes.u('operador'));
set local role authenticated;
select testes.def('o_conf', testes.erro(format($$select mudar_estado_pedido(%L, 'confirmado')$$, testes.u('pedido'))));
select testes.def('o_prep', testes.erro(format($$select mudar_estado_pedido(%L, 'em_preparacao')$$, testes.u('pedido'))));
select testes.def('o_pronto', testes.erro(format($$select marcar_pedido_pronto(%L, true)$$, testes.u('pedido'))));
reset role;
select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('e_cancelar', testes.erro(format($$select mudar_estado_pedido(%L, 'cancelado')$$, testes.u('pedido'))));
select testes.def('e_saiu', testes.erro(format($$select mudar_estado_pedido(%L, 'em_entrega')$$, testes.u('pedido'))));
select testes.def('e_entregue', testes.erro(format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, '[{"metodo":"Dinheiro","valor":9500}]')$$, testes.u('pedido'), testes.u('caixa'))));
reset role; select testes.sair();
select pg_temp.reg('Operador', 'confirma e põe em preparação', testes.v('o_conf') || ' / ' || testes.v('o_prep'), '^sem_erro / sem_erro$');
select pg_temp.reg('Cozinha', 'marca o pedido como pronto', testes.v('o_pronto'), '^sem_erro$');
select pg_temp.reg('Ataque estafeta', 'estafeta tenta cancelar o pedido', left(testes.v('e_cancelar'), 5), '^42501');
select pg_temp.reg('Estafeta', 'sai para entrega e entrega (9.500 Kz em dinheiro)', testes.v('e_saiu') || ' / ' || testes.v('e_entregue'), '^sem_erro / sem_erro$');
select pg_temp.reg('Estafeta', 'estado final do pedido', (select estado from pedidos where id = testes.u('pedido')), '^entregue_pago$');
select pg_temp.reg('Contas', 'venda registada (uma linha por prato)', (select count(*)::text || ' linhas, ' || sum(valor_total)::int || ' Kz' from vendas where pedido_id = testes.u('pedido')), '^2 linhas, 9500 Kz$');
select pg_temp.reg('Convida', 'ganho criado para a Ana (quem convidou)', coalesce((select estado || ' ' || valor::int from ganhos_indicacao where pedido_id = testes.u('pedido')), 'nenhum'), '^(confirmado|pendente|em_verificacao) [0-9]+$');

-- ======================= 5. DEPOIS DA ENTREGA + ATAQUES DE CONTA =======================
select set_config('request.jwt.claims', json_build_object('sub', testes.v('u_rui'), 'role', 'authenticated')::text, true);
set local role authenticated;
select testes.def('c_reclamar', testes.erro(format($$select fazer_reclamacao(%L, 'A muamba veio fria')$$, testes.u('pedido'))));
select testes.def('a_ler_pedidos_ana', (select count(*)::text from pedidos where cliente_id = testes.u('ana')));
select testes.def('a_ler_clientes', (select count(*)::text from clientes where id <> testes.u('rui')));
select testes.def('a_auth', testes.erro('select count(*) from auth.users'));
select testes.def('a_nivel_ouro', testes.erro(format($$update codigos_indicacao set nivel = 'ouro' where cliente_id = %L$$, testes.u('rui'))));
select testes.def('a_ganho_falso', testes.erro(format($$insert into ganhos_indicacao (pedido_id, indicador_id, indicado_id, valor, estado) values (%L, %L, %L, 99999, 'confirmado')$$, testes.u('pedido'), testes.u('rui'), testes.u('ana'))));
select testes.def('a_virar_admin', testes.erro($$insert into direcoes (nome, permissoes) values ('Hacker', '{"admin":true}')$$));
select testes.def('a_func', testes.erro(format($$insert into funcionarios (nome, auth_user_id) values ('Hacker', %L)$$, testes.v('u_rui'))));
select testes.def('a_parametros', testes.erro($$select alterar_parametros('{"desconto_indicado": 99999}'::jsonb)$$));
select testes.def('a_mudar_parametros', testes.erro($$update parametros set desconto_indicado = 99999$$));
select testes.def('a_preco_cardapio', testes.erro(format($$update cardapio set preco = 1 where id = %L$$, testes.u('muamba'))));
select testes.def('a_cancelar_ana', testes.erro(format($$select cancelar_pedido(%L, 'hack')$$, (select id from pedidos where cliente_id = testes.u('ana') limit 1))));
select testes.def('a_bloquear', testes.erro(format($$select bloquear_utilizador(%L, 'hack')$$, testes.v('u_rui'))));
select testes.def('a_foto', testes.erro(format($$insert into storage.objects (bucket_id, name) values ('fotos-pratos', 'pratos/%s/hack.jpg')$$, testes.v('muamba'))));
select testes.def('a_apagar', testes.erro('delete from pedidos'));
reset role; select testes.sair();
select pg_temp.reg('Pós-entrega', 'cliente faz reclamação', testes.v('c_reclamar'), '^sem_erro$');
select pg_temp.reg('Ataque conta', 'ver pedidos de outra cliente', testes.v('a_ler_pedidos_ana'), '^0$');
select pg_temp.reg('Ataque conta', 'ver dados de outros clientes', testes.v('a_ler_clientes'), '^0$');
select pg_temp.reg('Ataque conta', 'ler contas de utilizadores (auth)', left(testes.v('a_auth'), 5), '^42501');
select pg_temp.reg('Ataque conta', 'subir-se a nível Ouro', left(testes.v('a_nivel_ouro'), 5) || ' → ' || (select nivel from codigos_indicacao where cliente_id = testes.u('rui')), '^42501 → normal$');
select pg_temp.reg('Ataque conta', 'criar ganho falso de 99.999 Kz', left(testes.v('a_ganho_falso'), 5), '^42501');
select pg_temp.reg('Ataque conta', 'criar direcção de administrador', left(testes.v('a_virar_admin'), 5), '^42501');
select pg_temp.reg('Ataque conta', 'tornar-se funcionário', left(testes.v('a_func'), 5), '^42501');
select pg_temp.reg('Ataque conta', 'mudar parâmetros (função)', left(testes.v('a_parametros'), 5), '^42501');
select pg_temp.reg('Ataque conta', 'mudar parâmetros (tabela)', left(testes.v('a_mudar_parametros'), 5) || ' → ' || (select desconto_indicado::int from parametros where unico), '^42501 → 1000$');
select pg_temp.reg('Ataque conta', 'baixar preço no cardápio', left(testes.v('a_preco_cardapio'), 5) || ' → ' || (select preco::int from cardapio where id = testes.u('muamba')), '^(42501|sem_e) → 4000$');
select pg_temp.reg('Ataque conta', 'cancelar pedido de outra pessoa', left(testes.v('a_cancelar_ana'), 5), '^(P0001|42501)');
select pg_temp.reg('Ataque conta', 'bloquear utilizadores', left(testes.v('a_bloquear'), 5), '^42501');
select pg_temp.reg('Ataque conta', 'enviar foto para um prato', left(testes.v('a_foto'), 5), '^42501');
select pg_temp.reg('Ataque conta', 'apagar todos os pedidos', testes.v('a_apagar') || ' → ' || (select count(*) from pedidos where id = testes.u('pedido')), '^42501.* → 1$');
select pg_temp.reg('XSS', 'observação com <script> guardada como texto', (select observacoes from pedidos where id = testes.u('pedido')), '^<script>alert\(1\)</script>$');

select ok(coalesce(obtido, '(nulo)') ~ esperado, parte || ' · ' || etapa || ' — obtido: ' || coalesce(obtido, '(nulo)')) from sim order by n;

select * from finish();
rollback;
