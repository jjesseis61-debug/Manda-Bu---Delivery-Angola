-- Um dia completo do Manda Bué com todas as partes ligadas (teste geral, 19/11/2026):
-- o dono configura (funcionalidades, zona, cozinha, equipa e permissões), a cozinheira monta o cardápio
-- (pratos, doses, montável com opções), o visitante espreita, os clientes registam-se e usam o convite,
-- fazem pedidos (normal, montado, agendado, cancelado, esgotado), a operadora, a cozinha e o estafeta
-- levam-nos até casa (pronto, atribuição, GPS, dinheiro e TPA com talão), há avaliação, reclamação e
-- avisos, os agentes de IA trabalham (atendimento, analista, compras, vigilância; o modelo é simulado)
-- e o dia fecha com a caixa conferida e os relatórios. Pelo caminho, tentativas que têm de ser recusadas.
begin;
\ir _helpers.psql
select * from no_plan();
create table testes.sim (n serial, parte text, etapa text, obtido text, ok boolean);
grant usage on schema testes to anon, authenticated;
grant all on all tables in schema testes to anon, authenticated;
grant all on all sequences in schema testes to anon, authenticated;

-- Executa um passo como o papel actual; guarda o 1.º valor devolvido (opcional) e regista sucesso/erro
create function testes.passo(p_parte text, p_etapa text, p_sql text, p_nome text default null) returns void
language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  if p_nome is not null then perform testes.def(p_nome, v); end if;
  insert into testes.sim (parte, etapa, obtido, ok) values (p_parte, p_etapa, left(coalesce(v, '✓'), 140), true);
exception when others then
  insert into testes.sim (parte, etapa, obtido, ok) values (p_parte, p_etapa, left(sqlstate || ': ' || sqlerrm, 140), false);
end $$;
-- Verificação: condição tem de ser verdadeira
create function testes.verifica(p_parte text, p_etapa text, p_sql text) returns void language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  insert into testes.sim (parte, etapa, obtido, ok) values (p_parte, p_etapa, left(coalesce(v, '(nulo)'), 140), v = 'true');
exception when others then
  insert into testes.sim (parte, etapa, obtido, ok) values (p_parte, p_etapa, left(sqlstate || ': ' || sqlerrm, 140), false);
