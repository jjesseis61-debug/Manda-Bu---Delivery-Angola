-- I12 · Avisos dos pacotes: N15 à equipa, N13 no pagamento, N14 a acabar (refeições e validade)
begin;
\ir _helpers.psql
select plan(14);

with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 300) returning id) select testes.def('zona', id) from z;
with m as (insert into cardapio (nome, preco) values ('Muamba', 2500) returning id) select testes.def('muamba', id) from m;
with p as (insert into pacotes (nome, refeicoes, refeicoes_oferta, valor_refeicao, preco, validade_dias, pausa_max_dias)
           values ('Almoço do Mês', 4, 1, 2500, 10000, 30, 5) returning id) select testes.def('pacote', id) from p;
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('casa', testes.ponto('empresa', null, null, testes.u('zona')));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('ana'), testes.u('casa'));
select testes.def('gestor', testes.funcionario('Gestora', array['pacotes.gerir']));
select testes.def('caixa_f', testes.funcionario('Caixa', array['vendas.registar']));

create function testes.pedido_ana(p_qtd int) returns uuid language plpgsql as $$
declare v uuid;
begin
  set local role authenticated;
  insert into pedidos (cliente_id, ponto_entrega_id, itens)
  values (testes.u('ana'), testes.u('casa'), jsonb_build_array(jsonb_build_object('cardapio_id', testes.u('muamba'), 'qtd', p_qtd)))
  returning id into v;
  perform usar_pacote(v);
  reset role;
  return v;
end $$;
create function testes.n(p_codigo text) returns int language sql as $$
  select count(*)::int from notificacoes_fila where codigo = p_codigo;
$$;
-- Na mesma transacção os avisos têm a mesma hora: escolhe-se pelo motivo, não pelo mais recente
create function testes.texto(p_codigo text, p_motivo text default null) returns text language sql as $$
  select t.corpo from notificacoes_fila n cross join lateral texto_notificacao(n.codigo, n.dados) t
   where n.codigo = p_codigo and (p_motivo is null or n.dados ->> 'motivo' = p_motivo) limit 1;
$$;

-- N15: nova adesão, só a quem tem pacotes.gerir
select testes.funcionalidade('pacotes', true);
select testes.entrar(testes.u('ana'));
set local role authenticated;
select testes.def('adesao', aderir_pacote(testes.u('pacote'), 'multicaixa_express'));
reset role;
select is((select array_agg(funcionario_id) from notificacoes_fila where codigo = 'N15'), array[testes.u('gestor')],
          'N15: nova adesão avisa só quem tem pacotes.gerir');
select is(testes.texto('N15'), 'Ana aderiu ao Almoço do Mês (Multicaixa Express, ' || formatar_kz(10000) || '). Confirma o pagamento.',
          'N15: texto com o cliente, o pacote, o método e o preço');

-- N13: pagamento confirmado
select testes.entrar_funcionario(testes.u('gestor'));
set local role authenticated;
select confirmar_pagamento_pacote(testes.u('adesao'), 'MCX-1');
reset role;
select is(testes.n('N13'), 1, 'N13: pagamento confirmado avisa o cliente');
select is(testes.texto('N13'), format('O teu Almoço do Mês está activo: 5 refeições até %s. Bom almoço!',
                                      to_char(hoje_luanda() + 29, 'DD/MM')), 'N13: texto com as refeições e a validade');

-- N14 por refeições: só ao passar para 3 ou menos, uma vez por adesão
select testes.entrar(testes.u('ana'));
select testes.pedido_ana(1);
select is(testes.n('N14'), 0, 'com 4 refeições ainda não avisa');
select testes.pedido_ana(1);
select is(testes.n('N14'), 1, 'N14: ao ficar com 3 refeições avisa');
select is(testes.texto('N14', 'refeicoes'), 'Restam 3 refeições no teu Almoço do Mês. Renova para continuares a almoçar sem pagar na entrega.',
          'N14: texto das refeições a acabar');
select testes.pedido_ana(1);
select is(testes.n('N14'), 1, 'N14: não repete no pedido seguinte');

-- N14 por validade: job diário, 3 dias antes do fim, uma vez
update adesoes_pacote set fim = hoje_luanda() + 3 where id = testes.u('adesao');
select job_n14_pacotes();
select job_n14_pacotes();
select is((select count(*)::int from notificacoes_fila where codigo = 'N14' and dados ->> 'motivo' = 'validade'), 1,
          'N14: pacote a 3 dias do fim avisa uma vez');
select is(testes.texto('N14', 'validade'), format('O teu Almoço do Mês termina a %s e ainda tens 2 refeições. Usa-as ou pausa o pacote.',
                                      to_char(hoje_luanda() + 3, 'DD/MM')), 'N14: texto da validade');

-- Envio: só com o interruptor ligado
select is((select array_agg(distinct codigo order by codigo) from notificacoes_por_enviar(1000) where codigo in ('N13', 'N14', 'N15')),
          array['N13', 'N14', 'N15'], 'com pacotes ligado os avisos seguem para envio');
select testes.funcionalidade('pacotes', false);
select is((select count(*)::int from notificacoes_por_enviar(1000) where codigo in ('N13', 'N14', 'N15')), 0,
          'com pacotes desligado nenhum aviso sai');
select job_n14_pacotes();
select is((select count(*)::int from notificacoes_fila where codigo = 'N14'), 2, 'com pacotes desligado o job não cria avisos');

-- Funções internas fechadas às apps
select ok(not has_function_privilege('authenticated', 'job_n14_pacotes()', 'execute')
          and not has_function_privilege('authenticated', 'funcionarios_com_permissao(text)', 'execute'),
          'job e lista de funcionários não são chamáveis pelas apps');

select * from finish();
rollback;
