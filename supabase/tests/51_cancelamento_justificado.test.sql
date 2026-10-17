-- Cancelamento pela cozinha com uma justificação séria: fica registado quem cancelou; o motivo da lista vira uma frase
-- revista; diz o prato e a devolução do pacote ou do saldo; o cliente só lê a dos seus pedidos
begin;
\ir _helpers.psql
select plan(9);

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Muamba de galinha', 3500) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco) values ('Sumo', 500) returning id) select testes.def('sumo', id) from m;
select testes.def('gerente', testes.funcionario('Gerente', array['pedidos.gerir']));
insert into turnos (data, funcionario_id, cozinha_id) values (current_date, testes.u('gerente'), cozinha_padrao());
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('bia', testes.cliente('Bia Neto'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));
create function pg_temp.pedir(p_itens jsonb) returns uuid language plpgsql as $$
declare v uuid;
begin
  perform testes.entrar(testes.u('ana'));
  set local role authenticated;
  insert into pedidos (cliente_id, ponto_entrega_id, itens) values (testes.u('ana'), testes.u('casa'), p_itens) returning id into v;
  reset role;
  perform testes.sair();
  return v;
end $$;
create function pg_temp.cozinha_cancela(p_pedido text, p_motivo text) returns void language plpgsql as $$
begin
  perform testes.entrar_funcionario(testes.u('gerente'));
  set local role authenticated;
  perform mudar_estado_pedido(testes.u(p_pedido), 'cancelado', p_motivo, null, null);
  reset role;
  perform testes.sair();
end $$;
create function pg_temp.ler(p_cliente text, p_pedido text, p_curta boolean default false) returns text language plpgsql as $$
declare v text;
begin
  perform testes.entrar(testes.u(p_cliente));
  set local role authenticated;
  v := justificacao_cancelamento(testes.u(p_pedido), p_curta);
  reset role;
  perform testes.sair();
  return v;
end $$;
create function pg_temp.um(p text, q int default 1) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('cardapio_id', testes.v(p), 'qtd', q));
$$;

-- Motivo da lista, sem pacote nem saldo
select testes.def('p1', pg_temp.pedir(pg_temp.um('muamba')));
select pg_temp.cozinha_cancela('p1', 'Avaria na cozinha (gás, luz ou equipamento)');
select is((select cancelado_por from pedidos where id = testes.u('p1')), 'cozinha', 'fica registado que foi a cozinha a cancelar');
select is(pg_temp.ler('ana', 'p1'),
          'Lamentamos muito: tivemos de cancelar o teu pedido de Muamba de galinha por uma avaria na cozinha. '
          'Sabemos que contavas com esta refeição. Não tens nada a pagar. Se quiseres, podes pedir já outro prato.',
          'versão completa: assume, diz o prato e o motivo, reconhece o impacto e diz o passo seguinte');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N16' and dados ->> 'pedido_id' = testes.v('p1')),
          'Lamentamos: tivemos de cancelar o teu pedido de Muamba de galinha por uma avaria na cozinha. Não tens nada a pagar.',
          'a notificação leva a versão curta');

-- Vários pratos, pacote e saldo devolvidos
select testes.def('p2', pg_temp.pedir(pg_temp.um('muamba') || pg_temp.um('sumo') || pg_temp.um('sumo', 2)));
alter table pedidos disable trigger user;
update pedidos set refeicoes_pacote = 2, credito_indicacao_usado = 500 where id = testes.u('p2');
alter table pedidos enable trigger user;
select pg_temp.cozinha_cancela('p2', 'Acabou um ingrediente');
select is(pg_temp.ler('ana', 'p2', true),
          'Lamentamos: tivemos de cancelar o teu pedido de Muamba de galinha e mais 2 pratos porque acabou um dos ingredientes do prato. '
          'Não tens nada a pagar e as refeições do pacote e o saldo que usaste já foram devolvidos.',
          'diz quantos pratos mais e que o pacote e o saldo já foram devolvidos');
alter table pedidos disable trigger user;
update pedidos set credito_indicacao_usado = 0, refeicoes_pacote = 1 where id = testes.u('p2');
alter table pedidos enable trigger user;
select ok(pg_temp.ler('ana', 'p2', true) like '%Não tens nada a pagar e a refeição do pacote já foi devolvida.',
          'só o pacote: uma refeição devolvida');

-- Outros motivos da lista e texto livre arrumado
select ok(frase_motivo_cancelamento('A cozinha não conseguiria entregar a horas') = ' porque não conseguiríamos entregá-lo a horas'
          and frase_motivo_cancelamento('Endereço fora da zona de entrega') = ' porque o endereço está fora da nossa zona de entrega'
          and frase_motivo_cancelamento('  Sem gás.  ') = ' pelo seguinte motivo: sem gás'
          and frase_motivo_cancelamento('   ') = '',
          'cada motivo da lista tem a sua frase; outro texto é arrumado; sem motivo não se inventa');

-- O próprio cliente cancela
select testes.def('p3', pg_temp.pedir(pg_temp.um('sumo')));
select testes.entrar(testes.u('ana'));
set local role authenticated;
select cancelar_pedido(testes.u('p3'), 'Mudei de ideias');
reset role;
select testes.sair();
select ok((select cancelado_por from pedidos where id = testes.u('p3')) = 'cliente' and pg_temp.ler('ana', 'p3') = 'Cancelaste este pedido.',
          'quando é o cliente a cancelar, não se pede desculpa por ele');

-- Privacidade e pedidos por cancelar
select testes.def('p4', pg_temp.pedir(pg_temp.um('sumo')));
select ok(pg_temp.ler('bia', 'p1') is null and pg_temp.ler('ana', 'p4') is null,
          'outro cliente não lê a justificação; um pedido não cancelado não tem justificação');
select ok(not has_function_privilege('anon', 'justificacao_cancelamento(uuid, boolean)', 'execute')
          and not has_function_privilege('authenticated', 'pedidos_cancelado_por()', 'execute'),
          'sem sessão não se lê; a função do trigger não se chama');

select * from finish();
rollback;
