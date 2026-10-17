-- Vigilante do Convida e Ganha: sinais e casos, histórico de telemóveis, ferramentas só do serviço e sem
-- nomes nem telefones, dossiê com N26 e decisão de quem verifica
begin;
\ir _helpers.psql
select plan(17);

select testes.funcionalidade('agente_vigilante', true);
select testes.def('vera', testes.funcionario('Vera Verificação', array['indicacoes.verificar']));
select testes.def('rui', testes.funcionario('Rui Mateus', array['entregas.registar']));
select testes.def('carla', testes.cliente('Carla Indicadora', 'Particular', '+244923000001'));
select testes.def('duarte', testes.cliente('Duarte Normal', 'Particular', '+244923000002'));
select testes.def('casa', testes.ponto('residencial', -8.90, 13.20));
select testes.def('longe', testes.ponto('residencial', -8.70, 13.40));
insert into enderecos_cliente (cliente_id, ponto_entrega_id) values (testes.u('carla'), testes.u('casa'));

-- Indicados da Carla: i1..i4 ligados há 20 dias no mesmo dia; i1..i3 pedem na casa da Carla e só uma vez;
-- i4 pede duas vezes noutro sítio mas usa o telemóvel da Carla; a Carla levanta para o número do i2
create function pg_temp.indicado(p_nome text, p_tel text, p_indicador text, p_dias int) returns uuid language plpgsql as $$
declare v uuid := testes.cliente(p_nome, 'Particular', p_tel);
begin
  insert into ligacoes_indicacao (indicado_id, indicador_id, ligado_em, ganho_por_pedido_garantido, desconto_garantido, duracao_dias_garantida)
  values (v, testes.u(p_indicador), now() - make_interval(days => p_dias), 100, 500, 30);
  return v;
end $$;
create function pg_temp.entregue(p_cliente uuid, p_ponto text) returns uuid language plpgsql as $$
declare p uuid := testes.pedido(p_cliente, testes.u(p_ponto));
begin
  perform testes.pagar(p);
  update ligacoes_indicacao set primeiro_pedido_id = coalesce(primeiro_pedido_id, p) where indicado_id = p_cliente;
  return p;
end $$;
select testes.def('i1', pg_temp.indicado('Indicado Um', '+244923100001', 'carla', 20));
select testes.def('i2', pg_temp.indicado('Indicado Dois', '+244923100002', 'carla', 20));
select testes.def('i3', pg_temp.indicado('Indicado Três', '+244923100003', 'carla', 20));
select testes.def('i4', pg_temp.indicado('Indicado Quatro', '+244923100004', 'carla', 20));
select testes.def('d1', pg_temp.indicado('Amigo do Duarte', '+244923200001', 'duarte', 20));
select pg_temp.entregue(testes.u('i1'), 'casa');
select pg_temp.entregue(testes.u('i2'), 'casa');
select pg_temp.entregue(testes.u('i3'), 'casa');
select pg_temp.entregue(testes.u('i4'), 'longe');
select pg_temp.entregue(testes.u('i4'), 'longe');
select pg_temp.entregue(testes.u('d1'), 'longe');
select pg_temp.entregue(testes.u('d1'), 'longe');
-- o mesmo telemóvel: primeiro na conta da Carla, depois na do i4 (o token passa de conta)
select testes.entrar(testes.u('carla'));
set local role authenticated;
select registar_token_push('ExponentPushToken[telemovel-da-carla]', 'android');
reset role;
select testes.entrar(testes.u('i4'));
set local role authenticated;
select registar_token_push('ExponentPushToken[telemovel-da-carla]', 'android');
reset role;
select testes.sair();
insert into pagamentos_indicacao (indicador_id, valor, tipo, metodo, numero_destino, estado)
values (testes.u('carla'), 2000, 'levantamento', 'unitel_money', '923 100 002', 'pedido');

select is((select count(*)::int from aparelhos_contas where token_hash = md5('ExponentPushToken[telemovel-da-carla]')), 2,
          'o histórico guarda as duas contas que usaram o mesmo telemóvel');
select results_eq(format($$select (s ->> 'indicados')::int, (s ->> 'mesmo_local')::int, (s ->> 'telemovel_partilhado')::int,
                                  (s ->> 'levantamento_para_indicado')::int, (s ->> 'so_um_pedido')::int, (s ->> 'maximo_num_dia')::int,
                                  (s ->> 'pontuacao')::int
                             from sinais_convida(%L, current_date - 30, current_date) s$$, testes.v('carla')),
                  $$values (4, 3, 1, 1, 3, 4, 16)$$,
                  'sinais da Carla: 3 no mesmo local, 1 telemóvel partilhado, 1 levantamento para um indicado, 3 de 4 só com um pedido, 4 no mesmo dia');
select is((sinais_convida(testes.u('duarte'), current_date - 30, current_date) ->> 'pontuacao')::int, 0, 'o Duarte não tem sinais');

