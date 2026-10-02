-- I12 · Pacotes pré-pagos: adesão, pagamento, uso nos pedidos, venda, cancelamento, pausa e reembolso
begin;
\ir _helpers.psql
select plan(25);

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Muamba', 2500) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco) values ('Mufete', 3500) returning id) select testes.def('mufete', id) from m;
with p as (insert into pacotes (nome, refeicoes, refeicoes_oferta, valor_refeicao, preco, validade_dias, pausa_max_dias)
           values ('Almoço do Mês', 20, 2, 2500, 50000, 30, 5) returning id) select testes.def('pacote', id) from p;
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('empresa', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));
select testes.def('gestor', testes.funcionario('Gestora', array['pacotes.gerir']));
select testes.def('caixa_f', testes.funcionario('Caixa', array['vendas.registar']));

create function testes.novo_pedido(p_itens jsonb) returns uuid language plpgsql as $$
declare v uuid;
begin
  set local role authenticated;
  insert into pedidos (cliente_id, ponto_entrega_id, itens) values (testes.u('ana'), testes.u('casa'), p_itens) returning id into v;
  reset role;
  return v;
end $$;

-- Interruptor desligado
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_off', testes.erro(format($$select aderir_pacote(%L, 'multicaixa_express')$$, testes.v('pacote'))));
reset role;
select is(testes.v('e_off'), 'P0001:pacotes_inactivos', 'pacotes desligado: não se adere');

select testes.funcionalidade('pacotes', true);
set local role authenticated;
select testes.def('adesao', aderir_pacote(testes.u('pacote'), 'multicaixa_express'));
select testes.def('e_dupla', testes.erro(format($$select aderir_pacote(%L, 'loja')$$, testes.v('pacote'))));
select testes.def('e_escrever', testes.erro(format($$update adesoes_pacote set refeicoes_usadas = 0, estado = 'activa' where id = %L$$, testes.v('adesao'))));
select testes.def('pendente', meu_pacote()::text);
select testes.def('e_usar_pendente', testes.erro(format('select usar_pacote(%L)', testes.novo_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1))))));
reset role;
select is(testes.v('pendente')::jsonb ->> 'estado', 'pendente', 'adesão fica pendente até a equipa confirmar o pagamento');
select is(testes.v('e_dupla'), 'P0001:adesao_pendente', 'uma adesão pendente de cada vez');
select ok(testes.v('e_escrever') like '42501:%', 'o cliente não altera a adesão directamente');
select is(testes.v('e_usar_pendente'), 'P0001:sem_pacote', 'sem pagamento confirmado o pacote não se usa');

-- Confirmação do pagamento pela equipa
select testes.entrar_funcionario(testes.u('caixa_f'));
set local role authenticated;
select testes.def('e_sem_perm', testes.erro(format($$select confirmar_pagamento_pacote(%L, 'MCX-1')$$, testes.v('adesao'))));
reset role;
select is(testes.v('e_sem_perm'), '42501:sem_permissao', 'sem pacotes.gerir não se confirma o pagamento');
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('e_sem_ref', testes.erro(format($$select confirmar_pagamento_pacote(%L, ' ')$$, testes.v('adesao'))));
select testes.def('fim', confirmar_pagamento_pacote(testes.u('adesao'), 'MCX-123'));
reset role;
select is(testes.v('e_sem_ref'), 'P0001:referencia_obrigatoria', 'pagamento por Multicaixa precisa da referência');
select is(testes.v('fim')::date, hoje_luanda() + 29, 'activa por 30 dias a partir de hoje');

-- Pedido com 2 Muambas e 1 Mufete: 3 refeições; o Mufete paga 2.500 pelo pacote e 1.000 na entrega
select testes.entrar(testes.u('ana'));
select testes.def('p1', testes.novo_pedido(jsonb_build_array(
  jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2),
  jsonb_build_object('cardapio_id', testes.u('mufete'), 'qtd', 1))));
set local role authenticated;
select testes.def('pago1', usar_pacote(testes.u('p1')));
select testes.def('pago1b', usar_pacote(testes.u('p1')));
select testes.def('meu', meu_pacote()::text);
reset role;
select is(testes.v('pago1')::int, 7800, 'pacote paga 3 × 2.500 e a entrega (300)');
select is(testes.v('pago1b')::int, 7800, 'retentar não gasta refeições outra vez');
select is((testes.v('meu')::jsonb ->> 'refeicoes_restantes')::int, 19, 'restam 19 das 22 refeições');

