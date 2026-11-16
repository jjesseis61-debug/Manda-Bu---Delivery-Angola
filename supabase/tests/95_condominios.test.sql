-- Cozinha de condomínio (Fase 1): área por GPS, lista de moradores com vagas, abrir/fechar e 12 horas,
-- pedido só de membros com o endereço lá dentro e a taxa da zona do condomínio.
begin;
\ir _helpers.psql
select plan(30);

select testes.funcionalidade('multi_cozinha', true);
select testes.funcionalidade('condominios', true);
update parametros set entrega_gratis_acima = 0 where unico;

with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Jardim', 'Rita') returning id) select testes.def('k', id) from k;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Condomínio Jardim', 'Própria', 100, 'Fixo') returning id)
  select testes.def('zcond', id) from z;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Fora Jardim', 'Própria', 900, 'Fixo') returning id)
  select testes.def('zfora', id) from z;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Muamba Jardim', 3000, testes.u('k')) returning id)
  select testes.def('prato', id) from m;

select testes.def('admin', testes.funcionario('Admin Cond', array['cozinhas.gerir', 'pedidos.gerir']));
select testes.def('cliente_sem', testes.funcionario('Sem permissões', array[]::text[]));

-- Moradores e endereços (centro -8.9000, 13.2000; raio 300 m)
select testes.def('ana', testes.cliente('Ana Moradora', 'Particular', '923000001'));
select testes.def('rui', testes.cliente('Rui Vizinho', 'Particular', '923000002'));
select testes.def('eva', testes.cliente('Eva Terceira', 'Particular', '923000003'));
select testes.def('casa_ana', testes.ponto('residencial', -8.9010, 13.2005, testes.u('zfora')));   -- ~125 m: dentro
select testes.def('fora_ana', testes.ponto('residencial', -8.9200, 13.2000, testes.u('zfora')));   -- ~2,2 km: fora
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa_ana')), (testes.u('ana'), testes.u('fora_ana'));

-- 1) O operador cria o condomínio (2 vagas, entrada automática)
select testes.entrar_funcionario(testes.u('cliente_sem'));
set local role authenticated;
select testes.def('e_sem', testes.erro(format($$select guardar_condominio(jsonb_build_object('nome','X','cozinha_id',%L,'centro_lat',-8.9,'centro_lng',13.2))$$, testes.u('k'))));
reset role; select testes.sair();
select ok(testes.v('e_sem') like '42501%', 'sem cozinhas.gerir não cria condomínios');

select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('cond', guardar_condominio(jsonb_build_object(
  'nome', 'Jardim do Éden', 'cozinha_id', testes.u('k'), 'zona_id', testes.u('zcond'),
  'centro_lat', -8.9000, 'centro_lng', 13.2000, 'raio_m', 300, 'vagas', 2, 'modo_entrega', 'parceiro', 'parceiro_nome', 'Motos Já')));
select testes.def('e_padrao', testes.erro($$select guardar_condominio(jsonb_build_object('nome','P','cozinha_id',cozinha_padrao(),'centro_lat',-8.9,'centro_lng',13.2))$$));
select testes.def('e_dupla', testes.erro(format($$select guardar_condominio(jsonb_build_object('nome','Outro','cozinha_id',%L,'centro_lat',-8.9,'centro_lng',13.2))$$, testes.u('k'))));
reset role; select testes.sair();
select ok(testes.v('cond') is not null, 'condomínio criado');
select ok(testes.v('e_padrao') like '%cozinha_principal_nao%', 'a cozinha principal não pode ser de condomínio');
select ok(testes.v('e_dupla') like '%cozinha_ja_tem_condominio%', 'uma cozinha serve só um condomínio');
select testes.def('codigo', (select codigo from condominios where id = testes.u('cond')));

-- 2) A cozinha do condomínio não aparece nas listas gerais
select testes.entrar(testes.u('eva'));
set local role authenticated;
select testes.def('lista_eva', (select count(*) from cozinhas_para_pedir() where cozinha_id = testes.u('k'))::text);
reset role; select testes.sair();
select is(testes.v('lista_eva'), '0', 'cozinha do condomínio escondida da lista geral');

