-- Encomendas de receitas: cliente -> operador -> cozinha propõe -> operador aprova -> cliente aceita
-- (pedido agendado) -> sinal pago antes; recusas, prazos, permissões.
begin;
\ir _helpers.psql
select plan(19);

select testes.funcionalidade('encomendas', true);
select testes.funcionalidade('receitas', true);
with c as (insert into cozinhas (nome, responsavel) values ('Viana E', 'Ana') returning id) select testes.def('via', id) from c;
with c as (insert into cozinhas (nome, responsavel) values ('Rangel E', 'Bia') returning id) select testes.def('ran', id) from c;
update cozinhas set estado = 'activa', aberta = true where id in (testes.u('via'), testes.u('ran'));
insert into cozinhas_localizacao (cozinha_id, lat, lng) values (testes.u('via'), -8.90, 13.37), (testes.u('ran'), -8.83, 13.26);
with z as (insert into zonas (nome, tipo, taxa) values ('Zona E', 'Própria', 1500) returning id) select testes.def('zona', id) from z;
with r as (insert into receitas (titulo, corpo, estado, publicado_em) values ('Mufete E', 'x', 'publicada', now()) returning id)
select testes.def('rec', id) from r;
-- O Rangel já fez mufete (prato ligado à receita): é sugerido primeiro
with m as (insert into cardapio (nome, preco, cozinha_id, disponivel) values ('Mufete E', 4500, testes.u('ran'), false) returning id)
insert into receitas_pratos (receita_id, cardapio_id) select testes.u('rec'), id from m;

