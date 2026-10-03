create temp table tap_saida (n serial, linha text);
grant all on tap_saida to public;
grant all on sequence tap_saida_n_seq to public;
create temp table sim (chave text primary key, valor text);
grant all on sim to public;
insert into tap_saida (linha) select plan(16);
select testes.funcionalidade(chave, true) from funcionalidades;

do $sim$
declare
  cz_a uuid := cozinha_padrao();
  cz_k uuid := '7e2e268c-a92a-403d-94a1-bc35b01aa5bf';
  viana uuid := '2fb1dc94-0625-4e8c-ad95-f89424d0118f';
  kil uuid := '949cf89e-6060-43ad-9273-a22902567c29';
  chocos uuid := '9fafb454-268d-4d4e-bda8-7141f753a881';
  monta uuid := '6a485c33-40dc-42bc-82e7-810afd5642bb';
  cach_a uuid := 'e01ce0a3-f831-4a22-822d-153d82a44be8';
  arroz uuid := '15df1fa4-4394-4488-867c-0d83cb236c69';
  cach_k uuid := '13a67651-dcf4-40a8-bb49-b57a1e999e4b';
  pacote uuid := 'd634bfc1-ea91-4b0a-9b11-37b249e1cde7';
  seg date := current_date - 5;
  nomes text[] := array['Maria Indica','Ana Paula','Carlos Neto','Rosa Lemos','João Mateus','Lúcia Gomes','Pedro Sousa',
    'Isabel Costa','Miguel Dias','Teresa Lima','Paulo André','Sónia Faria','Jorge Pinto','Helena Cruz','Rui Baptista',
    'Marta Silva','Nuno Tavares','Clara Mendes','Hugo Ramos','Inês Cardoso','Filipe Moura','Eva Santos','Tomás Reis','Pedro Pacote'];
  uids uuid[] := '{}'; clis uuid[] := '{}'; pontos uuid[] := '{}'; zonas uuid[] := '{}';
  g_a uuid; e_a uuid; g_k uuid; e_k uuid; ger uuid; est uuid;
  u uuid; c uuid; p uuid; i int; d int; dia date; cod text; ind int;
  cx_a uuid; cx_k uuid; cx uuid; ad uuid; cz uuid; itens jsonb; pid uuid; r float8; apagar int; parc jsonb;
  ped record; res jsonb; dia_pedidos uuid[]; lev uuid;
