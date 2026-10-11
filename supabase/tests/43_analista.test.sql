-- Analista do administrador: perguntas (permissão, interruptor, limite diário), relatório mensal com N25,
-- ferramentas agregadas só do serviço e sem nomes de clientes, e quem vê as respostas
begin;
\ir _helpers.psql
select plan(20);

select testes.funcionalidade('agente_analista', true);
select testes.def('cz', cozinha_padrao());
select testes.def('paula', testes.funcionario('Paula Directora', array['analista.usar']));
select testes.def('tito', testes.funcionario('Tito Analista', array['analista.usar']));
select testes.def('rui', testes.funcionario('Rui Mateus', array['entregas.registar']));
select testes.def('ana', testes.cliente('Ana Sousa'));
select testes.def('bia', testes.cliente('Bia Neto'));
with z as (insert into zonas (nome, tipo, taxa) values ('Talatona', 'Própria', 500) returning id) select testes.def('zona', id) from z;
select testes.def('ponto', testes.ponto('empresa', null, null, testes.u('zona')));

-- Ana: 2 pedidos entregues (um com 1★); Bia: 1 entregue e 1 cancelado
create function pg_temp.pedido(p_cliente text, p_prato text, p_valor int) returns uuid language sql as $$
  insert into pedidos (cliente_id, ponto_entrega_id, zona_id, cozinha_id, subtotal, itens)
  values (testes.u(p_cliente), testes.u('ponto'), testes.u('zona'), testes.u('cz'), p_valor,
          jsonb_build_array(jsonb_build_object('nome', p_prato, 'qtd', 1, 'preco_unitario', p_valor)))
  returning id;
$$;
select testes.def('P1', pg_temp.pedido('ana', 'Muamba', 3000));
select testes.def('P2', pg_temp.pedido('ana', 'Calulu', 3500));
select testes.def('P3', pg_temp.pedido('bia', 'Muamba', 3000));
select testes.def('P4', pg_temp.pedido('bia', 'Muamba', 3000));
select testes.pagar(testes.u('P1'));
select testes.pagar(testes.u('P2'));
select testes.pagar(testes.u('P3'));
update pedidos set estado = 'cancelado', motivo_cancelamento = 'Sem gás' where id = testes.u('P4');
select testes.funcionalidade('avaliacoes', true);
select testes.entrar(testes.u('ana'));
set local role authenticated;
insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario) values (testes.u('P1'), testes.u('ana'), 1, 'Veio frio');
reset role;
select testes.sair();

-- Perguntas pela app
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('e_rui', testes.erro($$select perguntar_analista('Quanto vendemos ontem?')$$));
reset role;
select testes.entrar_funcionario(testes.u('paula'));
set local role authenticated;
select testes.def('Q1', perguntar_analista('Que prato vende mais e como estão as avaliações?'));
select testes.def('e_curta', testes.erro($$select perguntar_analista('oi')$$));
select testes.def('R1', pedir_relatorio_analista(extract(year from now() at time zone 'Africa/Luanda')::int,
                                                extract(month from now() at time zone 'Africa/Luanda')::int));
select testes.def('R1b', pedir_relatorio_analista(extract(year from now() at time zone 'Africa/Luanda')::int,
                                                 extract(month from now() at time zone 'Africa/Luanda')::int));
select testes.def('e_futuro', testes.erro('select pedir_relatorio_analista(2100, 1)'));
reset role;
select testes.sair();
select ok(testes.v('e_rui') like '42501:%' and testes.v('e_curta') = 'P0001:texto_curto' and testes.v('e_futuro') = 'P0001:periodo_invalido',
          'só quem tem analista.usar pergunta; pergunta com texto; relatório só de meses que já começaram');
select ok(testes.v('R1') = testes.v('R1b'), 'um relatório por mês (pedir de novo devolve o mesmo)');

update parametros set analista_perguntas_dia = 2 where unico;
select testes.entrar_funcionario(testes.u('paula'));
set local role authenticated;
select perguntar_analista('Quantos clientes voltaram este mês?');
select testes.def('e_limite', testes.erro($$select perguntar_analista('E na semana passada?')$$));
reset role;
select testes.sair();
select is(testes.v('e_limite'), 'P0001:limite_diario', 'limite de perguntas por dia (controla o custo)');

-- Ferramentas (só o serviço)
select ok((select (l ->> 'pedidos')::int = 3 and (l ->> 'valor_kz')::numeric = 9500
             from jsonb_array_elements(analista_vendas(testes.hoje(), testes.hoje(), 'total') -> 'pedidos_entregues') l)
          and (analista_vendas(testes.hoje(), testes.hoje(), 'total') ->> 'pedidos_cancelados')::int = 1,
          'vendas: 3 entregues (9.500 Kz) e 1 cancelado');
select is((select l ->> 'grupo' from jsonb_array_elements(analista_vendas(testes.hoje(), testes.hoje(), 'zona') -> 'pedidos_entregues') l),
          'Talatona', 'vendas por zona');
select ok((select (l ->> 'quantidade')::numeric = 2 from jsonb_array_elements(analista_pratos(testes.hoje(), testes.hoje()) -> 'mais_vendidos') l
            where l ->> 'prato' = 'Muamba'), 'pratos mais vendidos');
