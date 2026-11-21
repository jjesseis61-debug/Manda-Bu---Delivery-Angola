-- Condomínios Fase 2: lista de espera, campanhas (vale o maior: campanha ou convite) e relatório
begin;
\ir _helpers.psql
select plan(24);

select testes.funcionalidade('multi_cozinha', true);
select testes.funcionalidade('condominios', true);
select testes.funcionalidade('campanhas', true);
select testes.funcionalidade('indicacao', true);
update parametros set entrega_gratis_acima = 0, desconto_subtotal_minimo = 0, desconto_indicado = 750 where unico;

with k as (insert into cozinhas (nome, responsavel) values ('Cozinha Jardim 2', 'Rita') returning id) select testes.def('k', id) from k;
with z as (insert into zonas (nome, tipo, taxa, modo_calculo) values ('Jardim 2', 'Própria', 100, 'Fixo') returning id)
  select testes.def('z', id) from z;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Muamba J2', 3000, testes.u('k')) returning id)
  select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Sumo J2', 1000, testes.u('k')) returning id)
  select testes.def('sumo', id) from m;
select testes.def('admin', testes.funcionario('Admin Cond2', array['cozinhas.gerir', 'pedidos.gerir']));

select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('cond', guardar_condominio(jsonb_build_object(
  'nome', 'Jardim Dois', 'cozinha_id', testes.u('k'), 'zona_id', testes.u('z'),
  'centro_lat', -8.8000, 'centro_lng', 13.3000, 'raio_m', 300, 'vagas', 1)));
reset role; select testes.sair();
select testes.def('codigo', (select codigo from condominios where id = testes.u('cond')));

-- Moradores
select testes.def('ana', testes.cliente('Ana J2', 'Particular', '924000001'));
select testes.def('rui', testes.cliente('Rui J2', 'Particular', '924000002'));
select testes.def('eva', testes.cliente('Eva J2', 'Particular', '924000003'));

create function pg_temp.entrar_cond(p_cli uuid) returns text language plpgsql as $$
declare r text;
begin
  perform testes.entrar(p_cli);
  set local role authenticated;
  r := condominio_pedir_entrada(testes.v('codigo'), 'B', '1');
  reset role;
  perform testes.sair();
  return r;
end $$;

-- 1) Lista de espera
select is(pg_temp.entrar_cond(testes.u('ana')), 'activo', '1.ª vaga: entra');
select is(pg_temp.entrar_cond(testes.u('rui')), 'espera', 'vagas cheias: fica em espera');
select is(pg_temp.entrar_cond(testes.u('eva')), 'espera', 'segunda pessoa em espera');
select testes.entrar(testes.u('eva'));
set local role authenticated;
select testes.def('link_eva', condominio_pelo_codigo(testes.v('codigo'))::text);
reset role; select testes.sair();
select results_eq($$select testes.v('link_eva')::jsonb ->> 'meu_estado', (testes.v('link_eva')::jsonb ->> 'minha_posicao')::int$$,
                  $$values ('espera'::text, 2)$$, 'a Eva vê que está em espera, na posição 2');

-- Sobe as vagas para 2: o Rui (1.º da espera) entra sozinho e recebe aviso
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select guardar_condominio(jsonb_build_object('id', testes.u('cond'), 'nome', 'Jardim Dois', 'cozinha_id', testes.u('k'),
  'zona_id', testes.u('z'), 'centro_lat', -8.8000, 'centro_lng', 13.3000, 'raio_m', 300, 'vagas', 2));
reset role; select testes.sair();
select is((select estado from condominio_membros where cliente_id = testes.u('rui')), 'activo', 'vagas a subir: o 1.º da espera entra');
select is((select estado from condominio_membros where cliente_id = testes.u('eva')), 'espera', 'a Eva continua em espera');
select is((select count(*)::int from notificacoes_fila where cliente_id = testes.u('rui') and codigo = 'N31'), 1, 'o Rui recebe aviso');

-- Remover a Ana: a Eva entra
select testes.def('m_ana', (select id from condominio_membros where cliente_id = testes.u('ana') and estado = 'activo'));
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select condominio_decidir_membro(testes.u('m_ana'), 'remover');
select testes.def('lista', (select l::text from jsonb_array_elements(condominios_lista()) l where l ->> 'id' = testes.v('cond')));
reset role; select testes.sair();
select is((select estado from condominio_membros where cliente_id = testes.u('eva')), 'activo', 'saiu alguém: a Eva entra');
select results_eq($$select (testes.v('lista')::jsonb ->> 'activos')::int, (testes.v('lista')::jsonb ->> 'espera')::int$$,
                  $$values (2, 0)$$, 'lista: 2 activos e ninguém em espera');