select testes.def('cli', testes.cliente('Clara Encomenda'));
select testes.def('outro', testes.cliente('Outro Cliente'));
select testes.def('ponto', testes.ponto('residencial', -8.89, 13.36, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('cli'), testes.u('ponto'));

-- Cliente encomenda
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('e_cedo', testes.erro(format($$select encomendar(%L, 6, now() + interval '3 hours', %L)$$, testes.v('rec'), testes.v('ponto'))));
select testes.def('e_poucos', testes.erro(format($$select encomendar(%L, 2, now() + interval '2 days', %L)$$, testes.v('rec'), testes.v('ponto'))));
select testes.def('enc', encomendar(testes.u('rec'), 6, now() + interval '2 days', testes.u('ponto'), 'Sem jindungo'));
select testes.def('e_tabela', testes.erro($$select count(*) from encomendas$$));
select testes.def('e_lista', testes.erro($$select encomendas_lista()$$));
reset role;
select is(testes.v('e_cedo'), 'P0001:encomenda_data', 'menos de 24 h de antecedência é recusado');
select is(testes.v('e_poucos'), 'P0001:encomenda_pessoas', 'menos de 4 pessoas é recusado');
select is((select estado from encomendas where id = testes.u('enc')), 'pedida', 'a encomenda fica pedida');
select ok(testes.v('e_tabela') like '42501:%', 'a tabela não se lê directamente');
select ok(testes.v('e_lista') like '42501:%', 'o cliente não vê a lista do operador');

-- Outro cliente não usa a morada da Clara
select testes.entrar(testes.u('outro'));
set local role authenticated;
select testes.def('e_ponto', testes.erro(format($$select encomendar(%L, 6, now() + interval '2 days', %L)$$, testes.v('rec'), testes.v('ponto'))));
reset role;
select is(testes.v('e_ponto'), 'P0001:ponto_invalido', 'só nas moradas do próprio cliente');

-- Operador: sugestões e envio à cozinha
select testes.def('op', testes.funcionario('Olga Operadora', array['pedidos.gerir']));
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select testes.def('lista', encomendas_lista()::text);
select encomenda_enviar_cozinha(testes.u('enc'), testes.u('via'));
reset role;
select is((select x #>> '{sugestoes,0,nome}' from jsonb_array_elements(testes.v('lista')::jsonb) x where x ->> 'id' = testes.v('enc')),
          'Rangel E', 'sugere primeiro a cozinha que já faz o prato');

-- A cozinha de Viana recusa: volta ao operador
select testes.def('chefe_via', testes.funcionario('Chefe Viana', array['cozinhas.gerir']));
select testes.def('chefe_ran', testes.funcionario('Chefe Rangel', array['vendas.registar']));
insert into equipa_cozinha (cozinha_id, funcionario_id) values (testes.u('ran'), testes.u('chefe_ran'));
select testes.entrar_funcionario(testes.u('chefe_via'));
set local role authenticated;
select encomenda_resposta_cozinha(testes.u('enc'), null, 'Sem peixe esta semana');
reset role;
select is((select estado || '|' || coalesce(cozinha_id::text, '-') from encomendas where id = testes.u('enc')), 'pedida|-',
          'a cozinha recusa: volta a pedida, sem cozinha');
select ok((select motivo from encomendas where id = testes.u('enc')) like '%Sem peixe%', 'o operador vê porquê');

-- Envia ao Rangel; a cozinha propõe; uma cozinha de fora não mexe
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select encomenda_enviar_cozinha(testes.u('enc'), testes.u('ran'));
reset role;
select testes.entrar_funcionario(testes.u('chefe_ran'));
set local role authenticated;
select encomenda_resposta_cozinha(testes.u('enc'), 24000, 'Tilápia fresca');
select testes.def('lista_ran', encomendas_lista()::text);
reset role;
select is((select preco_cozinha from encomendas where id = testes.u('enc')), 24000, 'a cozinha propõe 24.000 Kz');
select is(jsonb_array_length(testes.v('lista_ran')::jsonb), 1, 'a cozinha vê a encomenda que lhe foi enviada');

-- Operador aprova com ajuste; o cliente vê a proposta com entrega e sinal
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select encomenda_aprovar(testes.u('enc'), 25000);
reset role;
select testes.entrar(testes.u('cli'));
set local role authenticated;
select testes.def('minhas', minhas_encomendas()::text);
select testes.def('ped', encomenda_responder(testes.u('enc'), true));
select testes.def('e_sinal_ref', testes.erro(format($$select encomenda_pagar_sinal(%L, 'multicaixa_express', '1')$$, testes.v('enc'))));
select testes.def('pag', encomenda_pagar_sinal(testes.u('enc'), 'multicaixa_express', 'MCX-SINAL-1'));
reset role;
select is(testes.v('minhas')::jsonb #>> '{0,estado}', 'a_confirmar', 'o cliente vê a proposta');
select is((testes.v('minhas')::jsonb #>> '{0,total}')::int, 26500, 'total = 25.000 + 1.500 de entrega');
select is((testes.v('minhas')::jsonb #>> '{0,sinal}')::int, 13250, 'sinal de 50%');
select is((select estado || '|' || subtotal || '|' || taxa_entrega || '|' || (agendado_para is not null) from pedidos where id = testes.u('ped')),
          'confirmado|25000|1500|true', 'aceite: nasce um pedido agendado normal');
select is((select pedido_id from encomendas where id = testes.u('enc')), testes.u('ped'), 'a encomenda fica ligada ao pedido');
select is(testes.v('e_sinal_ref'), 'P0001:referencia_invalida', 'sinal exige referência');
select is((select valor from pagamentos_antecipados where id = testes.u('pag')), 13250, 'o sinal vai para as Finanças confirmarem');

-- Finanças confirmam: o estafeta só cobra o resto
select testes.def('fin', testes.funcionario('Fina', array['financas.acertos']));
select testes.entrar_funcionario(testes.u('fin'));
set local role authenticated;
select decidir_pagamento_antes(testes.u('pag'), true);
reset role;
select is((select pedido_falta_pagar(p) from pedidos p where id = testes.u('ped')), 13250, 'depois do sinal, falta pagar 13.250 na entrega');

select * from finish();
rollback;