end $$;
-- Tentativa que TEM de ser recusada
create function testes.recusa(p_parte text, p_etapa text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  insert into testes.sim (parte, etapa, obtido, ok) values (p_parte, p_etapa, 'ACEITE (devia ser recusado)', false);
exception when others then
  insert into testes.sim (parte, etapa, obtido, ok) values (p_parte, p_etapa, 'recusado: ' || left(sqlerrm, 100), true);
end $$;
grant execute on all functions in schema testes to anon, authenticated;

-- Pessoas com conta (o login por SMS fica simulado pela criação do utilizador)
create function testes.utilizador(p_tel text) returns uuid language sql as $$ insert into auth.users (id, phone) values (gen_random_uuid(), p_tel) returning id $$;
create function testes.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$;

-- =============================================================================
-- 0. O dono (administrador principal)
-- =============================================================================
select testes.def('admin', testes.funcionario('Jacob (dono)', array[]::text[]));
update funcionarios set administrador_principal = true where id = testes.u('admin');
select testes.def('u_admin', (select auth_user_id from funcionarios where id = testes.u('admin')));
update funcionalidades set activa = false;  -- parte do zero
update parametros set desconto_indicado = 1000, desconto_subtotal_minimo = 5000 where unico;  -- como em produção

-- =============================================================================
-- 1. MANHÃ — o dono configura o negócio pela app do operador
-- =============================================================================
select testes.como(testes.v('u_admin'));
set local role authenticated;
select testes.passo('1 Configuração', 'liga o modo com várias cozinhas', $$select alterar_funcionalidade('multi_cozinha', true)$$);
select testes.passo('1 Configuração', 'liga as avaliações', $$select alterar_funcionalidade('avaliacoes', true)$$);
select testes.passo('1 Configuração', 'liga o Convida', $$select alterar_funcionalidade('indicacao', true)$$);
select testes.passo('1 Configuração', 'liga os pratos montáveis', $$select alterar_funcionalidade('pratos_montaveis', true)$$);
select testes.passo('1 Configuração', 'liga o acompanhamento da entrega', $$select alterar_funcionalidade('acompanhamento_entrega', true)$$);
select testes.passo('1 Configuração', 'liga o agente de atendimento', $$select alterar_funcionalidade('agente_atendimento', true)$$);
select testes.passo('1 Configuração', 'liga o agente analista', $$select alterar_funcionalidade('agente_analista', true)$$);
select testes.passo('1 Configuração', 'liga o agente de compras', $$select alterar_funcionalidade('agente_compras', true)$$);
select testes.passo('1 Configuração', 'liga o agente vigilante', $$select alterar_funcionalidade('agente_vigilante', true)$$);
select testes.passo('1 Configuração', 'cria a zona Kilamba (2.000 Kz)', $$insert into zonas (nome, tipo, taxa, modo_calculo, centro_lat, centro_lng) values ('Kilamba', 'Própria', 2000, 'Fixo', -8.997, 13.270) returning id$$, 'zona');
select testes.passo('1 Configuração', 'cria a cozinha «Cozinha da Tia Rosa»', $$insert into cozinhas (nome, responsavel, comissao_percent) values ('Cozinha da Tia Rosa', 'Rosa', 10) returning id$$, 'cz');
select testes.passo('1 Configuração', 'põe a cozinha no mapa', format($$insert into cozinhas_localizacao (cozinha_id, lat, lng, morada) values (%L, -8.990, 13.265, 'Kilamba, bloco Q') returning id$$, testes.v('cz')));
select testes.passo('1 Configuração', 'contrata a operadora Marta', $$select criar_funcionario('Marta Operadora', 'Operadora', '923100001', false)$$, 'marta');
select testes.passo('1 Configuração', 'contrata a cozinheira Rosa', $$select criar_funcionario('Rosa Cozinheira', 'Cozinheira', '923100002', false)$$, 'rosa');
select testes.passo('1 Configuração', 'contrata o estafeta Carlos', $$select criar_funcionario('Carlos Estafeta', 'Estafeta', '923100003', true)$$, 'carlos');
select testes.passo('1 Configuração', 'dá à Marta: pedidos, entregas, reclamações, caixa', format($$select definir_permissoes_funcionario(%L, '{"pedidos.gerir":true,"entregas.atribuir":true,"reclamacoes.gerir":true,"caixa.gerir":true,"vendas.registar":true,"atendimento.gerir":true}')$$, testes.v('marta')));
select testes.passo('1 Configuração', 'dá à Rosa: cardápio e pedidos da cozinha', format($$select definir_permissoes_funcionario(%L, '{"cardapio.gerir":true,"pedidos.gerir":true}')$$, testes.v('rosa')));
select testes.passo('1 Configuração', 'dá ao Carlos: registar entregas', format($$select definir_permissoes_funcionario(%L, '{"entregas.registar":true}')$$, testes.v('carlos')));
select testes.passo('1 Configuração', 'põe Marta, Rosa e Carlos na cozinha', format($$select definir_cozinhas_funcionario(%L, array[%L]::uuid[]), definir_cozinhas_funcionario(%L, array[%L]::uuid[]), definir_cozinhas_funcionario(%L, array[%L]::uuid[])$$,
  testes.v('marta'), testes.v('cz'), testes.v('rosa'), testes.v('cz'), testes.v('carlos'), testes.v('cz')));
reset role;

-- Os funcionários fazem login (o SMS liga a conta ao funcionário pelo telefone)
select testes.def('u_marta', testes.utilizador('244923100001'));
select testes.def('u_rosa', testes.utilizador('244923100002'));
select testes.def('u_carlos', testes.utilizador('244923100003'));
update funcionarios set auth_user_id = testes.u('u_marta') where id = testes.u('marta');
update funcionarios set auth_user_id = testes.u('u_rosa') where id = testes.u('rosa');
update funcionarios set auth_user_id = testes.u('u_carlos') where id = testes.u('carlos');

-- A Rosa monta o cardápio da cozinha dela
select testes.como(testes.v('u_rosa'));
set local role authenticated;
select testes.passo('2 Cardápio', 'Rosa cria «Muamba de galinha» (4.000 Kz, do dia, 20 doses)', format($$insert into cardapio (nome, preco, cozinha_id, do_dia, doses_dia, categoria) values ('Muamba de galinha', 4000, %L, true, 20, 'Pratos') returning id$$, testes.v('cz')), 'muamba');
select testes.passo('2 Cardápio', 'Rosa cria «Calulu de peixe» (5.000 Kz, 2 doses)', format($$insert into cardapio (nome, preco, cozinha_id, doses_dia, categoria) values ('Calulu de peixe', 5000, %L, 2, 'Pratos') returning id$$, testes.v('cz')), 'calulu');
select testes.passo('2 Cardápio', 'Rosa cria «Sumo de múcua» (500 Kz)', format($$insert into cardapio (nome, preco, cozinha_id, categoria) values ('Sumo de múcua', 500, %L, 'Bebidas') returning id$$, testes.v('cz')), 'sumo');
select testes.passo('2 Cardápio', 'Rosa cria o montável «Prato à escolha» (3.000 Kz)', format($$insert into cardapio (nome, preco, cozinha_id, categoria) values ('Prato à escolha', 3000, %L, 'Pratos') returning id$$, testes.v('cz')), 'montavel');
select testes.passo('2 Cardápio', 'grupo «Acompanhamento» (escolher 1)', format($$insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (%L, 'Acompanhamento', 1, 1) returning id$$, testes.v('montavel')), 'grupo');
select testes.passo('2 Cardápio', 'opção «Funge» (+0)', format($$insert into opcoes (grupo_id, nome, preco_extra) values (%L, 'Funge', 0) returning id$$, testes.v('grupo')), 'funge');
select testes.passo('2 Cardápio', 'opção «Arroz» (+200)', format($$insert into opcoes (grupo_id, nome, preco_extra) values (%L, 'Arroz', 200) returning id$$, testes.v('grupo')), 'arroz');
select testes.passo('2 Cardápio', 'opção «Batata frita» esgotada', format($$insert into opcoes (grupo_id, nome, preco_extra, disponivel) values (%L, 'Batata frita', 300, false) returning id$$, testes.v('grupo')), 'batata');
select testes.passo('2 Ataque', 'Rosa tenta pôr a taxa da zona a 1 Kz', format($$with x as (update zonas set taxa = 1 where id = %L returning 1) select count(*)::text || ' linhas alteradas' from x$$, testes.v('zona')));
reset role;
select testes.verifica('2 Ataque', '…a taxa continua 2.000 Kz (Rosa não tem permissão)', format($$select (taxa::int = 2000)::text from zonas where id = %L$$, testes.v('zona')));
select testes.como(testes.v('u_rosa'));
set local role authenticated;
reset role;

-- Custos (para a rentabilidade) e caixa aberta pela Marta
select testes.como(testes.v('u_admin'));
set local role authenticated;
select testes.passo('2 Cardápio', 'dono regista o custo da Muamba (2.100 Kz)', format($$select definir_custo_item(%L, 2100)$$, testes.v('muamba')));
select testes.passo('2 Cardápio', 'dono lança a despesa do gás (6.000 Kz)', format($$select lancar_despesa(%L, testes.hoje(), 'Gás', 'Botija', 6000)$$, testes.v('cz')));
reset role;
select testes.como(testes.v('u_marta'));
set local role authenticated;
select testes.passo('2 Caixa', 'Marta abre a caixa com 5.000 Kz de troco', format($$select abrir_caixa(%L, 'Balcão', 5000)$$, testes.v('cz')), 'caixa');
reset role; select testes.sair();

-- =============================================================================
-- 3. CLIENTES — visitante, registo, convite, moradas
-- =============================================================================
set local role anon;
select testes.passo('3 Visitante', 'vê as zonas', $$select string_agg(z->>'nome', ', ') from jsonb_array_elements(visitante_zonas()) z$$);
select testes.passo('3 Visitante', 'vê a cozinha da Tia Rosa no Kilamba', format($$select string_agg(c->>'nome', ', ') from jsonb_array_elements(visitante_cozinhas(%L)) c$$, testes.v('zona')));
select testes.passo('3 Visitante', 'vê o cardápio (montável marcado)', format($$select string_agg((p->>'nome') || case when (p->>'montar')::boolean then ' [montar]' else '' end, ', ') from jsonb_array_elements(visitante_cardapio(%L)->'pratos') p$$, testes.v('cz')));
reset role;

select testes.def('u_ana', testes.utilizador('244923200001'));
select testes.def('u_rui', testes.utilizador('244923200002'));
select testes.def('u_joana', testes.utilizador('244923200003'));
select testes.como(testes.v('u_ana')); set local role authenticated;
select testes.passo('3 Clientes', 'Ana cria conta', $$select registar_cliente('Ana Silva')$$, 'ana');
select testes.passo('3 Clientes', 'Ana vê o seu código de convite', $$select meu_perfil() ->> 'codigo'$$, 'cod_ana');
reset role;
select testes.como(testes.v('u_rui')); set local role authenticated;
select testes.passo('3 Clientes', 'Rui cria conta', $$select registar_cliente('Rui Costa')$$, 'rui');
select testes.passo('3 Clientes', 'Rui escreve só os números do código da Ana', format($$select ligar_indicacao(%L)$$, substr(testes.v('cod_ana'), 3)));
reset role;
select testes.como(testes.v('u_joana')); set local role authenticated;
select testes.passo('3 Clientes', 'Joana cria conta', $$select registar_cliente('Joana Mendes')$$, 'joana');
reset role; select testes.sair();
-- Moradas no Kilamba (o mapa da app grava o ponto)
select testes.def('casa_ana', testes.ponto('residencial', -8.995, 13.268, testes.u('zona')));
select testes.def('casa_rui', testes.ponto('residencial', -8.999, 13.272, testes.u('zona')));
select testes.def('casa_joana', testes.ponto('residencial', -8.993, 13.275, testes.u('zona')));
update pontos_entrega set criado_por_cliente = testes.u('ana') where id = testes.u('casa_ana');
update pontos_entrega set criado_por_cliente = testes.u('rui') where id = testes.u('casa_rui');
update pontos_entrega set criado_por_cliente = testes.u('joana') where id = testes.u('casa_joana');
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa_ana')), (testes.u('rui'), testes.u('casa_rui')), (testes.u('joana'), testes.u('casa_joana'));

-- =============================================================================
-- 4. ALMOÇO — pedidos pela app do cliente
-- =============================================================================
select testes.como(testes.v('u_rui')); set local role authenticated;
select testes.passo('4 Pedidos', 'Rui pede orçamento: 2 Muambas + 1 Sumo', format($$select orcamento_pedido('[{"cardapio_id":"%s","qtd":2},{"cardapio_id":"%s","qtd":1}]', %L, %L)::text$$, testes.v('muamba'), testes.v('sumo'), testes.v('casa_rui'), testes.v('cz')), 'orc_rui');
select testes.passo('4 Pedidos', 'Rui faz o pedido', format($$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens, observacoes) values (%L, %L, %L, '[{"cardapio_id":"%s","qtd":2},{"cardapio_id":"%s","qtd":1}]', 'Sem picante, por favor') returning id$$, testes.v('rui'), testes.v('casa_rui'), testes.v('cz'), testes.v('muamba'), testes.v('sumo')), 'p_rui');
reset role;
select testes.como(testes.v('u_joana')); set local role authenticated;
select testes.passo('4 Pedidos', 'Joana monta o prato: com Arroz (+200)', format($$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens) values (%L, %L, %L, '[{"cardapio_id":"%s","qtd":1,"opcoes":["%s"]}]') returning id$$, testes.v('joana'), testes.v('casa_joana'), testes.v('cz'), testes.v('montavel'), testes.v('arroz')), 'p_joana');
select testes.recusa('4 Ataque', 'Joana tenta a opção esgotada (Batata frita)', format($$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens) values (%L, %L, %L, '[{"cardapio_id":"%s","qtd":1,"opcoes":["%s"]}]')$$, testes.v('joana'), testes.v('casa_joana'), testes.v('cz'), testes.v('montavel'), testes.v('batata')));
select testes.recusa('4 Ataque', 'Joana tenta montar sem escolher acompanhamento', format($$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens) values (%L, %L, %L, '[{"cardapio_id":"%s","qtd":1}]')$$, testes.v('joana'), testes.v('casa_joana'), testes.v('cz'), testes.v('montavel')));
select testes.passo('4 Pedidos', 'Joana agenda o jantar de amanhã às 19h (Calulu)', format($$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens, agendado_para) values (%L, %L, %L, '[{"cardapio_id":"%s","qtd":1}]', ((testes.hoje() + 1) + time '19:00') at time zone 'Africa/Luanda') returning id$$, testes.v('joana'), testes.v('casa_joana'), testes.v('cz'), testes.v('calulu')), 'p_agendado');
reset role;
select testes.como(testes.v('u_ana')); set local role authenticated;
select testes.passo('4 Pedidos', 'Ana pede o último Calulu (o outro foi para o agendado da Joana)', format($$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens) values (%L, %L, %L, '[{"cardapio_id":"%s","qtd":1}]') returning id$$, testes.v('ana'), testes.v('casa_ana'), testes.v('cz'), testes.v('calulu')), 'p_ana');
select testes.recusa('4 Pedidos', 'mais ninguém consegue pedir Calulu: esgotado', format($$insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens) values (%L, %L, %L, '[{"cardapio_id":"%s","qtd":1}]')$$, testes.v('ana'), testes.v('casa_ana'), testes.v('cz'), testes.v('calulu')));
select testes.passo('4 Pedidos', 'Ana arrepende-se e cancela', format($$select cancelar_pedido(%L, 'Cancelado pelo cliente na app')$$, testes.v('p_ana')));
reset role; select testes.sair();
select testes.verifica('4 Pedidos', 'pedido do Rui: 8.500 + 2.000 entrega − 1.000 convite', format($$select (subtotal::int = 8500 and taxa_entrega::int = 2000 and desconto_indicacao::int = 1000)::text from pedidos where id = %L$$, testes.v('p_rui')));
select testes.verifica('4 Pedidos', 'pedido da Joana: 3.000 + 200 do Arroz', format($$select (subtotal::int = 3200)::text from pedidos where id = %L$$, testes.v('p_joana')));
select testes.verifica('4 Pedidos', 'Calulu volta a ter doses depois do cancelamento', format($$select (doses_restantes(%L) >= 1)::text$$, testes.v('calulu')));