-- Sem espera ligada, a lista cheia fecha
select testes.def('leo', testes.cliente('Leo J2', 'Particular', '924000004'));
update condominios set lista_espera = false where id = testes.u('cond');
select testes.entrar(testes.u('leo'));
set local role authenticated;
select testes.def('e_leo', testes.erro(format($$select condominio_pedir_entrada(%L, 'C', '2')$$, testes.v('codigo'))));
reset role; select testes.sair();
select ok(testes.v('e_leo') like '%lista_fechada%', 'sem lista de espera: lista cheia fecha');

-- 2) Campanhas
select testes.def('casa_rui', testes.ponto('residencial', -8.8005, 13.3005, testes.u('z')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('rui'), testes.u('casa_rui'));
create function pg_temp.orc(p_cli uuid, p_ponto uuid, p_itens jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform testes.entrar(p_cli);
  set local role authenticated;
  r := orcamento_pedido(p_itens, p_ponto, testes.u('k'));
  reset role;
  perform testes.sair();
  return r;
end $$;
select testes.def('itens', jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2),
                                             jsonb_build_object('cardapio_id', testes.u('sumo'), 'qtd', 1))::text);

select is((pg_temp.orc(testes.u('rui'), testes.u('casa_rui'), testes.v('itens')::jsonb) ->> 'subtotal')::int, 7000, 'sem campanha: 7.000');

select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('camp', guardar_campanha(jsonb_build_object('nome', 'Sexta no Jardim', 'condominio_id', testes.u('cond'),
  'tipo', 'percentagem', 'valor', 20, 'so_membros', true, 'limite_por_cliente', 1)));
reset role; select testes.sair();

select testes.def('orc_c', pg_temp.orc(testes.u('rui'), testes.u('casa_rui'), testes.v('itens')::jsonb)::text);
select results_eq($$select (testes.v('orc_c')::jsonb ->> 'subtotal')::int, (testes.v('orc_c')::jsonb -> 'campanha' ->> 'poupanca')::int,
                           testes.v('orc_c')::jsonb -> 'campanha' ->> 'nome'$$,
                  $$values (5600, 1400, 'Sexta no Jardim'::text)$$, '20% para membros: 7.000 → 5.600 (poupa 1.400)');
select results_eq($$select (i ->> 'preco_unitario')::int, (i ->> 'preco_original')::int from jsonb_array_elements(testes.v('orc_c')::jsonb -> 'itens') i order by 2 desc$$,
                  $$values (2400, 3000), (800, 1000)$$, 'o preço original fica guardado em cada prato');

-- Pedido real: guarda a campanha; com o limite de 1 por cliente, o 2.º pedido já não tem
select testes.entrar(testes.u('rui'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens)
           values (testes.u('rui'), testes.u('casa_rui'), testes.u('k'), testes.v('itens')::jsonb) returning id)
select testes.def('p1', id) from x;
reset role; select testes.sair();
select results_eq(format($$select subtotal::int, campanha_id = %L from pedidos where id = %L$$, testes.u('camp'), testes.u('p1')),
                  $$values (5600, true)$$, 'o pedido grava a campanha e o preço com desconto');
select ok(pg_temp.orc(testes.u('rui'), testes.u('casa_rui'), testes.v('itens')::jsonb) -> 'campanha' = 'null'::jsonb
          or pg_temp.orc(testes.u('rui'), testes.u('casa_rui'), testes.v('itens')::jsonb) -> 'campanha' is null,
          'limite de 1 por cliente: o 2.º pedido já não tem campanha');

