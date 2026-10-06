-- Conta de empresa (B2B): filiação, parte coberta pela empresa, a_pagar do cliente e relatório.
begin;
\ir _helpers.psql
select plan(7);

select testes.def('gestor', testes.funcionario('Gestor', array['clientes.gerir']));
select testes.def('op', testes.funcionario('Despacho', array['pedidos.gerir']));
select testes.def('func', testes.cliente('Funcionario Empresa'));
select testes.def('estranho', testes.cliente('Cliente de Fora'));
select testes.def('cod', testes.codigo(testes.u('func')));
with z as (insert into zonas (nome, tipo, taxa) values ('Zona Empresa', 'Própria', 300) returning id)
select testes.def('zona', id) from z;
select testes.def('ponto', testes.ponto('residencial', null, null, testes.u('zona')));
update pontos_entrega set criado_por_cliente = testes.u('func') where id = testes.u('ponto');
with x as (insert into cardapio (nome, preco, cozinha_id) values ('Almoço', 5000, cozinha_padrao()) returning id)
select testes.def('prato', id) from x;

-- O gestor cria a empresa (limite 3000/refeição) e adiciona o funcionário pelo código
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('emp', criar_empresa('Empresa X', 3000));
select empresa_adicionar_membro(testes.u('emp'), testes.v('cod'));
reset role;
select testes.sair();

-- O funcionário vê a sua empresa e faz um pedido na conta
select testes.entrar(testes.u('func'));
set local role authenticated;
select testes.def('minha', minha_empresa());
insert into pedidos (id, cliente_id, ponto_entrega_id, itens, subtotal, taxa_entrega, empresa_id)
values ('00000000-0000-0000-0000-0000000e0001', testes.u('func'), testes.u('ponto'),
        jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('prato'), 'qtd', 1, 'preco_unitario', 5000, 'nome', 'Almoço')),
        5000, 0, testes.u('emp'));
reset role;
select testes.sair();
select is(testes.v('minha')::jsonb ->> 'nome', 'Empresa X', 'o funcionário vê a sua conta de empresa');
select is((select valor_empresa from pedidos where id = '00000000-0000-0000-0000-0000000e0001'), 3000,
          'a empresa cobre até ao limite (3000)');

-- O que o cliente paga na entrega é só a diferença
select testes.entrar_funcionario(testes.u('op'));
set local role authenticated;
select testes.def('apagar', (select a_pagar from pedidos_operador() where pedido_id = '00000000-0000-0000-0000-0000000e0001'));
reset role;
select testes.sair();
-- 5000 (subtotal) + 300 (taxa da zona) − 3000 (empresa) = 2300
select is(testes.v('apagar')::int, 2300, 'o cliente paga só a diferença (2300)');

-- Um não-membro com empresa_id não é coberto (e o empresa_id é limpo)
insert into pedidos (id, cliente_id, subtotal, empresa_id)
values ('00000000-0000-0000-0000-0000000e0002', testes.u('estranho'), 5000, testes.u('emp'));
select is((select valor_empresa from pedidos where id = '00000000-0000-0000-0000-0000000e0002'), 0,
          'não-membro: a empresa não cobre');
select is((select empresa_id from pedidos where id = '00000000-0000-0000-0000-0000000e0002'), null,
          'não-membro: empresa_id é limpo');

-- Relatório mensal soma a parte da empresa dos pedidos entregues (sem passar pelo fluxo de caixa)
alter table pedidos disable trigger user;
update pedidos set estado = 'entregue_pago', entregue_em = now()
 where id = '00000000-0000-0000-0000-0000000e0001';
alter table pedidos enable trigger user;
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select testes.def('rel', relatorio_empresa(testes.u('emp'), extract(year from now())::int, extract(month from now())::int));
reset role;
select testes.sair();
select is(testes.v('rel')::jsonb ->> 'total', '3000', 'relatório mensal soma a parte da empresa');

-- Só quem gere clientes cria empresas
select testes.entrar(testes.u('func'));
set local role authenticated;
select testes.def('e_criar', testes.erro($$select criar_empresa('Pirata', 0)$$));
reset role;
select testes.sair();
select ok(testes.v('e_criar') like '42501%', 'criar_empresa exige clientes.gerir');

select * from finish();
rollback;
