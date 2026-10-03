-- Simulação de 6 meses de operação (182 dias, domingos fechados) no Supabase, numa só transacção que
-- termina com uma excepção: devolve o relatório e desfaz tudo (nenhum dado fica guardado).
-- Acontecimentos: aumento do preço dos Chocos (dia 60), troca do estafeta da Alexandra (dia 45),
-- novo bairro Talatona (dia 90), Cozinha do Kilamba pausada uma semana (dias 120–126), uma
-- "embaixadora" com 30 amigos, pacote do mês renovado sempre que acaba, levantamentos mensais;
-- os pagamentos electrónicos levam referência e foto do comprovativo, conferidos antes do fecho.
-- Limites conhecidos: o servidor não deixa recuar criado_em, por isso tudo o que conta "esta semana"
-- pela data de criação (limite semanal do Convida e Ganha, médias de avaliação por período, validade
-- dos pacotes e expiração das ligações aos 60 dias) vê o semestre inteiro como "agora".
create temp table tap_saida (n serial, linha text);
grant all on tap_saida to public;
grant all on sequence tap_saida_n_seq to public;
create temp table sim (chave text primary key, valor text);
grant all on sim to public;
create temp table difs (caixa uuid, dif numeric);
grant all on difs to public;
create temp table recusas (dia int, cozinha uuid, motivo text);
grant all on recusas to public;
insert into tap_saida (linha) select plan(17);
select testes.funcionalidade(chave, true) from funcionalidades;

do $sim$
declare
  cz_a uuid := cozinha_padrao();
  cz_k uuid := '7e2e268c-a92a-403d-94a1-bc35b01aa5bf';
  viana uuid := '2fb1dc94-0625-4e8c-ad95-f89424d0118f';
  kil uuid := '949cf89e-6060-43ad-9273-a22902567c29';
  talatona uuid;
  chocos uuid := '9fafb454-268d-4d4e-bda8-7141f753a881';
  monta uuid := '6a485c33-40dc-42bc-82e7-810afd5642bb';
  cach_a uuid := 'e01ce0a3-f831-4a22-822d-153d82a44be8';
  arroz uuid := '15df1fa4-4394-4488-867c-0d83cb236c69';
  cach_k uuid := '13a67651-dcf4-40a8-bb49-b57a1e999e4b';
  pacote uuid := 'd634bfc1-ea91-4b0a-9b11-37b249e1cde7';
  inicio date := current_date - 181;
  n_cli int := 50;
  t0 timestamptz := clock_timestamp(); t1 timestamptz;
  uids uuid[] := '{}'; clis uuid[] := '{}'; pontos uuid[] := '{}'; zonas uuid[] := '{}';
  dir uuid; g_a uuid; e_a uuid; e_a2 uuid; g_k uuid; e_k uuid; ger uuid; est uuid;
  u uuid; c uuid; p uuid; i int; d int; dia date; cod text; ind int; dias_trab int := 0; caixas_abertas int := 0;
  cx_a uuid; cx_k uuid; cx uuid; ad uuid; cz uuid; itens jsonb; pid uuid; r float8; apagar int; parc jsonb;
  ped record; res jsonb; dia_pedidos uuid[]; lev uuid; dif numeric; ultimo boolean; renovacoes int := 0;
  pagos int := 0; kil_aberta boolean;