-- Não-membro no condomínio não tem a campanha (só membros)
select testes.def('casa_leo', testes.ponto('residencial', -8.8005, 13.3005, testes.u('z')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('leo'), testes.u('casa_leo'));
insert into condominio_membros (condominio_id, cliente_id, estado) values (testes.u('cond'), testes.u('leo'), 'removido');

-- Convite vs campanha: vale o maior
select testes.def('bia', testes.indicado(testes.u('ana'), 'Bia J2'));
insert into condominio_membros (condominio_id, cliente_id, estado, aprovado_em) values (testes.u('cond'), testes.u('bia'), 'activo', now());
select testes.def('casa_bia', testes.ponto('residencial', -8.8005, 13.3005, testes.u('z')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('bia'), testes.u('casa_bia'));
select testes.def('orc_b', pg_temp.orc(testes.u('bia'), testes.u('casa_bia'), testes.v('itens')::jsonb)::text);
select results_eq($$select (testes.v('orc_b')::jsonb ->> 'desconto')::int, (testes.v('orc_b')::jsonb ->> 'subtotal')::int,
                           testes.v('orc_b')::jsonb ->> 'motivo_desconto'$$,
                  $$values (0, 5600, 'campanha'::text)$$, 'campanha (1.400) > convite (750): vale a campanha, sem desconto de convite');
select testes.def('itens_peq', jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('sumo'), 'qtd', 1))::text);
select testes.def('orc_p', pg_temp.orc(testes.u('bia'), testes.u('casa_bia'), testes.v('itens_peq')::jsonb)::text);
select results_eq($$select (testes.v('orc_p')::jsonb ->> 'desconto')::int, (testes.v('orc_p')::jsonb ->> 'subtotal')::int,
                           testes.v('orc_p')::jsonb -> 'campanha' is null or testes.v('orc_p')::jsonb -> 'campanha' = 'null'::jsonb$$,
                  $$values (750, 1000, true)$$, 'convite (750) > campanha (200): vale o convite, sem campanha');
select testes.entrar(testes.u('bia'));
set local role authenticated;
with x as (insert into pedidos (cliente_id, ponto_entrega_id, cozinha_id, itens)
           values (testes.u('bia'), testes.u('casa_bia'), testes.u('k'), testes.v('itens')::jsonb) returning id)
select testes.def('pb', id) from x;
reset role; select testes.sair();
select results_eq(format($$select desconto_indicacao::int, campanha_id is not null from pedidos where id = %L$$, testes.u('pb')),
                  $$values (0, true)$$, 'pedido com campanha: o convite não se gasta');

-- Campanha de preço especial num prato, com horas que não valem agora: não se aplica
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select guardar_campanha(jsonb_build_object('nome', 'Sumo a 1', 'cozinha_id', testes.u('k'), 'tipo', 'preco', 'valor', 1,
  'cardapio_ids', jsonb_build_array(testes.u('sumo')), 'inicio', now() + interval '1 day'));
select testes.def('camps', campanhas_lista()::text);
select testes.def('avisados', campanha_avisar(testes.u('camp'))::text);
select testes.def('e_avisar2', testes.erro(format($$select campanha_avisar(%L)$$, testes.u('camp'))));
reset role; select testes.sair();
select testes.def('casa_eva', testes.ponto('residencial', -8.8005, 13.3005, testes.u('z')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('eva'), testes.u('casa_eva'));
select is((pg_temp.orc(testes.u('eva'), testes.u('casa_eva'), testes.v('itens_peq')::jsonb) -> 'campanha' ->> 'nome'), 'Sexta no Jardim',
          'a campanha que ainda não começou (sumo a 1 Kz) não vale; vale a que está em curso');
select is((select (c -> 'resultado' ->> 'pedidos')::int from jsonb_array_elements(testes.v('camps')::jsonb) c where c ->> 'nome' = 'Sexta no Jardim'), 2,
          'resultado da campanha: 2 pedidos');
select is(testes.v('avisados')::int, 3, 'avisa os 3 membros activos do condomínio');
select ok(testes.v('e_avisar2') like '%ja_avisado%', 'só se avisa uma vez');

-- 3) Relatório do condomínio
select testes.pagar(testes.u('p1'));
select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
select testes.def('rel', relatorio_condominio(testes.u('cond'), testes.hoje() - 7, testes.hoje())::text);
reset role; select testes.sair();
select results_eq($$select (testes.v('rel')::jsonb ->> 'entregues')::int, (testes.v('rel')::jsonb ->> 'vendas')::int,
                           (testes.v('rel')::jsonb ->> 'com_campanha')::int, (testes.v('rel')::jsonb -> 'membros' ->> 'activos')::int$$,
                  $$values (1, 5600, 1, 3)$$, 'relatório: 1 entregue, 5.600 de vendas, 1 com campanha, 3 membros');

select is(has_function_privilege('authenticated', 'aplicar_campanha(jsonb,uuid,uuid,uuid,uuid)', 'execute'), false, 'aplicar_campanha é interna');

select * from finish();
rollback;