-- =============================================================================
-- 5. OPERADOR, COZINHA E ESTAFETA
-- =============================================================================
select testes.como(testes.v('u_marta')); set local role authenticated;
select testes.verifica('5 Operador', 'Marta vê os pedidos novos na lista', format($$select (count(*) filter (where pedido_id in (%L, %L)) = 2)::text from pedidos_operador()$$, testes.v('p_rui'), testes.v('p_joana')));
select testes.verifica('5 Operador', 'Marta vê o agendado de amanhã', format($$select (count(*) filter (where pedido_id = %L) = 1)::text from pedidos_agendados()$$, testes.v('p_agendado')));
select testes.passo('5 Operador', 'Marta confirma o pedido do Rui', format($$select mudar_estado_pedido(%L, 'confirmado')$$, testes.v('p_rui')));
select testes.passo('5 Operador', 'Marta confirma o pedido da Joana', format($$select mudar_estado_pedido(%L, 'confirmado')$$, testes.v('p_joana')));
reset role;
select testes.como(testes.v('u_rosa')); set local role authenticated;
select testes.passo('5 Cozinha', 'Rosa começa a preparar (Rui)', format($$select mudar_estado_pedido(%L, 'em_preparacao')$$, testes.v('p_rui')));
select testes.passo('5 Cozinha', 'Rosa começa a preparar (Joana)', format($$select mudar_estado_pedido(%L, 'em_preparacao')$$, testes.v('p_joana')));
select testes.passo('5 Cozinha', 'Rosa marca «pronto» (Rui)', format($$select marcar_pedido_pronto(%L, true)$$, testes.v('p_rui')));
reset role;
select testes.como(testes.v('u_marta')); set local role authenticated;
select testes.passo('5 Operador', 'Marta vê os estafetas da cozinha', format($$select string_agg(nome, ', ') from estafetas_para_atribuir(%L)$$, testes.v('cz')));
select testes.passo('5 Operador', 'Marta entrega os dois pedidos ao Carlos', format($$select atribuir_entrega(%L, %L), atribuir_entrega(%L, %L)$$, testes.v('p_rui'), testes.v('carlos'), testes.v('p_joana'), testes.v('carlos')));
select testes.passo('5 Operador', 'Marta avisa a Joana de um atraso de 10 min', format($$select informar_atraso(%L, 'Muitos pedidos', 10)$$, testes.v('p_joana')));
reset role;
select testes.como(testes.v('u_carlos')); set local role authenticated;
select testes.verifica('5 Estafeta', 'Carlos vê os 2 pedidos como dele', $$select (count(*) filter (where atribuido_a_mim) = 2)::text from pedidos_operador()$$);
select testes.passo('5 Estafeta', 'Carlos sai com o pedido do Rui', format($$select mudar_estado_pedido(%L, 'em_entrega')$$, testes.v('p_rui')));
select testes.passo('5 Estafeta', 'Carlos partilha a posição (GPS)', $$select registar_posicao_entrega(-8.996, 13.270, 10)$$);
select testes.recusa('5 Ataque', 'Carlos tenta cancelar um pedido', format($$select mudar_estado_pedido(%L, 'cancelado')$$, testes.v('p_joana')));
reset role;
select testes.como(testes.v('u_rui')); set local role authenticated;
select testes.passo('5 Cliente', 'Rui vê o estafeta a caminho no mapa', format($$select posicao_entrega(%L)::text$$, testes.v('p_rui')));
select testes.recusa('5 Ataque', 'Rui tenta ver a posição da entrega da Joana', format($$select case when posicao_entrega(%L) is null then 1/0 end$$, testes.v('p_joana')));
reset role;
select testes.como(testes.v('u_carlos')); set local role authenticated;
select testes.passo('5 Estafeta', 'Carlos entrega ao Rui e recebe 9.500 Kz em dinheiro', format($$select mudar_estado_pedido(%L, 'entregue_pago', null, %L, '[{"metodo":"Dinheiro","valor":9500}]')$$, testes.v('p_rui'), testes.v('caixa')));
select testes.recusa('5 Ataque', 'pagamento por TPA sem referência é recusado', format($$select mudar_estado_pedido(%L, 'em_entrega'), mudar_estado_pedido(%L, 'entregue_pago', null, %L, '[{"metodo":"TPA","valor":5200}]')$$, testes.v('p_joana'), testes.v('p_joana'), testes.v('caixa')));
select testes.passo('5 Estafeta', 'Carlos fotografa o talão do TPA', format($$insert into storage.objects (bucket_id, name, owner) values ('comprovativos', %L, auth.uid()) returning name$$, testes.v('p_joana') || '/tpa.jpg'));
select testes.passo('5 Estafeta', 'Carlos entrega à Joana: TPA 5.200 (3.200 + 2.000)', format($$select mudar_estado_pedido(%L, 'em_entrega'), mudar_estado_pedido(%L, 'entregue_pago', null, %L, '[{"metodo":"TPA","valor":5200,"referencia":"TPA-0042","comprovativo":"%s/tpa.jpg"}]')$$, testes.v('p_joana'), testes.v('p_joana'), testes.v('caixa'), testes.v('p_joana')));
reset role; select testes.sair();
select testes.verifica('5 Contas', 'vendas registadas para os 2 pedidos', format($$select (count(distinct pedido_id) = 2)::text from vendas where pedido_id in (%L, %L)$$, testes.v('p_rui'), testes.v('p_joana')));
select testes.verifica('5 Contas', 'total vendido: 9.500 + 5.200 = 14.700 Kz', format($$select (sum(valor_total)::int = 14700)::text from vendas where pedido_id in (%L, %L)$$, testes.v('p_rui'), testes.v('p_joana')));
select testes.verifica('5 Convida', 'a Ana ganhou com o 1.º pedido do Rui', format($$select (count(*) = 1)::text from ganhos_indicacao where pedido_id = %L$$, testes.v('p_rui')));
select testes.verifica('5 Stock', 'doses da Muamba: 20 − 2 = 18', format($$select (doses_restantes(%L) = 18)::text$$, testes.v('muamba')));