begin
  perform setseed(0.31);
  dir := testes.funcionario('Direcção', array['cozinhas.gerir','plataforma.parametros','relatorios.exportar','indicacoes.ver']);
  g_a := testes.funcionario('Gerente Alexandra', array['pedidos.gerir','vendas.registar','pacotes.gerir','indicacoes.aprovar_pagamentos']);
  e_a := testes.funcionario('Estafeta Alexandra', array['entregas.registar']);
  e_a2 := testes.funcionario('Novo estafeta Alexandra', array['entregas.registar']);
  g_k := testes.funcionario('Gerente Kilamba', array['pedidos.gerir','vendas.registar']);
  e_k := testes.funcionario('Estafeta Kilamba', array['entregas.registar']);

  -- 50 clientes: 1 Maria (8 amigos: 2–9), 10 Rosa (30 amigos: 11–40), 41–49 sem código, 50 Pedro (pacote)
  for i in 1..n_cli loop
    insert into auth.users (id, phone) values (gen_random_uuid(), '2449237' || lpad(i::text, 5, '0')) returning id into u;
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    c := registar_cliente(case i when 1 then 'Maria Indica' when 10 then 'Rosa Embaixadora' when 50 then 'Pedro Pacote' else 'Cliente ' || i end, 'Particular', null);
    insert into pontos_entrega (tipo, lat, lng, zona_id, referencia, dispositivo_id)
    values ('residencial', -8.90 - i * 0.003, (case when i % 3 = 0 then 13.20 else 13.37 end) + i * 0.003,
            case when i % 3 = 0 then kil else viana end, 'Casa ' || i, 'sim')
    returning id into p;
    insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome, principal) values (c, p, 'Casa', true);
    execute 'reset role';
    uids := uids || u; clis := clis || c; pontos := pontos || p; zonas := zonas || (case when i % 3 = 0 then kil else viana end);
  end loop;
  for i in 2..40 loop
    continue when i = 10;
    ind := case when i <= 9 then 1 else 10 end;
    cod := testes.codigo(clis[ind]);
    perform set_config('request.jwt.claims', json_build_object('sub', uids[i], 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    insert into sim values ('liga' || i, ligar_indicacao(cod));
    execute 'reset role';
  end loop;

  for d in 0..181 loop
    dia := inicio + d;
    continue when extract(isodow from dia) = 7;
    dias_trab := dias_trab + 1;
    ultimo := (d = 181);

    -- acontecimentos do semestre
    if d = 60 then   -- a direcção sobe o preço dos Chocos
      perform testes.entrar_funcionario(dir); perform set_config('role', 'authenticated', true);
      update cardapio set preco = 6500 where id = chocos;
      execute 'reset role';
      insert into sim values ('dia_preco', d::text);
    end if;
    if d = 90 then   -- novo bairro Talatona; 5 clientes mudam-se para lá
      perform testes.entrar_funcionario(dir); perform set_config('role', 'authenticated', true);
      insert into zonas (nome, tipo, taxa, modo_calculo) values ('Talatona', 'Própria', 1500, 'Fixo') returning id into talatona;
      execute 'reset role';
      for i in 41..45 loop
        perform set_config('request.jwt.claims', json_build_object('sub', uids[i], 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        insert into pontos_entrega (tipo, lat, lng, zona_id, referencia, dispositivo_id)
        values ('residencial', -8.92 - i * 0.003, 13.18 + i * 0.003, talatona, 'Talatona ' || i, 'sim') returning id into p;
        insert into enderecos_cliente (cliente_id, ponto_entrega_id, nome, principal) values (clis[i], p, 'Casa nova', false);
        execute 'reset role';
        pontos[i] := p; zonas[i] := talatona;
      end loop;
      insert into sim values ('dia_talatona', d::text);
    end if;
    if d in (120, 127) then   -- Kilamba fecha uma semana (obras) e reabre
      perform testes.entrar_funcionario(dir); perform set_config('role', 'authenticated', true);
      update cozinhas set estado = case when d = 120 then 'pausada' else 'activa' end where id = cz_k;
      execute 'reset role';
    end if;
    kil_aberta := (select estado = 'activa' from cozinhas where id = cz_k);

    insert into turnos (data, funcionario_id, cozinha_id, periodo, hora_inicio, hora_fim) values
      (dia, g_a, cz_a, 'manha', '08:00', '16:00'), (dia, case when d < 45 then e_a else e_a2 end, cz_a, 'manha', '08:00', '16:00'),
      (dia, g_k, cz_k, 'manha', '08:00', '16:00'), (dia, e_k, cz_k, 'manha', '08:00', '16:00');

    perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
    cx_a := abrir_caixa(cz_a, 'Posto Semestre', 5000);
    execute 'reset role';
    caixas_abertas := caixas_abertas + 1;
    cx_k := null;
    if kil_aberta then
      perform testes.entrar_funcionario(g_k); perform set_config('role', 'authenticated', true);
      cx_k := abrir_caixa(cz_k, 'Posto Semestre', 3000);
      execute 'reset role';
      caixas_abertas := caixas_abertas + 1;
    end if;

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
      continue when not (i = n_cli or random() < 0.22);
      cz := case when zonas[i] = kil and i <> n_cli and random() < 0.6 then cz_k else cz_a end;
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
      begin
        insert into pedidos (id, cliente_id, ponto_entrega_id, cozinha_id, itens, dispositivo_id)
        values (pid, clis[i], pontos[i], cz, itens, 'sim-s' || lpad(d::text, 3, '0') || '-c' || lpad(i::text, 2, '0'));
      exception when others then
        -- cozinha pausada: o pedido é recusado e o cliente pede à Alexandra
        insert into recusas values (d, cz, sqlerrm);
        pid := gen_random_uuid();
        insert into pedidos (id, cliente_id, ponto_entrega_id, cozinha_id, itens, dispositivo_id)
        values (pid, clis[i], pontos[i], cz_a, jsonb_build_array(jsonb_build_object('cardapio_id', cach_a, 'qtd', 1)),
                'sim-s' || lpad(d::text, 3, '0') || '-c' || lpad(i::text, 2, '0'));
      end;
      if i = n_cli then
        begin
          perform usar_pacote(pid);
        exception when others then
          begin
            ad := aderir_pacote(pacote, 'loja');
            renovacoes := renovacoes + 1;
          exception when others then insert into sim values ('renovar_falhou_' || d, sqlerrm) on conflict do nothing;
          end;
        end;
      end if;
      execute 'reset role';
      dia_pedidos := dia_pedidos || pid;
    end loop;

    foreach pid in array dia_pedidos loop
      select x.*, cl.auth_user_id as uid into ped from pedidos x join clientes cl on cl.id = x.cliente_id where x.id = pid;
      ger := case when ped.cozinha_id = cz_a then g_a else g_k end;
      est := case when ped.cozinha_id = cz_k then e_k when d < 45 then e_a else e_a2 end;
      cx := case when ped.cozinha_id = cz_a then cx_a else cx_k end;
      r := random();
      if r < 0.05 and ped.pago_pacote = 0 then
        perform set_config('request.jwt.claims', json_build_object('sub', ped.uid, 'role', 'authenticated')::text, true);
        perform set_config('role', 'authenticated', true);
        perform cancelar_pedido(pid, 'Mudei de ideias');
        execute 'reset role';
      elsif r < 0.08 and ped.pago_pacote = 0 then
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
                     when random() < 0.6 then jsonb_build_array(jsonb_build_object('metodo', 'Dinheiro', 'valor', apagar))
                     when random() < 0.6 then jsonb_build_array(jsonb_build_object('metodo', 'Multicaixa Express', 'valor', apagar))
                     else jsonb_build_array(jsonb_build_object('metodo', 'Unitel Money', 'valor', apagar)) end;
        -- pagamento electrónico: o estafeta escreve a referência e fotografa o comprovativo
        if parc <> '[]'::jsonb and parc -> 0 ->> 'metodo' <> 'Dinheiro' then
          insert into storage.objects (bucket_id, name) values ('comprovativos', pid || '/talao.jpg');
          parc := jsonb_build_array((parc -> 0) || jsonb_build_object('referencia', 'SIM-' || pid, 'comprovativo', pid || '/talao.jpg'));
        end if;
        perform mudar_estado_pedido(pid, 'entregue_pago', null, cx, parc);
        execute 'reset role';
        if random() < 0.3 then
          perform set_config('request.jwt.claims', json_build_object('sub', ped.uid, 'role', 'authenticated')::text, true);
          perform set_config('role', 'authenticated', true);
          insert into avaliacoes (pedido_id, cliente_id, estrelas, usar_pseudonimo) values (pid, ped.cliente_id, 3 + floor(random() * 3)::int, false);
          execute 'reset role';
        end if;
      end if;
    end loop;

    if exists (select 1 from adesoes_pacote a where a.cliente_id = clis[n_cli] and a.estado = 'pendente') then
      select id into ad from adesoes_pacote a where a.cliente_id = clis[n_cli] and a.estado = 'pendente';
      perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
      perform confirmar_pagamento_pacote(ad, null, cx_a);
      execute 'reset role';
    end if;

    perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
    res := resumo_caixa(cx_a);
    dif := case when random() < 0.08 then (array[-500, -1000, 200])[1 + floor(random() * 3)::int] else 0 end;
    -- o gerente confere os pagamentos electrónicos com o extracto antes de fechar
    perform conferir_comprovativo(k.id, true) from comprovativos_pagamento k where k.caixa_id = cx_a and k.estado = 'por_conferir';
    perform fechar_caixa(cx_a, (res ->> 'esperado')::numeric + dif, case when dif <> 0 then 'Contagem não bate' end);
    execute 'reset role';
    insert into difs values (cx_a, dif);
    if cx_k is not null then
      perform testes.entrar_funcionario(g_k); perform set_config('role', 'authenticated', true);
      res := resumo_caixa(cx_k);
      dif := case when random() < 0.08 then -500 else 0 end;
      -- o gerente confere os pagamentos electrónicos com o extracto antes de fechar
      perform conferir_comprovativo(k.id, true) from comprovativos_pagamento k where k.caixa_id = cx_k and k.estado = 'por_conferir';
      perform fechar_caixa(cx_k, (res ->> 'esperado')::numeric + dif, case when dif <> 0 then 'Contagem não bate' end);
      execute 'reset role';
      insert into difs values (cx_k, dif);
    end if;

    -- último sábado de cada mês: Maria e Rosa levantam o que podem (até 20 000 Kz)
    if extract(isodow from dia) = 6 and extract(day from dia + 7) <= 7 then
      foreach ind in array array[1, 10] loop
        if (select coalesce(sum(valor), 0) from ganhos_indicacao where indicador_id = clis[ind] and estado = 'confirmado') >= 2000 then
          perform set_config('request.jwt.claims', json_build_object('sub', uids[ind], 'role', 'authenticated')::text, true);
          perform set_config('role', 'authenticated', true);
          begin
            perform pedir_levantamento(least(20000, (select sum(valor)::int from ganhos_indicacao where indicador_id = clis[ind] and estado = 'confirmado') / 100 * 100),
                                       'multicaixa_express', '9237' || lpad(ind::text, 5, '0'));
          exception when others then insert into sim values ('lev_falhou_' || d || '_' || ind, sqlerrm) on conflict do nothing;
          end;
          execute 'reset role';
          for lev in select id from pagamentos_indicacao where indicador_id = clis[ind] and estado not in ('pago', 'rejeitado', 'anulado', 'cancelado') order by criado_em loop
            perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
            begin
              perform aprovar_levantamento(lev);
              perform marcar_pago(lev, 'MCX-' || d || '-' || ind);
              pagos := pagos + 1;
            exception when others then insert into sim values ('pago_falhou_' || d || '_' || ind, sqlerrm) on conflict do nothing;
            end;
            execute 'reset role';
          end loop;
        end if;
      end loop;
    end if;

    if not ultimo then
      update pedidos set hora_prometida = (dia + time '11:00')::timestamp at time zone 'Africa/Luanda' + random() * interval '2 hours'
       where dispositivo_id like 'sim-s' || lpad(d::text, 3, '0') || '-%';
      update pedidos set entregue_em = hora_prometida + (random() * 55 - 25) * interval '1 minute'
       where dispositivo_id like 'sim-s' || lpad(d::text, 3, '0') || '-%' and entregue_em is not null;
      update vendas v set data = x.entregue_em from pedidos x where v.pedido_id = x.id and x.dispositivo_id like 'sim-s' || lpad(d::text, 3, '0') || '-%';
      update caixa set data = dia where id in (cx_a, cx_k);
    end if;
  end loop;
  t1 := clock_timestamp();

  insert into sim values ('dias_trab', dias_trab::text), ('caixas_abertas', caixas_abertas::text), ('renovacoes', renovacoes::text),
                         ('pagos', pagos::text), ('segundos_simulacao', round(extract(epoch from t1 - t0))::text), ('talatona', talatona::text);
  -- relatórios do semestre (e quanto tempo demoram com milhares de pedidos)
  perform testes.entrar_funcionario(dir); perform set_config('role', 'authenticated', true);
  t0 := clock_timestamp();
  insert into sim values ('comparativo', (select json_agg(t)::text from relatorio_comparativo(inicio, current_date) t));
  insert into sim values ('ms_comparativo', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  t0 := clock_timestamp();
  insert into sim values ('rel_mes1', relatorio_cozinha(cz_a, inicio, inicio + 30)::text);
  insert into sim values ('ms_relatorio', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  insert into sim values ('rel_semestre', relatorio_cozinha(cz_a, inicio, current_date)::text);
  t0 := clock_timestamp();
  insert into sim values ('painel', painel_programa(inicio, current_date)::text);
  insert into sim values ('ms_painel', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  insert into sim values ('embaixadores', (select json_agg(t)::text from embaixadores() t));
  execute 'reset role';
  perform testes.entrar_funcionario(g_a); perform set_config('role', 'authenticated', true);
  t0 := clock_timestamp();
  insert into sim values ('fila_operador', (select count(*)::text from pedidos_operador()));
  insert into sim values ('ms_fila', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  execute 'reset role';
  insert into sim values ('cz_a', cz_a::text), ('cz_k', cz_k::text), ('inicio', inicio::text), ('pedro', clis[n_cli]::text),
                         ('rosa', clis[10]::text), ('chocos', chocos::text);
end $sim$;

insert into tap_saida (linha) select is((select count(*)::int from clientes where nome like 'Cliente %' or nome in ('Maria Indica', 'Rosa Embaixadora', 'Pedro Pacote')), 50, '50 clientes registados');
insert into tap_saida (linha) select is((select count(*)::int from sim where chave like 'liga%' and valor = 'ok'), 38, '38 amigos entram com código (8 da Maria, 30 da Rosa)');
insert into tap_saida (linha) select ok((select count(*) from pedidos where dispositivo_id like 'sim-s%') >= 1500, 'mais de 1 500 pedidos em 6 meses');
insert into tap_saida (linha) select is((select count(*)::int from pedidos where dispositivo_id like 'sim-s%' and estado not in ('entregue_pago', 'cancelado')), 0, 'nenhum pedido fica a meio');
insert into tap_saida (linha) select is((select count(*)::int from pedidos x where x.dispositivo_id like 'sim-s%' and x.estado = 'entregue_pago'
            and (select coalesce(sum(valor_total), 0) from vendas v where v.pedido_id = x.id) <> x.subtotal + x.taxa_entrega - x.desconto_indicacao), 0,
          'cada entrega gerou vendas com o valor exacto');
insert into tap_saida (linha) select is((select count(*)::int from caixa where posto = 'Posto Semestre' and fechamento is not null), (select valor from sim where chave = 'caixas_abertas')::int,
          'todas as caixas abertas foram fechadas');
insert into tap_saida (linha) select is((select count(*)::int from caixa c where c.posto = 'Posto Semestre'
            and ((c.fechamento ->> 'esperado')::numeric <> c.troco_inicial
                 + coalesce((select sum((p ->> 'valor')::numeric) from vendas v, jsonb_array_elements(v.parcelas) p where v.caixa_id = c.id and p ->> 'metodo' = 'Dinheiro'), 0)
                 + coalesce((select sum(preco) from adesoes_pacote a where a.caixa_id = c.id and a.metodo = 'loja'), 0)
                 or (c.fechamento ->> 'diferenca')::numeric <> (select dif from difs where caixa = c.id))), 0,
          'cada caixa: esperado certo e diferença registada exactamente');
insert into tap_saida (linha) select is((select array_agg(distinct (i ->> 'preco_unitario')::int order by (i ->> 'preco_unitario')::int)
            from pedidos x, jsonb_array_elements(x.itens) i
           where x.dispositivo_id like 'sim-s%' and i ->> 'cardapio_id' = (select valor from sim where chave = 'chocos')
             and substr(x.dispositivo_id, 6, 3)::int < (select valor from sim where chave = 'dia_preco')::int), array[6000],
          'antes do aumento os Chocos custavam 6 000 Kz');
insert into tap_saida (linha) select is((select array_agg(distinct (i ->> 'preco_unitario')::int)
            from pedidos x, jsonb_array_elements(x.itens) i
           where x.dispositivo_id like 'sim-s%' and i ->> 'cardapio_id' = (select valor from sim where chave = 'chocos')
             and substr(x.dispositivo_id, 6, 3)::int >= (select valor from sim where chave = 'dia_preco')::int), array[6500],
          'depois do aumento todos os pedidos usam 6 500 Kz (o servidor recalcula)');
insert into tap_saida (linha) select ok((select count(*) from pedidos x join pontos_entrega pe on pe.id = x.ponto_entrega_id
             where x.dispositivo_id like 'sim-s%' and pe.zona_id = (select valor from sim where chave = 'talatona')::uuid) > 0
          and not exists (select 1 from pedidos x join pontos_entrega pe on pe.id = x.ponto_entrega_id
             where x.dispositivo_id like 'sim-s%' and pe.zona_id = (select valor from sim where chave = 'talatona')::uuid and x.taxa_entrega <> 1500),
          'o bairro novo (Talatona) recebe pedidos com a sua taxa (1 500 Kz)');
insert into tap_saida (linha) select ok((select count(*) from recusas where cozinha = (select valor from sim where chave = 'cz_k')::uuid) > 0
          and not exists (select 1 from pedidos where dispositivo_id like 'sim-s%' and cozinha_id = (select valor from sim where chave = 'cz_k')::uuid
                            and substr(dispositivo_id, 6, 3)::int between 120 and 126),
          'com o Kilamba pausado os pedidos são recusados (e os clientes pedem à Alexandra)');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'renovacoes')::int >= 5
          and (select sum(refeicoes_usadas)::int from adesoes_pacote where cliente_id = (select valor from sim where chave = 'pedro')::uuid)
              = (select count(*)::int from pedidos where cliente_id = (select valor from sim where chave = 'pedro')::uuid and pago_pacote > 0 and estado = 'entregue_pago'),
          'o pacote do Pedro acaba e é renovado várias vezes, uma refeição por almoço');
insert into tap_saida (linha) select ok(((select valor from sim where chave = 'rel_mes1')::jsonb -> 'retencao' ->> '90') is not null, 'retenção a 90 dias calculada para os clientes do 1.º mês');
insert into tap_saida (linha) select ok(exists (select 1 from json_array_elements((select valor from sim where chave = 'embaixadores')::json) e
                  where e ->> 'cliente_id' = (select valor from sim where chave = 'rosa') or e::text like '%Rosa Embaixadora%'),
          'a Rosa, com 30 amigos activos, aparece como elegível a embaixadora');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'pagos')::int >= 4
          and (select count(*) from notificacoes_fila where codigo = 'N8') = (select valor from sim where chave = 'pagos')::int,
          'levantamentos mensais aprovados e pagos, cada um com aviso N8');
insert into tap_saida (linha) select ok((select count(*) from pedidos x, jsonb_array_elements(x.parcelas) p
             where x.dispositivo_id like 'sim-s%' and p ->> 'metodo' <> 'Dinheiro') > 0
          and (select count(*) from pedidos x, jsonb_array_elements(x.parcelas) p
                where x.dispositivo_id like 'sim-s%' and p ->> 'metodo' <> 'Dinheiro')
              = (select count(*) from comprovativos_pagamento k join pedidos x on x.id = k.pedido_id
                  where x.dispositivo_id like 'sim-s%' and k.estado = 'conferido'),
          'cada pagamento electrónico tem referência e foto, conferidos antes do fecho da caixa');
insert into tap_saida (linha) select ok((select valor from sim where chave = 'ms_comparativo')::int < 3000 and (select valor from sim where chave = 'ms_fila')::int < 1000,
          'relatório do semestre em menos de 3 s e fila do operador em menos de 1 s');

insert into sim values ('resumo', (select json_build_object(
  'pedidos', count(*), 'entregues', count(*) filter (where estado = 'entregue_pago'), 'cancelados', count(*) filter (where estado = 'cancelado'),
  'por_mes', (select json_object_agg(m, n) from (select to_char((inicio_d)::date, 'YYYY-MM') m, count(*) n from (select (select valor from sim where chave = 'inicio')::date + substr(dispositivo_id, 6, 3)::int as inicio_d from pedidos where dispositivo_id like 'sim-s%') z group by 1 order by 1) w),
  'faturacao', (select json_object_agg(c.nome, s) from (select v.cozinha_id, sum(v.valor_total) s from vendas v join pedidos x on x.id = v.pedido_id where x.dispositivo_id like 'sim-s%' group by 1) z join cozinhas c on c.id = z.cozinha_id),
  'por_metodo', (select json_object_agg(m, s) from (select p ->> 'metodo' m, sum((p ->> 'valor')::numeric) s from vendas v join pedidos x on x.id = v.pedido_id, jsonb_array_elements(v.parcelas) p where x.dispositivo_id like 'sim-s%' group by 1) z),
  'diferencas_caixa', (select json_build_object('fechos', count(*), 'com_diferenca', count(*) filter (where dif <> 0), 'total', sum(dif)) from difs),
  'recusas_kilamba', (select count(*) from recusas),
  'descontos_indicacao', sum(desconto_indicacao) filter (where estado = 'entregue_pago'),
  'ganhos', (select json_object_agg(estado, s) from (select estado, sum(valor) s from ganhos_indicacao group by 1) z),
  'avaliacoes', (select json_build_object('n', count(*), 'media', round(avg(estrelas), 2)) from avaliacoes a join pedidos x on x.id = a.pedido_id where x.dispositivo_id like 'sim-s%'),
  'avisos', (select json_object_agg(codigo, n) from (select codigo, count(*) n from notificacoes_fila group by 1 order by 1) z)
)::text from pedidos where dispositivo_id like 'sim-s%'));
insert into tap_saida (linha) select * from finish();
do $fim$ begin raise exception 'TAP %', E'\n' || (select string_agg(linha, E'\n' order by n) from tap_saida)
  || E'\n--- dados ---\n' || (select string_agg(chave || ': ' || left(valor, 600), E'\n' order by chave) from sim
                              where chave not like 'liga%' and chave not in ('cz_a', 'cz_k', 'pedro', 'rosa', 'chocos', 'talatona', 'rel_semestre')); end $fim$;