begin
  perform setseed(0.42);
  g_a := testes.funcionario('Gerente Alexandra', array['pedidos.gerir','vendas.registar','pacotes.gerir','relatorios.exportar',
                                                       'equipa.reconhecer','indicacoes.ver','indicacoes.aprovar_pagamentos']);
  e_a := testes.funcionario('Estafeta Alexandra', array['entregas.registar']);
  g_k := testes.funcionario('Gerente Kilamba', array['pedidos.gerir','vendas.registar']);
  e_k := testes.funcionario('Estafeta Kilamba', array['entregas.registar']);
  for d in 0..5 loop
    insert into turnos (data, funcionario_id, cozinha_id, periodo, hora_inicio, hora_fim) values
      (seg + d, g_a, cz_a, 'manha', '08:00', '16:00'), (seg + d, e_a, cz_a, 'manha', '08:00', '16:00'),
      (seg + d, g_k, cz_k, 'manha', '08:00', '16:00'), (seg + d, e_k, cz_k, 'manha', '08:00', '16:00');
  end loop;

  -- 24 clientes registam-se pelo telemóvel e guardam o endereço
  for i in 1..24 loop
    insert into auth.users (id, phone) values (gen_random_uuid(), '2449235' || lpad(i::text, 5, '0')) returning id into u;
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    c := registar_cliente(nomes[i], 'Particular', null);
    insert into pontos_entrega (tipo, lat, lng, zona_id, referencia, dispositivo_id)
    values ('residencial', -8.90 - i * 0.004, (case when i <= 14 then 13.37 else 13.20 end) + i * 0.004,
            case when i <= 14 then viana else kil end, 'Casa de ' || split_part(nomes[i], ' ', 1), 'sim')
    returning id into p;
    insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome, principal) values (c, p, 'Casa', true);
    execute 'reset role';
    uids := uids || u; clis := clis || c; pontos := pontos || p; zonas := zonas || (case when i <= 14 then viana else kil end);
  end loop;
  insert into sim values ('clientes', array_length(clis, 1)::text);

  -- 16 amigos entram com o código de quem os convidou (8 da Maria)
  for i in 5..20 loop
    ind := case when i <= 12 then 1 when i <= 15 then 2 when i <= 18 then 3 else 4 end;
    cod := testes.codigo(clis[ind]);
    perform set_config('request.jwt.claims', json_build_object('sub', uids[i], 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    insert into sim values ('liga' || i, ligar_indicacao(cod));
    execute 'reset role';
  end loop;

  for d in 0..5 loop
    dia := seg + d;
    -- 07:30 abrem as caixas
    perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
    cx_a := abrir_caixa(cz_a, 'Posto Semana', 5000);
    execute 'reset role';
    perform testes.entrar_funcionario(g_k); perform set_config('role', 'authenticated', true);
    cx_k := abrir_caixa(cz_k, 'Posto Semana', 3000);
    execute 'reset role';
    if d = 0 then
      -- o Pedro compra o pacote do mês na loja
      perform set_config('request.jwt.claims', json_build_object('sub', uids[24], 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      ad := aderir_pacote(pacote, 'loja');
      execute 'reset role';
      perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
      perform confirmar_pagamento_pacote(ad, null, cx_a);
      execute 'reset role';
    end if;

    -- 10:00–12:00 os pedidos chegam
    dia_pedidos := '{}';
    for i in 1..24 loop
      r := random();
      continue when not (i = 24 or (i between 5 and 20 and r < 0.75) or r < 0.5);
      cz := case when zonas[i] = kil and i <> 24 and random() < 0.5 then cz_k else cz_a end;
      if cz = cz_k then
        itens := jsonb_build_array(jsonb_build_object('cardapio_id', cach_k, 'qtd', 1 + floor(random() * 2)::int));
      elsif i = 24 then
        itens := jsonb_build_array(jsonb_build_object('cardapio_id', cach_a, 'qtd', 1));
      else
        r := random();
        itens := case
          when r < 0.30 then jsonb_build_array(jsonb_build_object('cardapio_id', chocos, 'qtd', 1))
          when r < 0.55 then jsonb_build_array(jsonb_build_object('cardapio_id', cach_a, 'qtd', 1))
          when r < 0.80 then jsonb_build_array(jsonb_build_object('cardapio_id', monta, 'qtd', 1, 'opcoes',
                               jsonb_build_array('1a064f58-8b0d-436d-8fe0-f5a9b0a87e37', 'd1af71b8-47ae-4f16-8105-4ecd3a33cb28',
                                                 '98a76b0c-12a1-49fa-ac53-29590a49ae80')))
          else jsonb_build_array(jsonb_build_object('cardapio_id', arroz, 'qtd', 2), jsonb_build_object('cardapio_id', chocos, 'qtd', 1)) end;
      end if;
      pid := gen_random_uuid();
      perform set_config('request.jwt.claims', json_build_object('sub', uids[i], 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      insert into pedidos (id, cliente_id, ponto_entrega_id, cozinha_id, itens, dispositivo_id)
      values (pid, clis[i], pontos[i], cz, itens, 'sim-d' || d || '-c' || lpad(i::text, 2, '0'));
      if i = 24 then perform usar_pacote(pid); end if;
      execute 'reset role';
      dia_pedidos := dia_pedidos || pid;
    end loop;

    -- a cozinha trabalha a fila
    foreach pid in array dia_pedidos loop
      select x.*, cl.auth_user_id as uid into ped from pedidos x join clientes cl on cl.id = x.cliente_id where x.id = pid;
      ger := case when ped.cozinha_id = cz_a then g_a else g_k end;
      est := case when ped.cozinha_id = cz_a then e_a else e_k end;
      cx := case when ped.cozinha_id = cz_a then cx_a else cx_k end;
      r := random();
      if r < 0.07 and ped.pago_pacote = 0 then
        perform set_config('request.jwt.claims', json_build_object('sub', ped.uid, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        perform cancelar_pedido(pid, 'Mudei de ideias');
        execute 'reset role';
      elsif r < 0.11 and ped.pago_pacote = 0 then
        perform testes.entrar_funcionario(ger); perform set_config('role', 'authenticated', true);
        perform mudar_estado_pedido(pid, 'cancelado', 'Acabou o prato', null, null);
        execute 'reset role';
      else
        perform testes.entrar_funcionario(ger); perform set_config('role', 'authenticated', true);
        perform mudar_estado_pedido(pid, 'confirmado', null, null, null);
        perform mudar_estado_pedido(pid, 'em_preparacao', null, null, null);
        execute 'reset role';
        perform testes.entrar_funcionario(est); perform set_config('role', 'authenticated', true);
        perform mudar_estado_pedido(pid, 'em_entrega', null, null, null);
        apagar := ped.subtotal + ped.taxa_entrega - ped.desconto_indicacao - ped.credito_indicacao_usado - ped.pago_pacote;
        parc := case when apagar <= 0 then '[]'::jsonb
                     when random() < 0.7 then jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', apagar))
                     else jsonb_build_array(jsonb_build_object('metodo', 'Multicaixa Express', 'valor', apagar)) end;
        -- pagamento electrónico: o estafeta escreve a referência e fotografa o comprovativo
        if parc <> '[]'::jsonb and parc -> 0 ->> 'metodo' <> 'Dinheiro' then
          insert into storage.objects (bucket_id, name) values ('comprovativos', pid || '/talao.jpg');
          parc := jsonb_build_array((parc -> 0) || jsonb_build_object('referencia', 'SIM-' || pid, 'comprovativo', pid || '/talao.jpg'));
        end if;
        perform mudar_estado_pedido(pid, 'entregue_pago', null, cx, parc);
        execute 'reset role';
        if random() < 0.45 then
          perform set_config('request.jwt.claims', json_build_object('sub', ped.uid, 'role', 'authenticated')::text, true);
          perform set_config('role', 'authenticated', true);
          insert into avaliacoes (pedido_id, cliente_id, estrelas, comentario, usar_pseudonimo)
          values (pid, ped.cliente_id, 3 + floor(random() * 3)::int, case when random() < 0.3 then 'Chegou quente e a horas' end, false);
          execute 'reset role';
        end if;
      end if;
    end loop;

    -- 18:00 fecham as caixas (na quarta faltam 500 Kz na Alexandra)
    perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
    res := resumo_caixa(cx_a);
    -- o gerente confere os pagamentos electrónicos com o extracto antes de fechar
    perform conferir_comprovativo(k.id, true) from comprovativos_pagamento k where k.caixa_id = cx_a and k.estado = 'por_conferir';
    perform fechar_caixa(cx_a, (res ->> 'esperado')::numeric - case when d = 2 then 500 else 0 end,
                         case when d = 2 then 'Faltaram 500 Kz' end);
    execute 'reset role';
    perform testes.entrar_funcionario(g_k); perform set_config('role', 'authenticated', true);
    res := resumo_caixa(cx_k);
    -- o gerente confere os pagamentos electrónicos com o extracto antes de fechar
    perform conferir_comprovativo(k.id, true) from comprovativos_pagamento k where k.caixa_id = cx_k and k.estado = 'por_conferir';
    perform fechar_caixa(cx_k, (res ->> 'esperado')::numeric, null);
    execute 'reset role';

    -- o dia passa: datas reais de segunda a sexta (sábado é hoje)
    if d < 5 then
      update pedidos set entregue_em = (dia + time '11:00')::timestamp at time zone 'Africa/Luanda' + random() * interval '2 hours'
       where dispositivo_id like 'sim-d' || d || '-%' and entregue_em is not null;
      update vendas v set data = x.entregue_em from pedidos x where v.pedido_id = x.id and x.dispositivo_id like 'sim-d' || d || '-%';
      update caixa set data = dia where id in (cx_a, cx_k);
    else
      update pedidos set entregue_em = now() - interval '2 hours' where dispositivo_id like 'sim-d5-%' and entregue_em is not null;
      update vendas v set data = x.entregue_em from pedidos x where v.pedido_id = x.id and x.dispositivo_id like 'sim-d5-%';
    end if;
  end loop;

  -- Fim da semana: a Maria levanta o que ganhou com os amigos
  insert into sim values ('saldo_maria', (select coalesce(sum(valor), 0)::text from ganhos_indicacao where indicador_id = clis[1] and estado = 'confirmado'));
  perform set_config('request.jwt.claims', json_build_object('sub', uids[1], 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform pedir_levantamento(2000, 'multicaixa_express', '923500001');
    insert into sim values ('lev', 'ok');
  exception when others then insert into sim values ('lev', sqlerrm);
  end;
  insert into sim values ('posicao_maria', coalesce((select json_agg(t)::text from minha_posicao() t), 'null'));
  insert into sim values ('destaques', coalesce((select count(*) from destaques_mes())::text, 'null'));
  insert into sim values ('medias', coalesce(medias_avaliacoes(cz_a)::text, 'null'));
  execute 'reset role';
  select id into lev from pagamentos_indicacao where indicador_id = clis[1] order by criado_em desc limit 1;
  perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
  begin
    perform aprovar_levantamento(lev);
    perform marcar_pago(lev, 'MCX-2026-0001');
    insert into sim values ('pago', 'ok');
  exception when others then insert into sim values ('pago', sqlerrm);
  end;
  -- Relatórios da semana e reconhecimento da equipa
  insert into sim values ('rel_a', relatorio_cozinha(cz_a, seg, seg + 5)::text);
  insert into sim values ('rel_k', relatorio_cozinha(cz_k, seg, seg + 5)::text);
  insert into sim values ('comparativo', (select json_agg(t)::text from relatorio_comparativo(seg, seg + 5) t));
  insert into sim values ('painel', painel_programa(seg, seg + 5)::text);
  insert into sim values ('metricas', (select json_agg(t)::text from metricas_turno(cz_a, seg) t));
  begin
    insert into reconhecimentos_turno (cozinha_id, semana, periodo, tipo, criado_por) values (cz_a, seg, 'manha', 'entregas_a_horas', g_a);
    insert into sim values ('reconhecimento', 'ok');
  exception when others then insert into sim values ('reconhecimento', sqlerrm);
  end;
  execute 'reset role';
  perform job_contadores_zona();
  perform job_n9_avaliacao();
  perform job_n7_destaques();
  perform set_config('request.jwt.claims', json_build_object('sub', uids[2], 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  insert into sim values ('contador_viana', coalesce((select json_agg(t)::text from contador_zona(viana) t), 'null'));
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', uids[24], 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  insert into sim values ('pacote_pedro', coalesce((select json_agg(t)::text from meu_pacote() t), 'null'));
  execute 'reset role';
  insert into sim values ('g_a', g_a::text), ('cz_a', cz_a::text), ('cz_k', cz_k::text), ('seg', seg::text), ('maria', clis[1]::text);
end $sim$;

-- Verificações
insert into tap_saida (linha) select is((select valor from sim where chave = 'clientes'), '24', '24 clientes registados pelo telemóvel, com endereço');
insert into tap_saida (linha) select is((select count(*)::int from sim where chave like 'liga%' and valor = 'ok'), 16, '16 amigos entram com o código de quem os convidou');
insert into tap_saida (linha) select ok((select count(*) from pedidos where dispositivo_id like 'sim-d%') >= 70, 'pedidos ao longo da semana (pelo menos 70)');
insert into tap_saida (linha) select is((select count(*)::int from pedidos where dispositivo_id like 'sim-d%' and estado not in ('entregue_pago', 'cancelado')), 0, 'nenhum pedido fica a meio no fim de cada dia');
insert into tap_saida (linha) select is((select count(*)::int from pedidos x where x.dispositivo_id like 'sim-d%' and x.estado = 'entregue_pago'
            and (select coalesce(sum(valor_total), 0) from vendas v where v.pedido_id = x.id) <> x.subtotal + x.taxa_entrega - x.desconto_indicacao), 0,
          'cada entrega gerou vendas com o valor exacto do pedido');
insert into tap_saida (linha) select is((select count(*)::int from caixa c where c.cozinha_id in ((select valor from sim where chave = 'cz_a')::uuid, (select valor from sim where chave = 'cz_k')::uuid)
            and c.fechamento is not null and c.posto = 'Posto Semana' and c.data between (select valor from sim where chave = 'seg')::date and current_date), 12, '12 caixas abertas e fechadas (6 dias x 2 cozinhas)');
insert into tap_saida (linha) select is((select array_agg((fechamento ->> 'diferenca')::numeric order by data) from caixa where posto = 'Posto Semana' and (fechamento ->> 'diferenca')::numeric <> 0 and data >= (select valor from sim where chave = 'seg')::date), array[-500::numeric], 'só a caixa de quarta tem diferença (-500 Kz)');
insert into tap_saida (linha) select is((select count(*)::int from caixa c where c.posto = 'Posto Semana' and c.fechamento is not null and c.data >= (select valor from sim where chave = 'seg')::date
            and (c.fechamento ->> 'esperado')::numeric <> c.troco_inicial
                 + coalesce((select sum((p ->> 'valor')::numeric) from vendas v, jsonb_array_elements(v.parcelas) p where v.caixa_id = c.id and p ->> 'metodo' = 'Dinheiro'), 0)
                 + coalesce((select sum(preco) from adesoes_pacote a where a.caixa_id = c.id and a.metodo = 'loja'), 0)), 0,
          'o esperado de cada caixa bate com o dinheiro das vendas e do pacote');
insert into tap_saida (linha) select is((select refeicoes_usadas from adesoes_pacote a join clientes cl on cl.id = a.cliente_id where cl.nome = 'Pedro Pacote'),
          (select count(*)::int from pedidos x join clientes cl on cl.id = x.cliente_id where cl.nome = 'Pedro Pacote' and x.estado = 'entregue_pago'),
          'o pacote do Pedro gasta uma refeição por almoço entregue');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'saldo_maria')::int >= 2000 and (select valor from sim where chave = 'lev') = 'ok', 'a Maria junta pelo menos 2 000 Kz e pede o levantamento');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'pago') = 'ok' and exists (select 1 from notificacoes_fila where codigo = 'N8' and cliente_id = (select valor from sim where chave = 'maria')::uuid), 'o operador aprova e paga; a Maria recebe o N8');
insert into tap_saida (linha) select is((select jsonb_array_length((valor::jsonb) -> 'pedidos_por_dia') from sim where chave = 'rel_a'), 6, 'o relatório da semana mostra os 6 dias');
insert into tap_saida (linha) select ok(((select valor from sim where chave = 'medias')::jsonb -> 'cozinha' ->> 'media') is not null, 'com mais de 5 avaliações aparece a média da cozinha');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'metricas') is not null, 'métricas da semana por turno');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'reconhecimento') = 'ok' and exists (select 1 from notificacoes_fila where codigo = 'N12'), 'reconhecimento da equipa com aviso N12');
insert into tap_saida (linha) select ok((select count(*) from notificacoes_por_enviar(5000)) > 0, 'os avisos da semana estão prontos para envio');

insert into sim values ('resumo', (select json_build_object(
  'pedidos', count(*), 'entregues', count(*) filter (where estado = 'entregue_pago'),
  'cancelados_cliente', count(*) filter (where estado = 'cancelado' and motivo_cancelamento = 'Mudei de ideias'),
  'cancelados_cozinha', count(*) filter (where estado = 'cancelado' and motivo_cancelamento = 'Acabou o prato'),
  'por_dia', (select json_object_agg(d, n) from (select split_part(dispositivo_id, '-c', 1) d, count(*) n from pedidos where dispositivo_id like 'sim-d%' group by 1 order by 1) z),
  'faturacao_alexandra', (select sum(valor_total) from vendas where cozinha_id = (select valor from sim where chave = 'cz_a')::uuid and data >= (select valor from sim where chave = 'seg')::date),
  'faturacao_kilamba', (select sum(valor_total) from vendas where cozinha_id = (select valor from sim where chave = 'cz_k')::uuid and data >= (select valor from sim where chave = 'seg')::date),
  'descontos_indicacao', sum(desconto_indicacao) filter (where estado = 'entregue_pago'),
  'ganhos_indicacao', (select json_object_agg(c.nome, s) from (select indicador_id, sum(valor) s from ganhos_indicacao group by 1) g join clientes c on c.id = g.indicador_id),
  'avaliacoes', (select json_build_object('n', count(*), 'media', round(avg(estrelas), 2)) from avaliacoes a join pedidos x on x.id = a.pedido_id where x.dispositivo_id like 'sim-d%'),
  'ganhos_estado', (select json_object_agg(estado, n) from (select estado, count(*) n from ganhos_indicacao group by 1) z),
  'avisos', (select json_object_agg(codigo, n) from (select codigo, count(*) n from notificacoes_fila group by 1 order by 1) z)
)::text from pedidos where dispositivo_id like 'sim-d%'));
insert into tap_saida (linha) select * from finish();
do $fim$ begin raise exception 'TAP %', E'\n' || (select string_agg(linha, E'\n' order by n) from tap_saida)
  || E'\n--- dados ---\n' || (select string_agg(chave || ': ' || left(valor, 700), E'\n' order by chave) from sim
                              where chave not like 'liga%' and chave not in ('g_a', 'cz_a', 'cz_k', 'maria')); end $fim$;
