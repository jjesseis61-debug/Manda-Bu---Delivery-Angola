-- Simulação de um mês de operação (32 dias, domingos fechados) no Supabase. Corre numa transacção e
-- termina com uma excepção que devolve o relatório e desfaz tudo: nenhum dado fica guardado.
create temp table tap_saida (n serial, linha text);
grant all on tap_saida to public;
grant all on sequence tap_saida_n_seq to public;
create temp table sim (chave text primary key, valor text);
grant all on sim to public;
create temp table difs (caixa uuid, dif numeric);
grant all on difs to public;
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
  inicio date := current_date - 31;
  n_cli int := 30;
  uids uuid[] := '{}'; clis uuid[] := '{}'; pontos uuid[] := '{}'; zonas uuid[] := '{}';
  g_a uuid; e_a uuid; g_k uuid; e_k uuid; ger uuid; est uuid;
  u uuid; c uuid; p uuid; i int; d int; dia date; cod text; ind int; dias_trab int := 0;
  cx_a uuid; cx_k uuid; cx uuid; ad uuid; cz uuid; itens jsonb; pid uuid; r float8; apagar int; parc jsonb;
  ped record; res jsonb; dia_pedidos uuid[]; lev uuid; dif numeric; ultimo boolean; renovacoes int := 0;
  levantamentos int := 0; pagos int := 0; rec int := 0;
