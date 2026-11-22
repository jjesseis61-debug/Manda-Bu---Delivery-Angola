-- Receitas: o «Pedir» segue o balcão do cliente e o prato; «quero que façam»; funil toque -> pedido
begin;
\ir _helpers.psql
select plan(14);

select testes.funcionalidade('receitas', true);
select testes.funcionalidade('multi_cozinha', true);
with c as (insert into cozinhas (nome, responsavel) values ('Kilamba R', 'Ana') returning id) select testes.def('kil', id) from c;
with c as (insert into cozinhas (nome, responsavel) values ('Viana R', 'Bia') returning id) select testes.def('via', id) from c;
with c as (insert into cozinhas (nome, responsavel) values ('Longe R', 'Cid') returning id) select testes.def('lon', id) from c;
update cozinhas set estado = 'activa', aberta = true where id in (testes.u('kil'), testes.u('via'), testes.u('lon'));
insert into cozinhas_localizacao (cozinha_id, lat, lng) values
  (testes.u('kil'), -8.99, 13.27), (testes.u('via'), -8.90, 13.37), (testes.u('lon'), -8.60, 13.20);
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Mufete R', 4500, testes.u('via')) returning id) select testes.def('muf_via', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Mufete especial R', 5200, testes.u('lon')) returning id) select testes.def('muf_lon', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Cocada R', 800, testes.u('kil')) returning id) select testes.def('coc_kil', id) from m;
with m as (insert into cardapio (nome, preco, cozinha_id) values ('Arroz R', 3000, testes.u('kil')) returning id) select testes.def('arroz', id) from m;
with r as (insert into receitas (titulo, corpo, estado, publicado_em, cozinha_id) values ('Mufete R', 'x', 'publicada', now(), testes.u('via')) returning id)
select testes.def('r_muf', id) from r;
with r as (insert into receitas (titulo, corpo, estado, publicado_em) values ('Muamba R', 'x', 'publicada', now()) returning id)
select testes.def('r_mua', id) from r;
with r as (insert into receitas (titulo, corpo, estado, publicado_em) values ('Cocada R', 'x', 'publicada', now()) returning id)
select testes.def('r_coc', id) from r;

-- O editor liga os pratos (de várias cozinhas)
select testes.def('ed', testes.funcionario('Edu Editor', array['receitas.gerir']));
select testes.entrar_funcionario(testes.u('ed'));
set local role authenticated;
select testes.def('n_muf', receita_guardar_pratos(testes.u('r_muf'), array[testes.u('muf_via'), testes.u('muf_lon')])::text);
select testes.def('n_coc', receita_guardar_pratos(testes.u('r_coc'), array[testes.u('coc_kil')])::text);
select testes.def('lista_muf', receita_pratos_gerir(testes.u('r_muf'))::text);
reset role;
select is(testes.v('n_muf'), '2', 'a receita liga-se a pratos de duas cozinhas');
select is(jsonb_array_length(testes.v('lista_muf')::jsonb), 2, 'o editor vê os pratos ligados');

-- Cliente no Kilamba (ponto perto do Kilamba)
with z as (insert into zonas (nome, tipo, taxa) values ('Zona R', 'Própria', 1000) returning id) select testes.def('zona', id) from z;
select testes.def('cli', testes.cliente('Rui Receitas'));
select testes.def('ponto', testes.ponto('residencial', -8.98, 13.28, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('cli'), testes.u('ponto'));
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('coc', receita_onde_pedir(testes.u('r_coc'), testes.u('kil'), testes.u('ponto'))::text);
select testes.def('muf', receita_onde_pedir(testes.u('r_muf'), testes.u('kil'), testes.u('ponto'))::text);
select testes.def('mua', receita_onde_pedir(testes.u('r_mua'), testes.u('kil'), testes.u('ponto'))::text);
select testes.def('q1', receita_quero(testes.u('r_mua'))::text);
select testes.def('q2', receita_quero(testes.u('r_mua'))::text);
select testes.def('mua2', receita_onde_pedir(testes.u('r_mua'), testes.u('kil'), testes.u('ponto'))::text);
select testes.def('e_pratos', testes.erro(format($$select receita_guardar_pratos(%L, null)$$, testes.v('r_coc'))));
select testes.def('e_tabela', testes.erro($$select count(*) from receitas_pratos$$));
reset role;
select is(testes.v('coc')::jsonb ->> 'estado', 'aqui', 'o balcão escolhido vende o prato: pede-se aí');
select is(testes.v('muf')::jsonb ->> 'estado', 'perto', 'o Kilamba não tem mufete: vai para outro balcão');
select is(testes.v('muf')::jsonb ->> 'cozinha_id', testes.v('via'), '... o mais perto que o vende (Viana, não o longe)');
select is((testes.v('muf')::jsonb ->> 'preco')::int, 4500, '... com o preço do prato dessa cozinha');
select is(testes.v('mua')::jsonb ->> 'estado', 'ninguem', 'ninguém faz muamba: não se promete');
select is(testes.v('q2'), '1', '«quero que façam» conta uma vez por cliente');
select is((testes.v('mua2')::jsonb ->> 'quero')::boolean, true, 'o cliente vê que já pediu');
select ok(testes.v('e_pratos') like '42501:%', 'o cliente não liga pratos');
select ok(testes.v('e_tabela') like '42501:%', 'as tabelas não se lêem directamente');

-- Funil: toque em «Pedir» na receita do mufete e pedido com o mufete de Viana
select testes.entrar(testes.u('cli'));
set local role authenticated;
select receita_tocou_pedir(testes.u('r_muf'));
reset role;
insert into pedidos (cliente_id, cozinha_id, itens, subtotal)
values (testes.u('cli'), testes.u('via'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muf_via'), 'qtd', 1, 'preco_unitario', 4500)), 4500);
insert into pedidos (cliente_id, cozinha_id, itens, subtotal)
values (testes.u('cli'), testes.u('kil'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('arroz'), 'qtd', 1, 'preco_unitario', 3000)), 3000);
select testes.entrar_funcionario(testes.u('ed'));
set local role authenticated;
select testes.def('met', receitas_metricas()::text);
reset role;
select is((testes.v('met')::jsonb #>> array[testes.v('r_muf'), 'pedidos'])::int, 1, 'funil: o pedido com o mufete conta (o do arroz não)');
select is((testes.v('met')::jsonb #>> array[testes.v('r_mua'), 'interessados'])::int, 1, 'o operador vê quantos querem a muamba');
select is((testes.v('met')::jsonb #>> array[testes.v('r_muf'), 'toques'])::int, 1, 'o toque ficou contado');

select * from finish();
rollback;
