-- Feira (consignação): carga, venda ao vivo com guarda de stock da carga, resumo/reconciliação,
-- fecho com devolvidos e perdas, e barreira de permissão (feira.gerir + cozinha).
begin;
\ir _helpers.psql
select plan(11);

select testes.def('coz', (select cozinha_padrao()));
select testes.def('gestor', testes.funcionario('Gestor Feira', array['feira.gerir', 'cozinhas.gerir']));
select testes.def('vendedor', testes.funcionario('Feirante', array['feira.gerir']));

-- Prato só de feira (não visível online)
with c as (insert into cardapio (cozinha_id, nome, preco, visivel_online)
           values (testes.u('coz'), 'Muamba (tigela)', 1500, false) returning id)
select testes.def('prato', id) from c;

select is((select count(*)::int from cardapio where id = testes.u('prato') and visivel_online), 0,
          'prato de feira está marcado como não visível online');

select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('feira', (select criar_feira(testes.u('coz'), testes.u('vendedor'), 'Feira do Bairro')));
select testes.def('item', (select feira_adicionar_item(testes.u('feira'), testes.u('prato'), 20)));
select testes.def('r1', (select feira_vender(testes.u('item'), 5, 'dinheiro'))::text);
select testes.def('r2', (select feira_vender(testes.u('item'), 3, 'transferencia', 'MCX-123'))::text);
select testes.def('e_overflow', testes.erro(format('select feira_vender(%L, 20, %L)', testes.u('item'), 'dinheiro')));
select testes.def('resumo', (select feira_resumo(testes.u('feira')))::text);
reset role;

select is(testes.v('r1'), '15', 'após vender 5, restam 15');
select is(testes.v('r2'), '12', 'após vender 3, restam 12');
select matches(testes.v('e_overflow'), 'sem_unidades', 'não deixa vender mais do que a carga');
select is((testes.v('resumo')::jsonb ->> 'esperado'), '12000', 'esperado = vendidos × preço (8×1500)');
select is((testes.v('resumo')::jsonb ->> 'recebido_dinheiro'), '7500', 'recebido em dinheiro (5×1500)');
select is((testes.v('resumo')::jsonb ->> 'recebido_transferencia'), '4500', 'recebido por transferência (3×1500)');
select is((testes.v('resumo')::jsonb ->> 'diferenca'), '0', 'sem diferença no acerto');

-- Fecho: 8 vendidos + 10 devolvidos + 2 perdas = 20 (a carga)
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select feira_fechar(testes.u('feira'),
       jsonb_build_array(jsonb_build_object('item_id', testes.u('item'), 'devolvida', 10, 'perda', 2)));
select testes.def('e_vender_fechada', testes.erro(format('select feira_vender(%L, 1, %L)', testes.u('item'), 'dinheiro')));
reset role;
select is((select estado from feiras where id = testes.u('feira')), 'fechada', 'feira fechada no acerto');
select matches(testes.v('e_vender_fechada'), 'feira_invalida', 'não se vende numa feira fechada');

-- Sem feira.gerir não cria feira
select testes.def('ze', testes.funcionario('Zé Sem Permissão', array[]::text[]));
select testes.entrar_funcionario(testes.u('ze'));
set local role authenticated;
select testes.def('e_sem_perm', testes.erro(format('select criar_feira(%L, %L, %L)', testes.u('coz'), testes.u('vendedor'), 'X')));
reset role;
select matches(testes.v('e_sem_perm'), '42501', 'sem feira.gerir não cria feira');

select * from finish();
rollback;