-- =============================================================================
-- 6. DEPOIS DA ENTREGA — avaliação, reclamação, avisos
-- =============================================================================
select testes.como(testes.v('u_rui')); set local role authenticated;
select testes.passo('6 Pós-venda', 'Rui avalia com 5 estrelas', format($$insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario) values (%L, %L, 5, 'Muamba deliciosa!') returning id$$, testes.v('p_rui'), testes.v('rui')), 'av_rui');
select testes.recusa('6 LIMITAÇÃO', 'estrelas por prato: a Muamba não tem «prato base», não dá',  format($$insert into avaliacoes_pratos (avaliacao_id, prato_id, estrelas) values (%L, %L, 5)$$, testes.v('av_rui'), testes.v('muamba')));
select testes.recusa('6 Ataque', 'Rui tenta escolher a cozinha da avaliação', format($$insert into avaliacoes (pedido_id, cliente_id, cozinha_id, estrelas) values (%L, %L, %L, 1)$$, testes.v('p_rui'), testes.v('rui'), testes.v('cz')));
select testes.passo('6 Pós-venda', 'Rui vê os avisos dele (pedido a caminho, entregue…)', $$select count(*)::text || ' avisos' from meus_avisos(20)$$);
reset role;
select testes.como(testes.v('u_joana')); set local role authenticated;
select testes.passo('6 Pós-venda', 'Joana reclama: o arroz veio frio', format($$select fazer_reclamacao(%L, 'O arroz veio frio e atrasado')$$, testes.v('p_joana')), 'recl');
reset role;
select testes.como(testes.v('u_marta')); set local role authenticated;
select testes.passo('6 Pós-venda', 'Marta vê a reclamação na lista', $$select jsonb_array_length(reclamacoes_lista('aberta'))::text$$);
select testes.passo('6 Pós-venda', 'Marta dá razão e oferece 500 Kz de desconto', format($$select decidir_reclamacao(%L, true, 'Pedimos desculpa, Joana.', 'atraso', 'desconto', 500)$$, testes.v('recl')));
select testes.passo('6 Pós-venda', 'Marta vê as notificações dela', $$select count(*)::text || ' notificações' from minhas_notificacoes(20)$$);
reset role; select testes.sair();
select testes.como(testes.v('u_ana')); set local role authenticated;
select testes.verifica('6 Pós-venda', 'a Ana vê a avaliação na média da cozinha', format($$select (medias_avaliacoes(%L) is not null)::text$$, testes.v('cz')));
reset role;