-- Abrir: só quem verifica; um caso para a Carla; não repete
select testes.entrar_funcionario(testes.u('rui'));
set local role authenticated;
select testes.def('e_rui', testes.erro('select abrir_vigilancia(current_date - 30, current_date)'));
reset role;
select testes.entrar_funcionario(testes.u('vera'));
set local role authenticated;
select testes.def('abertos', abrir_vigilancia(current_date - 30, current_date));
select testes.def('de_novo', abrir_vigilancia(current_date - 30, current_date));
reset role;
select testes.sair();
select testes.def('caso', (select id from casos_convida where indicador_id = testes.u('carla')));
select ok(testes.v('e_rui') like '42501:%' and testes.v('abertos') = '1' and testes.v('de_novo') = '0'
          and not exists (select 1 from casos_convida where indicador_id = testes.u('duarte')),
          'só quem verifica abre casos; só a Carla tem caso; o mesmo período não repete');

-- Ferramentas
select testes.def('reserva', reservar_caso_convida());
select ok((testes.v('reserva')::jsonb -> 'sinais' ->> 'pontuacao')::int = 16 and reservar_caso_convida() is null,
          'reserva o caso uma vez, com os sinais');
select is(jsonb_array_length(vig_indicados(testes.u('carla'), current_date - 30, current_date)), 4, 'lista os indicados do período');
select ok((select bool_and((e ->> 'mesmo_local_que_o_indicador')::boolean) from jsonb_array_elements(vig_indicados(testes.u('carla'), current_date - 30, current_date)) e
            where (e ->> 'pedidos_entregues')::int = 1)
          and (select (e ->> 'telemovel_partilhado')::boolean from jsonb_array_elements(vig_indicados(testes.u('carla'), current_date - 30, current_date)) e
                where e ->> 'indicado_id' = testes.v('i4')),
          'cada indicado: mesmo local que a indicadora e telemóvel partilhado');
select ok((select (e ->> 'e_o_numero_de_um_indicado')::boolean and e ->> 'numero_final' = '002'
             from jsonb_array_elements(vig_levantamentos(testes.u('carla'))) e),
          'o levantamento vai para o número de um indicado (só os 3 últimos dígitos)');
select is(jsonb_array_length(vig_pedidos_indicado(testes.u('i4'))), 2, 'pedidos de um indicado');
select ok(vig_rede(testes.u('carla')) ->> 'ciclo' = 'false', 'rede de indicações (sem ciclo)');
select ok((vig_comparar(current_date - 30, current_date) ->> 'maximo_de_indicados')::int = 4, 'compara com os outros indicadores');
select ok(vig_indicados(testes.u('carla'), current_date - 30, current_date)::text !~ '(Indicado|Carla|92310000|92300000)'
          and vig_levantamentos(testes.u('carla'))::text !~ '(Indicado|Carla|92310000|92300000)',
          'sem nomes nem telefones para o agente');
select ok(not has_function_privilege('authenticated', 'vig_indicados(uuid, date, date)', 'execute')
          and not has_function_privilege('authenticated', 'reservar_caso_convida()', 'execute')
          and not has_function_privilege('authenticated', 'registar_vigilancia(uuid, text, jsonb, jsonb, text)', 'execute'),
          'as ferramentas do vigilante só o serviço as chama');

-- Dossiê e decisão
select is(registar_vigilancia(testes.u('caso'), 'investigado',
            '{"risco": "alto", "resumo": "Indicados na casa da indicadora, telemóvel partilhado e levantamento para um indicado.",
              "factos": [{"texto": "3 de 4 indicados só fizeram o pedido do desconto", "pedido_id": null}],
              "explicacoes_possiveis": ["família na mesma casa"], "recomendacao": "Suspender os ganhos em verificação",
              "perguntas_ao_funcionario": []}'::jsonb, '[{"ferramenta": "indicados"}]'::jsonb), 'investigado', 'regista o dossiê');
select is((select (texto_notificacao(codigo, dados)).corpo from notificacoes_fila where codigo = 'N26' and funcionario_id = testes.u('vera')),
          format('Convida e Ganha: o código %s tem sinais a confirmar. Abre a Vigilância para ver os factos e decidir.',
                 (select codigo from codigos_indicacao where cliente_id = testes.u('carla'))),
          'N26 a quem verifica, com o código (não o nome) e sem rótulos');
select testes.entrar_funcionario(testes.u('vera'));
set local role authenticated;
select testes.def('lista', casos_convida_lista());
select decidir_caso_convida(testes.u('caso'), 'suspeita_confirmada', 'Família a criar contas para o desconto. Ganhos anulados.');
select testes.def('e_duas', testes.erro(format($$select decidir_caso_convida(%L, 'sem_problema', 'Outra decisão')$$, testes.v('caso'))));
reset role;
select testes.sair();
select ok(testes.v('lista')::jsonb -> 0 ->> 'indicador' = 'Carla Indicadora' and testes.v('e_duas') = 'P0001:caso_decidido'
          and (select decisao from casos_convida where id = testes.u('caso')) = 'suspeita_confirmada',
          'quem verifica vê o caso (com o nome, na app), decide uma vez');

select testes.funcionalidade('agente_vigilante', false);
select ok(job_vigilancia() = 0 and reservar_caso_convida() is null, 'com o interruptor desligado o vigilante não trabalha');

select * from finish();
rollback;