select ok((analista_clientes(testes.hoje(), testes.hoje()) ->> 'clientes_que_compraram')::int = 2
          and (analista_clientes(testes.hoje(), testes.hoje()) ->> 'clientes_com_2_ou_mais_pedidos')::int = 1
          and analista_clientes(testes.hoje(), testes.hoje()) -> 'por_tipo_de_local' ->> 'empresa' = '3',
          'clientes: quem comprou, quem repetiu, tipo de local');
select ok((select (l ->> 'cancelados')::int = 1 from jsonb_array_elements(analista_operacao(testes.hoje(), testes.hoje()) -> 'por_cozinha') l)
          and analista_operacao(testes.hoje(), testes.hoje()) -> 'motivos_de_cancelamento' -> 0 ->> 'motivo' = 'Sem gás',
          'operação: cancelados e motivos');
select ok((analista_satisfacao(testes.hoje(), testes.hoje()) ->> 'avaliacoes')::int = 1
          and (analista_satisfacao(testes.hoje(), testes.hoje()) ->> 'reclamacoes')::int = 1
          and analista_satisfacao(testes.hoje(), testes.hoje()) -> 'comentarios_negativos_recentes' -> 0 ->> 'comentario' = 'Veio frio',
          'satisfação: avaliações, reclamações e comentários negativos');
select ok((analista_financas(testes.hoje(), testes.hoje()) ->> 'receita_entregue_kz')::numeric = 9500
          and (analista_financas(testes.hoje(), testes.hoje()) -> 'recebido_por_metodo_kz' ->> 'Dinheiro')::numeric = 9500,
          'finanças: receita e recebido por método');
select ok(analista_clientes(testes.hoje(), testes.hoje())::text not like '%Ana%'
          and analista_satisfacao(testes.hoje(), testes.hoje())::text not like '%Ana%'
          and analista_vendas(testes.hoje(), testes.hoje(), 'dia')::text not like '%Bia%',
          'as ferramentas não levam nomes de clientes');
select is(metricas_funcionario(testes.u('rui'), date_trunc('month', testes.hoje())::date),
          metricas_funcionario_periodo(testes.u('rui'), date_trunc('month', testes.hoje())::date,
                                       (date_trunc('month', testes.hoje()) + interval '1 month - 1 day')::date),
          'os estímulos mensais usam a mesma conta da equipa');
select ok(not has_function_privilege('authenticated', 'analista_vendas(date, date, text)', 'execute')
          and not has_function_privilege('authenticated', 'reservar_pergunta(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'registar_resposta_analista(uuid, text, jsonb, jsonb, text)', 'execute'),
          'as ferramentas do analista só o serviço as chama');

-- Resposta
select testes.def('reserva', reservar_pergunta(testes.u('Q1')));
select ok(testes.v('reserva')::jsonb ->> 'pergunta' like 'Que prato vende mais%' and testes.v('reserva')::jsonb ? 'hoje',
          'reserva a pergunta pedida, com a data de hoje');
select ok(reservar_pergunta(testes.u('Q1')) is null, 'uma pergunta a ser respondida não é reservada duas vezes');
select is(registar_resposta_analista(testes.u('Q1'), 'respondida',
            '{"resposta": "A Muamba é o prato mais vendido (2).", "numeros_chave": [{"rotulo": "Muamba", "valor": "2"}],
              "sugestoes": ["Ver porque veio frio"], "limitacoes": "Só um dia de dados."}'::jsonb,
            '[{"ferramenta": "vendas_dos_pratos"}]'::jsonb), 'respondida', 'regista a resposta');
select registar_resposta_analista(testes.u('R1'), 'respondida', '{"resposta": "Mês com 3 pedidos entregues.", "numeros_chave": [], "sugestoes": []}'::jsonb);
select is((select array_agg(funcionario_id order by funcionario_id) from notificacoes_fila where codigo = 'N25'),
          (select array_agg(x order by x) from unnest(array[testes.u('paula'), testes.u('tito')]) x),
          'relatório pronto: N25 a quem usa o analista');

-- Quem vê: cada um as suas perguntas; os relatórios todos
select testes.entrar_funcionario(testes.u('tito'));
set local role authenticated;
select testes.def('vistos_tito', (select string_agg(tipo, ',' order by tipo) from perguntas_analista));
select testes.def('lista_tito', jsonb_array_length(perguntas_analista_lista()));
reset role;
select testes.entrar_funcionario(testes.u('paula'));
set local role authenticated;
select testes.def('lista_paula', (select jsonb_agg(e ->> 'estado' order by e ->> 'pergunta') from jsonb_array_elements(perguntas_analista_lista()) e));
reset role;
select testes.sair();
select ok(testes.v('vistos_tito') = 'relatorio_mensal' and testes.v('lista_tito') = '1',
          'o Tito vê o relatório do mês mas não as perguntas da Paula');
select ok(testes.v('lista_paula')::jsonb @> '["respondida"]' and jsonb_array_length(testes.v('lista_paula')::jsonb) = 3,
          'a Paula vê as suas perguntas e o relatório');

select testes.funcionalidade('agente_analista', false);
select ok(job_relatorio_analista() is null and reservar_pergunta() is null, 'com o interruptor desligado o analista não trabalha');

select * from finish();
rollback;