-- =============================================================================
-- 7. AGENTES DE IA (a resposta do modelo é simulada; o resto é o circuito real)
-- =============================================================================
select testes.como(testes.v('u_joana')); set local role authenticated;
select testes.passo('7 Agente atendimento', 'Joana escreve ao apoio', $$select enviar_mensagem_atendimento('Quando chega o meu jantar de amanhã?') ->> 'conversa_id'$$, 'conversa');
reset role; select testes.sair();
select testes.passo('7 Agente atendimento', 'o agente pega na conversa (serviço)', format($$select (reservar_atendimento(%L) is not null)::text$$, testes.v('conversa')));
select testes.passo('7 Agente atendimento', 'o agente responde', format($$select registar_atendimento(%L, 'respondida', '{"texto":"O teu Calulu chega amanhã às 19h.","passar_a_pessoa":false}')$$, testes.v('conversa')));
select testes.como(testes.v('u_joana')); set local role authenticated;
select testes.verifica('7 Agente atendimento', 'Joana lê a resposta na app', $$select (minha_conversa_atendimento()::text like '%19h%')::text$$);
reset role;
select testes.como(testes.v('u_admin')); set local role authenticated;
select testes.passo('7 Agente analista', 'o dono pergunta ao analista', $$select perguntar_analista('Que prato vendeu mais hoje?')$$, 'pergunta');
select testes.passo('7 Agente compras', 'o dono pede um plano de compras', format($$select pedir_plano_compras(%L)$$, testes.v('cz')), 'plano');
reset role; select testes.sair();
select testes.passo('7 Agente analista', 'o analista lê as vendas (ferramenta)', $$select analista_pratos(testes.hoje(), testes.hoje())::text$$);
select testes.passo('7 Agente analista', 'o analista pega na pergunta', format($$select (reservar_pergunta(%L) is not null)::text$$, testes.v('pergunta')));
select testes.passo('7 Agente analista', 'o analista responde', format($$select registar_resposta_analista(%L, 'respondida', '{"resposta":"A Muamba: 2 doses vendidas hoje."}', '[]')$$, testes.v('pergunta')));
select testes.passo('7 Agente compras', 'o agente pega no pedido de plano', format($$select (reservar_plano_compras(%L) is not null)::text$$, testes.v('plano')));
select testes.passo('7 Agente compras', 'o agente entrega o plano', format($$select registar_plano_compras(%L, 'pronto', '{"resumo":"Comprar galinha para 20 doses.","compras":[]}', '[]')$$, testes.v('plano')));
select testes.como(testes.v('u_admin')); set local role authenticated;
select testes.verifica('7 Agentes', 'o dono vê a resposta do analista', $$select (perguntas_analista_lista()::text like '%Muamba%')::text$$);
select testes.verifica('7 Agentes', 'o dono vê o plano de compras', $$select (planos_compras_lista()::text like '%galinha%')::text$$);
select testes.passo('7 Agente vigilante', 'o dono pede vigilância do Convida de hoje', $$select abrir_vigilancia(testes.hoje(), testes.hoje())$$);
select testes.passo('7 Agente vigilante', 'painel de vigilância', $$select left(painel_vigilancia(30)::text, 80)$$);
reset role; select testes.sair();