select testes.entrar_funcionario(testes.u('gestor'));
update funcionarios set direcao_id = null, administrador_principal = true where id = testes.u('gestor');
set local role authenticated;
select testes.def('a_pagar', (select a_pagar from pedidos_operador() where pedido_id = testes.u('p1')));
reset role;
select is(testes.v('a_pagar')::int, 1000, 'na entrega só se cobra a diferença do prato mais caro (1.000 Kz)');

-- Entrega: parcelas + pacote = valor final; a venda leva a parcela Pacote
update pedidos set caixa_id = testes.caixa(), parcelas = '[{"metodo": "Dinheiro", "valor": 1000}]', estado = 'entregue_pago'
 where id = testes.u('p1');
select is((select sum((p ->> 'valor')::int)::int from vendas v cross join jsonb_array_elements(v.parcelas) p
            where v.pedido_id = testes.u('p1') and p ->> 'metodo' = 'Pacote'), 7800, 'as vendas levam 7.800 Kz em parcela Pacote');
select throws_ok(format($$update pedidos set caixa_id = %L, parcelas = '[{"metodo": "Dinheiro", "valor": 1000}]', estado = 'entregue_pago' where id = %L$$,
                        testes.caixa(), testes.novo_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1)))),
                 'P0001', null, 'sem usar o pacote, as parcelas têm de pagar tudo');

-- Cancelado: as refeições voltam
select testes.def('p2', testes.novo_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 2))));
select testes.entrar(testes.u('ana'));
set local role authenticated;
select usar_pacote(testes.u('p2'));
select testes.def('antes', (meu_pacote() ->> 'refeicoes_restantes'));
select cancelar_pedido(testes.u('p2'), 'mudei de ideias');
select testes.def('depois', (meu_pacote() ->> 'refeicoes_restantes'));
reset role;
select is(testes.v('antes')::int, 17, 'pedido de 2 refeições: restam 17');
select is(testes.v('depois')::int, 19, 'pedido cancelado: as 2 refeições voltam ao pacote');

-- Poupança mostrada ao cliente: 7.800 pagos pelo pacote − 3 × 50.000/20
set local role authenticated;
select testes.def('poupanca', (meu_pacote() ->> 'poupanca'));
reset role;
select is(testes.v('poupanca')::int, 300, 'poupança = o que o pacote pagou menos o que essas refeições custaram');

-- Pausa
set local role authenticated;
select testes.def('fim_pausa', pausar_pacote(3));
select testes.def('e_pausa', testes.erro('select pausar_pacote(3)'));
reset role;
select is(testes.v('fim_pausa')::date, hoje_luanda() + 32, 'pausa de 3 dias prolonga a validade');
select is(testes.v('e_pausa'), 'P0001:pausa_invalida', 'não passa do máximo de 5 dias de pausa');

-- Prova social: abaixo do mínimo não mostra números
set local role authenticated;
select testes.def('volta', pacotes_a_minha_volta()::text);
reset role;
select is(testes.v('volta')::jsonb -> 'no_meu_local', 'null'::jsonb, 'prova social só a partir do mínimo de clientes (sem números abaixo)');
update parametros set contador_minimo = 1 where unico;
set local role authenticated;
select testes.def('volta1', pacotes_a_minha_volta()::text);
reset role;
select is((testes.v('volta1')::jsonb ->> 'no_meu_local')::int, 1, 'com o mínimo atingido: quantos têm pacote no mesmo local');

-- Reembolso: 20 pagas, 3 usadas → 17 × 2.500 = 42.500 (as 2 de oferta não se reembolsam)
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('reembolso', reembolsar_pacote(testes.u('adesao'), 'MCX-R1'));
reset role;
select is(testes.v('reembolso')::int, 42500, 'reembolso das refeições pagas e não usadas');
select is((select estado from adesoes_pacote where id = testes.u('adesao')), 'reembolsada', 'adesão fica reembolsada');
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('e_depois', testes.erro(format('select usar_pacote(%L)', testes.novo_pedido(jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1))))));
reset role;
select is(testes.v('e_depois'), 'P0001:sem_pacote', 'depois do reembolso o pacote já não se usa');

-- Pagamento na loja precisa de caixa aberta
select testes.def('rui', testes.cliente('Rui Costa'));
select testes.entrar(testes.u('rui'));
set local role authenticated;
select testes.def('adesao_loja', aderir_pacote(testes.u('pacote'), 'loja'));
reset role;
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('e_loja', testes.erro(format($$select confirmar_pagamento_pacote(%L)$$, testes.v('adesao_loja'))));
reset role;
select is(testes.v('e_loja'), 'P0001:caixa_obrigatoria', 'pagamento na loja precisa da caixa onde o dinheiro entrou');

select * from finish();
rollback;