begin
  perform setseed(0.77);
  g_a := testes.funcionario('Gerente Alexandra', array['pedidos.gerir','vendas.registar','pacotes.gerir','relatorios.exportar',
                                                       'equipa.reconhecer','indicacoes.ver','indicacoes.aprovar_pagamentos']);
  e_a := testes.funcionario('Estafeta Alexandra', array['entregas.registar']);
  g_k := testes.funcionario('Gerente Kilamba', array['pedidos.gerir','vendas.registar']);
  e_k := testes.funcionario('Estafeta Kilamba', array['entregas.registar']);

  for i in 1..n_cli loop
    insert into auth.users (id, phone) values (gen_random_uuid(), '2449236' || lpad(i::text, 5, '0')) returning id into u;
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    c := registar_cliente(case when i = n_cli then 'Pedro Pacote' when i = 1 then 'Maria Indica' else 'Cliente ' || i end, 'Particular', null);
    insert into pontos_entrega (tipo, lat, lng, zona_id, referencia, dispositivo_id)
    values ('residencial', -8.90 - i * 0.004, (case when i <= 18 then 13.37 else 13.20 end) + i * 0.004,
            case when i <= 18 then viana else kil end, 'Casa ' || i, 'sim')
    returning id into p;
    insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome, principal) values (c, p, 'Casa', true);
    execute 'reset role';
    uids := uids || u; clis := clis || c; pontos := pontos || p; zonas := zonas || (case when i <= 18 then viana else kil end);
  end loop;

  -- 18 amigos: 8 da Maria (1), 4 do 2, 3 do 3, 3 do 4
  for i in 5..22 loop
    ind := case when i <= 12 then 1 when i <= 16 then 2 when i <= 19 then 3 else 4 end;
    cod := testes.codigo(clis[ind]);
    perform set_config('request.jwt.claims', json_build_object('sub', uids[i], 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    insert into sim values ('liga' || i, ligar_indicacao(cod));
    execute 'reset role';
  end loop;

  for d in 0..31 loop
    dia := inicio + d;
    continue when extract(isodow from dia) = 7;   -- domingo: fechado
    dias_trab := dias_trab + 1;
    ultimo := (d = 31);
    insert into turnos (data, funcionario_id, cozinha_id, periodo, hora_inicio, hora_fim) values
      (dia, g_a, cz_a, 'manha', '08:00', '16:00'), (dia, e_a, cz_a, 'manha', '08:00', '16:00'),
      (dia, g_k, cz_k, 'manha', '08:00', '16:00'), (dia, e_k, cz_k, 'manha', '08:00', '16:00');

    perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
    cx_a := abrir_caixa(cz_a, 'Posto Mes', 5000);
    execute 'reset role';
    perform testes.entrar_funcionario(g_k); perform set_config('role', 'authenticated', true);
    cx_k := abrir_caixa(cz_k, 'Posto Mes', 3000);
    execute 'reset role';

    -- o Pedro compra o pacote no primeiro dia e renova quando as refeições acabam
    if d = 0 then
      perform set_config('request.jwt.claims', json_build_object('sub', uids[n_cli], 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
      ad := aderir_pacote(pacote, 'loja');
      execute 'reset role';
      perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
      perform confirmar_pagamento_pacote(ad, null, cx_a);
      execute 'reset role';
    end if;

    dia_pedidos := '{}';
    for i in 1..n_cli loop
      r := random();
      continue when not (i = n_cli or (i between 5 and 22 and r < 0.6) or r < 0.4);
      cz := case when zonas[i] = kil and i <> n_cli and random() < 0.5 then cz_k else cz_a end;
      if cz = cz_k then
        itens := jsonb_build_array(jsonb_build_object('cardapio_id', cach_k, 'qtd', 1 + floor(random() * 2)::int));
      elsif i = n_cli then
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
      values (pid, clis[i], pontos[i], cz, itens, 'sim-m' || lpad(d::text, 2, '0') || '-c' || lpad(i::text, 2, '0'));
      if i = n_cli then
        begin
          perform usar_pacote(pid);
        exception when others then
          -- refeições acabaram: renova o pacote (paga na loja amanhã de manhã, hoje paga o almoço)
          insert into sim values ('pacote_esgotado_dia' || d, sqlerrm) on conflict do nothing;
          begin
            ad := aderir_pacote(pacote, 'loja');
            renovacoes := renovacoes + 1;
          exception when others then insert into sim values ('renovar_falhou_dia' || d, sqlerrm) on conflict do nothing;
          end;
        end;
      end if;
      execute 'reset role';
      dia_pedidos := dia_pedidos || pid;
    end loop;

    foreach pid in array dia_pedidos loop
      select x.*, cl.auth_user_id as uid into ped from pedidos x join clientes cl on cl.id = x.cliente_id where x.id = pid;
      ger := case when ped.cozinha_id = cz_a then g_a else g_k end;
      est := case when ped.cozinha_id = cz_a then e_a else e_k end;
      cx := case when ped.cozinha_id = cz_a then cx_a else cx_k end;
      r := random();
      if r < 0.06 and ped.pago_pacote = 0 then
        perform set_config('request.jwt.claims', json_build_object('sub', ped.uid, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        perform cancelar_pedido(pid, 'Mudei de ideias');
        execute 'reset role';
      elsif r < 0.09 and ped.pago_pacote = 0 then
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
                     when random() < 0.65 then jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', apagar))
                     when random() < 0.7 then jsonb_build_array(jsonb_build_object('metodo', 'Multicaixa Express', 'valor', apagar))
                     else jsonb_build_array(jsonb_build_object('metodo', 'Unitel Money', 'valor', apagar)) end;
        perform mudar_estado_pedido(pid, 'entregue_pago', null, cx, parc);
        execute 'reset role';
        if random() < 0.35 then
          perform set_config('request.jwt.claims', json_build_object('sub', ped.uid, 'role', 'authenticated')::text, true);
          perform set_config('role', 'authenticated', true);
          insert into avaliacoes (pedido_id, cliente_id, estrelas, usar_pseudonimo)
          values (pid, ped.cliente_id, 3 + floor(random() * 3)::int, false);
          execute 'reset role';
        end if;
      end if;
    end loop;

    -- pacote renovado: o Pedro paga na loja antes de fechar a caixa
    if exists (select 1 from adesoes_pacote a where a.cliente_id = clis[n_cli] and a.estado = 'pendente') then
      select id into ad from adesoes_pacote a where a.cliente_id = clis[n_cli] and a.estado = 'pendente';
      perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
      perform confirmar_pagamento_pacote(ad, null, cx_a);
      execute 'reset role';
    end if;

    -- fecho das caixas: em ~10% dos fechos o dinheiro contado não bate
    perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
    res := resumo_caixa(cx_a);
    dif := case when random() < 0.1 then (array[-500, -1000, 200])[1 + floor(random() * 3)::int] else 0 end;
    perform fechar_caixa(cx_a, (res ->> 'esperado')::numeric + dif, case when dif <> 0 then 'Contagem não bate' end);
    execute 'reset role';
    insert into difs values (cx_a, dif);
    perform testes.entrar_funcionario(g_k); perform set_config('role', 'authenticated', true);
    res := resumo_caixa(cx_k);
    dif := case when random() < 0.1 then -500 else 0 end;
    perform fechar_caixa(cx_k, (res ->> 'esperado')::numeric + dif, case when dif <> 0 then 'Contagem não bate' end);
    execute 'reset role';
    insert into difs values (cx_k, dif);

    -- sábado: quem tem 2 000 Kz ou mais pede o levantamento e o operador paga
    if extract(isodow from dia) = 6 then
      for ind in 1..4 loop
        if (select coalesce(sum(valor), 0) from ganhos_indicacao where indicador_id = clis[ind] and estado = 'confirmado') >= 2000 then
          perform set_config('request.jwt.claims', json_build_object('sub', uids[ind], 'role', 'authenticated')::text, true);
          perform set_config('role', 'authenticated', true);
          begin
            perform pedir_levantamento(2000, 'unitel_money', '9236' || lpad(ind::text, 5, '0'));
            levantamentos := levantamentos + 1;
          exception when others then insert into sim values ('lev_falhou_' || d || '_' || ind, sqlerrm) on conflict do nothing;
          end;
          execute 'reset role';
          lev := null;
          select id into lev from pagamentos_indicacao where indicador_id = clis[ind] and estado not in ('pago', 'rejeitado', 'anulado', 'cancelado') order by criado_em desc limit 1;
          if lev is not null then
            perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
            begin
              perform aprovar_levantamento(lev);
              perform marcar_pago(lev, 'UM-' || d || '-' || ind);
              pagos := pagos + 1;
            exception when others then insert into sim values ('pago_falhou_' || d || '_' || ind, sqlerrm) on conflict do nothing;
            end;
            execute 'reset role';
          end if;
        end if;
      end loop;
    end if;

    -- segunda-feira: reconhecimento da equipa pela semana anterior
    if extract(isodow from dia) = 1 and d > 0 then
      perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
      insert into reconhecimentos_turno (cozinha_id, semana, periodo, tipo, criado_por)
      values (cz_a, dia - 7, 'manha', case when rec % 2 = 0 then 'entregas_a_horas' else 'caixa_certa' end, g_a);
      execute 'reset role';
      rec := rec + 1;
    end if;

    -- o dia passa: horas reais (prometida 11:00–13:00; entregue entre 25 min antes e 30 min depois)
    if not ultimo then
      update pedidos set hora_prometida = (dia + time '11:00')::timestamp at time zone 'Africa/Luanda' + random() * interval '2 hours'
       where dispositivo_id like 'sim-m' || lpad(d::text, 2, '0') || '-%';
      update pedidos set entregue_em = hora_prometida + (random() * 55 - 25) * interval '1 minute'
       where dispositivo_id like 'sim-m' || lpad(d::text, 2, '0') || '-%' and entregue_em is not null;
      update vendas v set data = x.entregue_em from pedidos x where v.pedido_id = x.id and x.dispositivo_id like 'sim-m' || lpad(d::text, 2, '0') || '-%';
      update caixa set data = dia where id in (cx_a, cx_k);
    else
      update pedidos set entregue_em = now() - interval '2 hours', hora_prometida = now() - interval '2 hours' + interval '10 minutes'
       where dispositivo_id like 'sim-m31-%' and entregue_em is not null;
      update vendas v set data = x.entregue_em from pedidos x where v.pedido_id = x.id and x.dispositivo_id like 'sim-m31-%';
    end if;
  end loop;

  insert into sim values ('dias_trab', dias_trab::text), ('renovacoes', renovacoes::text), ('levantamentos', levantamentos::text),
                         ('pagos', pagos::text), ('reconhecimentos', rec::text),
                         ('estados_levantamento', (select json_object_agg(estado, n)::text from (select estado, count(*) n from pagamentos_indicacao group by 1) z));
  perform job_contadores_zona();
  perform job_n9_avaliacao();
  perform job_n7_destaques();
  perform job_n14_pacotes();
  perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
  insert into sim values ('rel_a', relatorio_cozinha(cz_a, inicio, current_date)::text);
  insert into sim values ('rel_k', relatorio_cozinha(cz_k, inicio, current_date)::text);
  insert into sim values ('comparativo', (select json_agg(t)::text from relatorio_comparativo(inicio, current_date) t));
  insert into sim values ('painel', painel_programa(inicio, current_date)::text);
  insert into sim values ('metricas', (select json_agg(t)::text from metricas_turno(cz_a, current_date - extract(isodow from current_date)::int - 6) t));
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', uids[n_cli], 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  insert into sim values ('pacote_pedro', coalesce((select json_agg(t)::text from meu_pacote() t), 'null'));
  execute 'reset role';
  insert into sim values ('cz_a', cz_a::text), ('cz_k', cz_k::text), ('inicio', inicio::text), ('pedro', clis[n_cli]::text), ('maria', clis[1]::text);
end $sim$;

insert into tap_saida (linha) select is((select count(*)::int from clientes where nome like 'Cliente %' or nome in ('Maria Indica', 'Pedro Pacote')), 30, '30 clientes registados pelo telemóvel');
insert into tap_saida (linha) select is((select count(*)::int from sim where chave like 'liga%' and valor = 'ok'), 18, '18 amigos entram com código');
insert into tap_saida (linha) select ok((select count(*) from pedidos where dispositivo_id like 'sim-m%') >= 300, 'mais de 300 pedidos no mês');
insert into tap_saida (linha) select is((select count(*)::int from pedidos where dispositivo_id like 'sim-m%' and estado not in ('entregue_pago', 'cancelado')), 0, 'nenhum pedido fica a meio');
insert into tap_saida (linha) select is((select count(*)::int from pedidos x where x.dispositivo_id like 'sim-m%' and x.estado = 'entregue_pago'
            and (select coalesce(sum(valor_total), 0) from vendas v where v.pedido_id = x.id) <> x.subtotal + x.taxa_entrega - x.desconto_indicacao), 0,
          'cada entrega gerou vendas com o valor exacto do pedido');
insert into tap_saida (linha) select is((select count(*)::int from caixa where posto = 'Posto Mes' and fechamento is not null), 2 * (select valor from sim where chave = 'dias_trab')::int,
          'duas caixas abertas e fechadas em cada dia de trabalho');
insert into tap_saida (linha) select is((select count(*)::int from caixa c join difs f on f.caixa = c.id where (c.fechamento ->> 'diferenca')::numeric <> f.dif), 0,
          'cada fecho guarda exactamente a diferença contada');
insert into tap_saida (linha) select is((select count(*)::int from caixa c where c.posto = 'Posto Mes'
            and (c.fechamento ->> 'esperado')::numeric <> c.troco_inicial
                 + coalesce((select sum((p ->> 'valor')::numeric) from vendas v, jsonb_array_elements(v.parcelas) p where v.caixa_id = c.id and p ->> 'metodo' = 'Dinheiro'), 0)
                 + coalesce((select sum(preco) from adesoes_pacote a where a.caixa_id = c.id and a.metodo = 'loja'), 0)), 0,
          'o esperado de cada caixa bate com o dinheiro do dia (Multicaixa e Unitel Money não entram)');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'renovacoes')::int >= 1
          and exists (select 1 from notificacoes_fila where codigo = 'N14' and cliente_id = (select valor from sim where chave = 'pedro')::uuid)
          and (select count(*) from notificacoes_fila where codigo = 'N13' and cliente_id = (select valor from sim where chave = 'pedro')::uuid) >= 2,
          'o Pedro gasta as 22 refeições, é avisado (N14), renova e o novo pacote é activado (N13)');
insert into tap_saida (linha) select is((select sum(refeicoes_usadas)::int from adesoes_pacote where cliente_id = (select valor from sim where chave = 'pedro')::uuid),
          (select count(*)::int from pedidos where cliente_id = (select valor from sim where chave = 'pedro')::uuid and pago_pacote > 0 and estado = 'entregue_pago'),
          'cada almoço pago com o pacote gastou exactamente uma refeição');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'pagos')::int >= 2
          and (select count(*) from notificacoes_fila where codigo = 'N8') = (select valor from sim where chave = 'pagos')::int,
          'levantamentos de sábado aprovados e pagos, cada um com aviso N8');
insert into tap_saida (linha) select is((select jsonb_array_length((valor::jsonb) -> 'pedidos_por_dia') from sim where chave = 'rel_a'), (select valor from sim where chave = 'dias_trab')::int,
          'o relatório do mês mostra todos os dias de trabalho');
insert into tap_saida (linha) select ok(((select valor from sim where chave = 'rel_a')::jsonb -> 'retencao' ->> '30') is not null, 'retenção a 30 dias calculada para os clientes da primeira semana');
insert into tap_saida (linha) select ok((select (t ->> 'pct_a_horas') is not null from json_array_elements((select valor from sim where chave = 'metricas')::json) t limit 1), 'percentagem de entregas a horas medida (hora prometida em cada pedido)');
insert into tap_saida (linha) select is((select count(*)::int from notificacoes_fila where codigo = 'N12'), 2 * (select valor from sim where chave = 'reconhecimentos')::int,
          'reconhecimento semanal chega ao gerente e ao estafeta (N12)');
-- Nota: o servidor não deixa recuar criado_em, por isso os ganhos do mês contam todos como "esta semana";
-- só a Maria (8 amigos) passa o limite semanal de verificação, e é avisada (N4).
insert into tap_saida (linha) select ok((select count(*) from ganhos_indicacao where estado = 'em_verificacao' and indicador_id <> (select valor from sim where chave = 'maria')::uuid) = 0
          and exists (select 1 from notificacoes_fila where codigo = 'N4' and cliente_id = (select valor from sim where chave = 'maria')::uuid),
          'só quem passa o limite semanal fica com ganhos em verificação, e é avisado (N4)');

insert into sim values ('resumo', (select json_build_object(
  'pedidos', count(*), 'entregues', count(*) filter (where estado = 'entregue_pago'),
  'cancelados', count(*) filter (where estado = 'cancelado'),
  'por_semana', (select json_object_agg(s, n) from (select to_char(date_trunc('week', coalesce(entregue_em, criado_em) at time zone 'Africa/Luanda'), 'DD/MM') s, count(*) n
                   from pedidos where dispositivo_id like 'sim-m%' group by 1 order by 1) z),
  'faturacao', (select json_object_agg(c.nome, s) from (select v.cozinha_id, sum(v.valor_total) s from vendas v join pedidos x on x.id = v.pedido_id where x.dispositivo_id like 'sim-m%' group by 1) z join cozinhas c on c.id = z.cozinha_id),
  'por_metodo', (select json_object_agg(m, s) from (select p ->> 'metodo' m, sum((p ->> 'valor')::numeric) s from vendas v join pedidos x on x.id = v.pedido_id, jsonb_array_elements(v.parcelas) p where x.dispositivo_id like 'sim-m%' group by 1) z),
  'diferencas_caixa', (select json_build_object('fechos_com_diferenca', count(*) filter (where dif <> 0), 'total', sum(dif)) from difs),
  'descontos_indicacao', sum(desconto_indicacao) filter (where estado = 'entregue_pago'),
  'ganhos', (select json_object_agg(estado, s) from (select estado, sum(valor) s from ganhos_indicacao group by 1) z),
  'avaliacoes', (select json_build_object('n', count(*), 'media', round(avg(estrelas), 2)) from avaliacoes a join pedidos x on x.id = a.pedido_id where x.dispositivo_id like 'sim-m%'),
  'avisos', (select json_object_agg(codigo, n) from (select codigo, count(*) n from notificacoes_fila group by 1 order by 1) z)
)::text from pedidos where dispositivo_id like 'sim-m%'));
insert into tap_saida (linha) select * from finish();
do $fim$ begin raise exception 'TAP %', E'\n' || (select string_agg(linha, E'\n' order by n) from tap_saida)
  || E'\n--- dados ---\n' || (select string_agg(chave || ': ' || left(valor, 900), E'\n' order by chave) from sim
                              where chave not like 'liga%' and chave not in ('cz_a', 'cz_k', 'pedro', 'maria')); end $fim$;