-- =============================================================================
-- 8. FIM DO DIA — caixa e relatórios
-- =============================================================================
select testes.como(testes.v('u_marta')); set local role authenticated;
reset role;
select testes.como(testes.v('u_carlos')); set local role authenticated;
select testes.verifica('8 Fecho', 'Carlos vê as 2 entregas que fez hoje', $$select (count(*) = 2)::text from entregas_feitas_hoje()$$);
reset role;
select testes.como(testes.v('u_marta')); set local role authenticated;
select testes.recusa('8 Fecho', 'a caixa não fecha com o talão do TPA por conferir', format($$select fechar_caixa(%L, 14500, 'x')$$, testes.v('caixa')));
select testes.passo('8 Fecho', 'Marta confere o talão do TPA (referência TPA-0042)', format($$select conferir_comprovativo((select id from comprovativos_pagamento where pedido_id = %L), true, 'Confere com o talão')$$, testes.v('p_joana')));
select testes.passo('8 Fecho', 'Marta fecha a caixa (5.000 troco + 9.500 dinheiro = 14.500)', format($$select 'diferença ' || (fechar_caixa(%L, 14500, 'Tudo certo') ->> 'diferenca')$$, testes.v('caixa')), 'fecho_caixa');
reset role;
select testes.como(testes.v('u_admin')); set local role authenticated;
select testes.passo('8 Relatórios', 'fecho do dia da cozinha', format($$select left(fecho_diario(testes.hoje(), %L)::text, 120)$$, testes.v('cz')));
select testes.passo('8 Relatórios', 'relatório da cozinha', format($$select left(relatorio_cozinha(%L, testes.hoje(), testes.hoje())::text, 120)$$, testes.v('cz')));
select testes.passo('8 Relatórios', 'rentabilidade (custos e despesas)', format($$select left(rentabilidade_cozinha(%L, testes.hoje(), testes.hoje())::text, 120)$$, testes.v('cz')));
select testes.passo('8 Relatórios', 'painel do Convida', $$select left(painel_programa(testes.hoje(), testes.hoje())::text, 120)$$);
select testes.passo('8 Relatórios', 'histórico do pedido do Rui (auditoria)', format($$select jsonb_array_length(coalesce(historico_pedido(%L)->'eventos', historico_pedido(%L)))::text || ' eventos'$$, testes.v('p_rui'), testes.v('p_rui')));
reset role; select testes.sair();

select ok(coalesce(ok, false), parte || ' · ' || etapa || case when coalesce(ok, false) then '' else ' — ' || coalesce(obtido, '') end) from testes.sim order by n;
select ok((select count(*) from testes.sim) >= 100, 'o dia inteiro correu (pelo menos 100 passos)');

select * from finish();
rollback;