-- 3) Ana entra pelo link (automático); antes de entrar não vê nada no GPS
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('aqui_antes', coalesce(condominio_aqui(-8.9005, 13.2003)::text, 'NULO'));
select testes.def('info', condominio_pelo_codigo(lower(testes.v('codigo')))::text);
select testes.def('e_casa', testes.erro(format($$select condominio_pedir_entrada(%L, '', '')$$, testes.v('codigo'))));
select testes.def('entrada_ana', condominio_pedir_entrada(testes.v('codigo'), 'Bloco B', '12'));
select testes.def('entrada_ana2', condominio_pedir_entrada(testes.v('codigo'), 'Bloco B', '12'));
reset role; select testes.sair();
select is(testes.v('aqui_antes'), 'NULO', 'quem não é membro não vê o condomínio');
select is((testes.v('info')::jsonb ->> 'vagas_livres')::int, 2, 'o link mostra as vagas livres (código sem diferença de maiúsculas)');
select ok(testes.v('e_casa') like '%casa_obrigatoria%', 'pede o bloco ou a casa');
select is(testes.v('entrada_ana'), 'activo', 'entrada automática: fica activa');
select is(testes.v('entrada_ana2'), 'activo', 'pedir outra vez não duplica');

-- 4) A cozinha acrescenta o Rui pelo telefone; a lista enche (2/2) e fecha sozinha
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('m_rui', condominio_adicionar_membro(testes.u('cond'), '+244 923 000 002', 'A', '3'));
select testes.def('e_naoconta', testes.erro(format($$select condominio_adicionar_membro(%L, '999999999')$$, testes.u('cond'))));
select testes.def('lista', (select l::text from jsonb_array_elements(condominios_lista()) l where l ->> 'id' = testes.v('cond')));
reset role; select testes.sair();
select ok(testes.v('m_rui') is not null, 'a cozinha acrescenta o morador pelo telefone');
select ok(testes.v('e_naoconta') like '%cliente_nao_encontrado%', 'número sem conta: avisa');
select results_eq($$select (testes.v('lista')::jsonb ->> 'activos')::int, (testes.v('lista')::jsonb ->> 'lista_aberta')::boolean$$,
                  $$values (2, false)$$, '2/2 vagas: a lista fecha sozinha');

select testes.entrar(testes.u('eva'));
set local role authenticated;
select testes.def('e_cheia', testes.erro(format($$select condominio_pedir_entrada(%L, 'C', '1')$$, testes.v('codigo'))));
reset role; select testes.sair();
select ok(testes.v('e_cheia') like '%lista_fechada%', 'com a lista cheia ninguém mais entra pelo link');

-- 5) GPS: dentro (com margem de 50 m) vê; longe não
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('aqui', condominio_aqui(-8.9020, 13.2010)::text);      -- ~250 m
select testes.def('margem', coalesce(condominio_aqui(-8.9031, 13.2000)::text, 'NULO'));  -- ~345 m (raio 300 + 50)
select testes.def('longe', coalesce(condominio_aqui(-8.9200, 13.2000)::text, 'NULO'));
reset role; select testes.sair();
select results_eq($$select (testes.v('aqui')::jsonb ->> 'aberta')::boolean, (testes.v('aqui')::jsonb ->> 'visivel')::boolean$$,
                  $$values (true, true)$$, 'dentro do condomínio e aberta: visível');
select ok(testes.v('margem') <> 'NULO', 'na margem de 50 m continua a ver');
select is(testes.v('longe'), 'NULO', 'longe do condomínio: não vê');

-- 6) Pedido: endereço dentro, taxa da zona do condomínio (100); endereço fora recusado; não-membro recusado
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('orc', orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', 1)),
                                          testes.u('casa_ana'), testes.u('k'))::text);
select testes.def('e_fora', testes.erro(format($$select orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)), %L, %L)$$,
                                               testes.u('prato'), testes.u('fora_ana'), testes.u('k'))));
reset role; select testes.sair();
select results_eq($$select (testes.v('orc')::jsonb ->> 'taxa_entrega')::int, testes.v('orc')::jsonb ->> 'zona_nome'$$,
                  $$values (100, 'Condomínio Jardim'::text)$$, 'pedido dentro: taxa e zona do condomínio');
