-- I9 · Pratos montáveis: opções por grupo, validação e preço no servidor
begin;
\ir _helpers.psql
select plan(14);

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Muamba', 2500) returning id) select testes.def('muamba', id) from m;
with m as (insert into cardapio (nome, preco) values ('Calulu', 3000) returning id) select testes.def('calulu', id) from m;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo, ordem) values (testes.u('muamba'), 'Base', 1, 1, 1) returning id)
select testes.def('g_base', id) from g;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo, ordem) values (testes.u('muamba'), 'Extras', 0, 2, 2) returning id)
select testes.def('g_extra', id) from g;
with g as (insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (testes.u('calulu'), 'Base', 0, 1) returning id)
select testes.def('g_calulu', id) from g;
with o as (insert into opcoes (grupo_id, nome, ordem) values (testes.u('g_base'), 'Funge', 1) returning id) select testes.def('funge', id) from o;
with o as (insert into opcoes (grupo_id, nome, ordem) values (testes.u('g_base'), 'Arroz', 2) returning id) select testes.def('arroz', id) from o;
with o as (insert into opcoes (grupo_id, nome, preco_extra, ordem) values (testes.u('g_extra'), 'Ovo', 200, 1) returning id) select testes.def('ovo', id) from o;
with o as (insert into opcoes (grupo_id, nome, preco_extra, ordem) values (testes.u('g_extra'), 'Banana', 300, 2) returning id) select testes.def('banana', id) from o;
with o as (insert into opcoes (grupo_id, nome, preco_extra, ordem) values (testes.u('g_extra'), 'Salada', 150, 3) returning id) select testes.def('salada', id) from o;
with o as (insert into opcoes (grupo_id, nome, preco_extra, disponivel) values (testes.u('g_extra'), 'Gindungo', 50, false) returning id) select testes.def('gindungo', id) from o;
with o as (insert into opcoes (grupo_id, nome) values (testes.u('g_calulu'), 'Pirão') returning id) select testes.def('pirao', id) from o;

select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('residencial', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));

create function testes.orc(p_opcoes text) returns text language plpgsql as $$
begin
  return (select orcamento_pedido(format('[{"cardapio_id": "%s", "qtd": 2, "opcoes": %s}]', testes.v('muamba'), p_opcoes)::jsonb,
                                  testes.u('casa'))::text);
exception when others then
  return sqlstate || ':' || sqlerrm;
end $$;

select testes.entrar(testes.u('ana'));

-- Interruptor desligado: as opções são ignoradas e o prato custa o preço base
select is((testes.orc(format('["%s"]', testes.v('ovo')))::jsonb ->> 'subtotal')::int, 5000,
          'pratos_montaveis desligado: opções ignoradas, preço base');

select testes.funcionalidade('pratos_montaveis', true);
set local role authenticated;
select testes.def('r_ok', testes.orc(format('["%s", "%s"]', testes.v('funge'), testes.v('ovo'))));
select testes.def('r_falta', testes.orc(format('["%s"]', testes.v('ovo'))));
select testes.def('r_mais', testes.orc(format('["%s", "%s", "%s", "%s"]', testes.v('arroz'), testes.v('ovo'), testes.v('banana'), testes.v('salada'))));
select testes.def('r_outro', testes.orc(format('["%s", "%s"]', testes.v('funge'), testes.v('pirao'))));
select testes.def('r_rep', testes.orc(format('["%s", "%s", "%s"]', testes.v('funge'), testes.v('ovo'), testes.v('ovo'))));
select testes.def('r_indisp', testes.orc(format('["%s", "%s"]', testes.v('funge'), testes.v('gindungo'))));
select testes.def('r_lixo', testes.orc('["nao-e-uuid"]'));
reset role;

select is((testes.v('r_ok')::jsonb ->> 'subtotal')::int, 5400, 'preço = (2500 + 200 do ovo) × 2');
select is(testes.v('r_ok')::jsonb #>> '{itens,0,nome}', 'Muamba (Funge, Ovo)', 'o nome do item leva as opções, pela ordem dos grupos');
select is(jsonb_array_length(testes.v('r_ok')::jsonb #> '{itens,0,opcoes}'), 2, 'as opções ficam guardadas no item');
select is(split_part(testes.v('r_falta'), ':', 2), 'opcoes_em_falta', 'grupo obrigatório (Base) sem escolha: recusado');
select is(split_part(testes.v('r_mais'), ':', 2), 'opcoes_a_mais', 'mais extras do que o máximo: recusado');
select is(split_part(testes.v('r_outro'), ':', 2), 'opcao_invalida', 'opção de outro prato: recusada');
select is(split_part(testes.v('r_rep'), ':', 2), 'opcao_invalida', 'opção repetida: recusada');
select is(split_part(testes.v('r_indisp'), ':', 2), 'opcao_invalida', 'opção indisponível: recusada');
select is(split_part(testes.v('r_lixo'), ':', 2), 'opcao_invalida', 'id inválido: recusado');

-- O pedido feito pela app fica com o preço e as opções calculados no servidor
set local role authenticated;
with p as (insert into pedidos (cliente_id, ponto_entrega_id, itens)
           values (testes.u('ana'), testes.u('casa'),
                   jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', 1, 'preco_unitario', 1,
                                                        'opcoes', jsonb_build_array(testes.u('arroz'), testes.u('banana')))))
           returning id)
select testes.def('pedido', id) from p;
select testes.def('e_cliente_grupo', testes.erro(format($$insert into opcoes_grupos (cardapio_id, nome) values (%L, 'Molho')$$, testes.v('muamba'))));
reset role;
select is((select subtotal || '|' || (itens -> 0 ->> 'preco_unitario') from pedidos where id = testes.u('pedido')), '2800|2800',
          'o preço enviado pela app é ignorado: 2500 + 300 da banana');
select testes.pagar(testes.u('pedido'));
select is((select produto from vendas where pedido_id = testes.u('pedido')), 'Muamba (Arroz, Banana)',
          'a venda gerada mostra o prato montado');
select ok(testes.v('e_cliente_grupo') like '42501:%', 'o cliente não cria grupos de opções');

select testes.def('chefe', testes.funcionario('Chefe', array['cozinhas.gerir']));
select testes.entrar_funcionario(testes.u('chefe'));
set local role authenticated;
select testes.def('e_chefe', testes.erro(format($$insert into opcoes_grupos (cardapio_id, nome, minimo, maximo) values (%L, 'Molho', 0, 1)$$, testes.v('calulu'))));
reset role;
select is(testes.v('e_chefe'), 'sem_erro', 'cozinhas.gerir cria grupos de opções');

select * from finish();
rollback;
