-- Caixa na app do operador: abrir, sangrias, resumo (só a parcela Dinheiro) e fecho com contagem
begin;
\ir _helpers.psql
select plan(17);

select testes.def('cz', cozinha_padrao());
with c as (insert into cozinhas (nome, responsavel) values ('Cozinha do Kilamba', 'Rosa') returning id) select testes.def('outra', id) from c;
select testes.def('caixa_f', testes.funcionario('Caixa', array['vendas.registar']));
select testes.def('fora', testes.funcionario('Caixa de fora', array['vendas.registar']));
select testes.def('estafeta', testes.funcionario('Estafeta', array['entregas.registar']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('caixa_f'), testes.u('cz'));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('fora'), testes.u('outra'));
select testes.def('ana', testes.cliente('Ana Sousa'));

-- Abrir
select testes.entrar_funcionario(testes.u('caixa_f'));
set local role authenticated;
select testes.def('cx', abrir_caixa(testes.u('cz'), ' Balcão ', 5000));
select testes.def('dupla', testes.erro(format($$select abrir_caixa(%L, 'balcão', 0)$$, testes.v('cz'))));
select testes.def('posto_vazio', testes.erro(format($$select abrir_caixa(%L, '  ', 0)$$, testes.v('cz'))));
select testes.def('vejo', (select count(*) from caixa where id = testes.u('cx')));
reset role;
select is((select posto from caixa where id = testes.u('cx')), 'Balcão', 'abre a caixa com o posto sem espaços');
select is((select funcionario_nome from caixa where id = testes.u('cx')), 'Caixa', 'e quem a abriu');
select ok(testes.v('dupla') like '%caixa_ja_aberta%', 'uma caixa aberta por posto e cozinha');
select ok(testes.v('posto_vazio') like '%posto_invalido%', 'o posto é obrigatório');
select is(testes.v('vejo')::int, 1, 'quem tem vendas.registar vê as caixas');

select testes.entrar_funcionario(testes.u('fora'));
set local role authenticated;
select testes.def('e_fora', testes.erro(format($$select abrir_caixa(%L, 'Outro', 0)$$, testes.v('cz'))));
select testes.def('e_fora_s', testes.erro(format($$select registar_sangria(%L, 100, 'x')$$, testes.v('cx'))));
reset role;
select ok(testes.v('e_fora') like '42501:%', 'não abre caixa numa cozinha onde não trabalha');
select ok(testes.v('e_fora_s') like '42501:%', 'nem mexe na caixa de outra cozinha');

select testes.entrar_funcionario(testes.u('estafeta'));
set local role authenticated;
select testes.def('e_estafeta', testes.erro(format($$select abrir_caixa(%L, 'Moto', 0)$$, testes.v('cz'))));
reset role;
select ok(testes.v('e_estafeta') like '42501:%', 'sem vendas.registar não abre caixa');

-- Dinheiro que entra: pedido pago com parcela Dinheiro + Multicaixa, pacote pago na loja
select testes.def('ped', testes.pedido(testes.u('ana')));
insert into storage.objects (bucket_id, name) values ('comprovativos', testes.v('ped') || '/mcx.jpg');
update pedidos set caixa_id = testes.u('cx'), estado = 'entregue_pago',
       parcelas = jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', 2000),
                                    jsonb_build_object('metodo', 'Multicaixa Express', 'valor', 1000,
                                                       'referencia', 'MCX 7781', 'comprovativo', testes.v('ped') || '/mcx.jpg'))
 where id = testes.u('ped');
with p as (insert into pacotes (nome, refeicoes, refeicoes_oferta, valor_refeicao, preco, validade_dias, pausa_max_dias)
           values ('Almoço do Mês', 20, 2, 2000, 40000, 30, 5) returning id)
insert into adesoes_pacote (cliente_id, pacote_id, estado, metodo, refeicoes, refeicoes_oferta, valor_refeicao, preco,
                            validade_dias, pausa_max_dias, entrega_gratis, caixa_id)
select testes.u('ana'), p.id, 'activa', 'loja', 20, 2, 2000, 40000, 30, 5, true, testes.u('cx') from p;

-- Sangrias
select testes.entrar_funcionario(testes.u('caixa_f'));
set local role authenticated;
select testes.def('sang', registar_sangria(testes.u('cx'), 1500, 'Compra de gás'));
select testes.def('e_valor', testes.erro(format($$select registar_sangria(%L, 0, 'x')$$, testes.v('cx'))));
select testes.def('e_motivo', testes.erro(format($$select registar_sangria(%L, 10, ' ')$$, testes.v('cx'))));
select testes.def('res', resumo_caixa(testes.u('cx')));
reset role;
select is(testes.v('sang')::numeric, 1500::numeric, 'regista a sangria');
select ok(testes.v('e_valor') like '%valor_invalido%' and testes.v('e_motivo') like '%motivo_obrigatorio%',
          'sangria com valor e motivo');
select is(testes.v('res')::jsonb -> 'dinheiro_vendas', '2000'::jsonb, 'o caixa só soma a parcela Dinheiro das vendas');
select is((testes.v('res')::jsonb ->> 'esperado')::numeric, 45500::numeric,
          'esperado = troco 5000 + dinheiro 2000 + pacote na loja 40000 − sangria 1500');

-- Fecho (o pagamento por Multicaixa é conferido antes)
select testes.entrar_funcionario(testes.u('caixa_f'));
set local role authenticated;
select conferir_comprovativo((select id from comprovativos_pagamento where pedido_id = testes.u('ped')), true);
select testes.def('fecho', fechar_caixa(testes.u('cx'), 45000, 'Faltam 500'));
select testes.def('e_depois', testes.erro(format($$select registar_sangria(%L, 100, 'x')$$, testes.v('cx'))));
select testes.def('e_refechar', testes.erro(format($$select fechar_caixa(%L, 1)$$, testes.v('cx'))));
update caixa set troco_inicial = 1 where id = testes.u('cx');
select testes.def('nova', testes.erro(format($$select abrir_caixa(%L, 'Balcão', 0)$$, testes.v('cz'))));
reset role;
select is((testes.v('fecho')::jsonb ->> 'diferenca')::numeric, -500::numeric, 'o fecho guarda o contado e a diferença');
select ok(testes.v('e_depois') like '%caixa_fechada%' and testes.v('e_refechar') like '%caixa_fechada%',
          'caixa fechada não aceita sangrias nem novo fecho');
select is((select troco_inicial::int from caixa where id = testes.u('cx')), 5000, 'nem escrita directa na tabela');
select is(testes.v('nova'), 'sem_erro', 'depois do fecho abre-se outra caixa no mesmo posto');
select ok((select count(*) from auditoria where ref_id = testes.u('cx')
            and acao in ('caixa_aberta', 'caixa_sangria', 'caixa_fechada')) = 3, 'abertura, sangria e fecho na auditoria');

select * from finish();
rollback;