select ok(testes.v('e_fora') like '%fora_do_condominio%', 'endereço fora do condomínio: recusado');

select testes.def('casa_eva', testes.ponto('residencial', -8.9010, 13.2005, testes.u('zfora')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('eva'), testes.u('casa_eva'));
select testes.entrar(testes.u('eva'));
set local role authenticated;
select testes.def('e_eva', testes.erro(format($$select orcamento_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', %L, 'qtd', 1)), %L, %L)$$,
                                              testes.u('prato'), testes.u('casa_eva'), testes.u('k'))));
reset role; select testes.sair();
select ok(testes.v('e_eva') like '%so_membros_condominio%', 'não-membro não pede, mesmo lá dentro');

-- 7) Fechar a cozinha: deixa de aceitar pedidos; visível 12 horas; depois invisível; reabrir
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select abrir_fechar_cozinha(testes.u('k'), false, now() + interval '2 hours');
reset role; select testes.sair();
select is(cozinha_aceita_pedidos(testes.u('k')), false, 'fechada: não aceita pedidos');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('fechada', condominio_aqui(-8.9005, 13.2003)::text);
reset role; select testes.sair();
select results_eq($$select (testes.v('fechada')::jsonb ->> 'aberta')::boolean, (testes.v('fechada')::jsonb ->> 'visivel')::boolean,
                           testes.v('fechada')::jsonb ->> 'reabre_em' is not null$$,
                  $$values (false, true, true)$$, 'fechada há pouco: aparece como fechada, com a hora de reabrir');

-- Directamente na tabela não se abre nem se mexe na hora de fecho
update cozinhas set aberta = true, fechada_desde = now() - interval '13 hours' where id = testes.u('k');
select is((select aberta from cozinhas where id = testes.u('k')), false, 'aberta só muda pela função');
select set_config('mb.abrir_fechar', '1', true);
update cozinhas set fechada_desde = now() - interval '13 hours' where id = testes.u('k');
select set_config('mb.abrir_fechar', '', true);
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('passou12', condominio_aqui(-8.9005, 13.2003)::text);
reset role; select testes.sair();
select is((testes.v('passou12')::jsonb ->> 'visivel')::boolean, false, 'fechada há mais de 12 horas: invisível');

select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select abrir_fechar_cozinha(testes.u('k'), true);
reset role; select testes.sair();
select results_eq(format($$select aberta, fechada_desde is null, reabre_em is null from cozinhas where id = %L$$, testes.u('k')),
                  $$values (true, true, true)$$, 'reaberta: volta a aceitar e a aparecer');

-- 8) Aprovação manual: entra pendente; a cozinha aprova; remover liberta a vaga
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select guardar_condominio(jsonb_build_object('id', testes.u('cond'), 'nome', 'Jardim do Éden', 'cozinha_id', testes.u('k'),
  'zona_id', testes.u('zcond'), 'centro_lat', -8.9000, 'centro_lng', 13.2000, 'vagas', 3, 'aprovacao_manual', true));
reset role; select testes.sair();
select testes.entrar(testes.u('eva'));
set local role authenticated;
select testes.def('entrada_eva', condominio_pedir_entrada(testes.v('codigo'), 'C', '7'));
reset role; select testes.sair();
select is(testes.v('entrada_eva'), 'pendente', 'com aprovação manual fica pendente');
select testes.def('m_eva', (select id from condominio_membros where cliente_id = testes.u('eva') and estado = 'pendente'));
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select condominio_decidir_membro(testes.u('m_eva'), 'aprovar');
select condominio_decidir_membro(testes.u('m_rui'), 'remover');
select testes.def('n_lista', (select count(*) from condominio_membros_lista(testes.u('cond')))::text);
reset role; select testes.sair();
select is((select estado from condominio_membros where id = testes.u('m_eva')), 'activo', 'aprovada pela cozinha');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('eva') and codigo = 'N31'), 1, 'avisa o morador aprovado');
select is(testes.v('n_lista'), '2', 'removido sai da lista (ficam 2)');

-- 9) Tabelas fechadas às apps
select is(has_table_privilege('authenticated', 'condominio_membros', 'select'), false, 'membros só pelas funções');

select * from finish();
rollback;
