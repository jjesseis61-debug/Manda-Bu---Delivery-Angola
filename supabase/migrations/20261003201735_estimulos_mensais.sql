-- Estímulos mensais (Albert Bandura) e análise automática das reclamações e dos estímulos (Edge Function
-- analisar-ia). Ver a migração das reclamações para o contexto.

-- ---------------------------------------------------------------- 2. desempenho e estímulos mensais
create table estimulos_mensais (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  ano              integer not null check (ano between 2020 and 2100),
  mes              integer not null check (mes between 1 and 12),
  tipo             text not null check (tipo in ('funcionario', 'cliente')),
  funcionario_id   uuid references funcionarios(id),
  cliente_id       uuid references clientes(id),
  metricas         jsonb not null default '{}',   -- {"mes": {...}, "anterior": {...}}
  foco             text,                          -- métrica em que se trabalha
  conquista        text,                          -- o que melhorou (mestria)
  modelo           text,                          -- melhor registo da equipa (vicariante)
  meta             jsonb,                         -- {"metrica": ..., "valor": ...} para o mês seguinte
  meta_anterior    jsonb,                         -- meta dada no mês anterior e se foi atingida
  mensagem         text not null,                 -- texto base (sempre disponível)
  ia_estado        text not null default 'pendente'
                     check (ia_estado in ('pendente', 'a_analisar', 'analisada', 'indisponivel')),
  ia_tentativas    integer not null default 0,
  ia_mensagem      text,
  ia_nota          text,
  bonus_sugerido   integer not null default 0,
  bonus            integer,
  mensagem_final   text,
  estado           text not null default 'proposto' check (estado in ('proposto', 'aprovado', 'descartado')),
  decidido_por     uuid references funcionarios(id),
  decidido_em      timestamptz,
  check ((tipo = 'funcionario') = (funcionario_id is not null) and (tipo = 'cliente') = (cliente_id is not null))
);
create unique index estimulos_funcionario_mes_key on estimulos_mensais (ano, mes, funcionario_id) where funcionario_id is not null;
create unique index estimulos_cliente_mes_key on estimulos_mensais (ano, mes, cliente_id) where cliente_id is not null;
create index estimulos_funcionario_idx on estimulos_mensais (funcionario_id);
create index estimulos_cliente_idx on estimulos_mensais (cliente_id);
create index estimulos_decidido_por_idx on estimulos_mensais (decidido_por);
create index estimulos_ia_pendente_idx on estimulos_mensais (criado_em) where ia_estado = 'pendente';
create trigger trg_0_so_servidor before insert or update or delete on estimulos_mensais
for each row execute function bloquear_escrita_dispositivo();
create trigger trg_sync_receber before insert or update on estimulos_mensais
for each row execute function sync_receber();
alter table estimulos_mensais enable row level security;
revoke all on estimulos_mensais from anon;
revoke insert, update, delete, truncate on estimulos_mensais from authenticated;
grant select on estimulos_mensais to authenticated;
create policy ler on estimulos_mensais for select to authenticated
  using (deletado_em is null and (tem_permissao('equipa.gerir')
                                  or (estado = 'aprovado' and funcionario_id is not null and funcionario_id = funcionario_actual())));
comment on table estimulos_mensais is 'Sincronização: só servidor (desempenho do mês, metas e estímulos aprovados). Telemóvel só lê.';

create or replace function nome_mes(p_mes int) returns text
language sql immutable set search_path = public as $$
  select (array['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro',
                'Outubro', 'Novembro', 'Dezembro'])[p_mes];
$$;

-- Números de um funcionário num mês (Luanda)
create or replace function metricas_funcionario(p_func uuid, p_ini date) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (select alerta_atraso_min from parametros where unico),
  ent as (select x.* from pedidos x
           where x.entregador_id = p_func and x.deletado_em is null and x.estado = 'entregue_pago'
             and (x.entregue_em at time zone 'Africa/Luanda')::date >= p_ini
             and (x.entregue_em at time zone 'Africa/Luanda')::date < (p_ini + interval '1 month')::date),
  hor as (select count(*) filter (where e.hora_prometida is not null) com_hora,
                 count(*) filter (where e.hora_prometida is not null
                                    and e.entregue_em <= e.hora_prometida + make_interval(mins => p.alerta_atraso_min)) a_horas
            from ent e, p),
  av as (select count(*) n, round(avg(a.estrelas)::numeric, 1) media
           from avaliacoes a join ent e on e.id = a.pedido_id where a.deletado_em is null),
  ven as (select count(*) n, coalesce(sum(v.valor_total), 0) valor from vendas v
           where v.registado_por = p_func and v.pedido_id is null and v.deletado_em is null
             and (v.data at time zone 'Africa/Luanda')::date >= p_ini
             and (v.data at time zone 'Africa/Luanda')::date < (p_ini + interval '1 month')::date)
  select jsonb_build_object(
    'entregas', (select count(*) from ent),
    'com_hora', hor.com_hora,
    'a_horas', hor.a_horas,
    'pct_a_horas', case when hor.com_hora > 0 then round(100.0 * hor.a_horas / hor.com_hora)::int end,
    'avaliacoes', av.n,
    'estrelas', av.media,
    'vendas_balcao', ven.n,
    'valor_balcao', ven.valor,
    'confirmados', (select count(*) from auditoria a
                     where a.funcionario_id = p_func and a.acao = 'pedido_estado' and a.deletado_em is null
                       and (a.detalhe::jsonb) ->> 'para' = 'confirmado'
                       and (a.data at time zone 'Africa/Luanda')::date >= p_ini
                       and (a.data at time zone 'Africa/Luanda')::date < (p_ini + interval '1 month')::date),
    'reclamacoes_procedentes', (select count(*) from reclamacoes r
                                 where r.entregador_id = p_func and r.procedente and r.deletado_em is null
                                   and (r.criado_em at time zone 'Africa/Luanda')::date >= p_ini
                                   and (r.criado_em at time zone 'Africa/Luanda')::date < (p_ini + interval '1 month')::date),
    'comprovativos_rejeitados', (select count(*) from comprovativos_pagamento k
                                  where k.registado_por = p_func and k.estado = 'rejeitado' and k.deletado_em is null
                                    and (k.criado_em at time zone 'Africa/Luanda')::date >= p_ini
                                    and (k.criado_em at time zone 'Africa/Luanda')::date < (p_ini + interval '1 month')::date))
  from hor, av, ven;
$$;
revoke execute on function metricas_funcionario(uuid, date) from public, anon, authenticated;

-- Números de um cliente num mês: pedidos entregues e compras ao balcão
create or replace function metricas_cliente(p_cliente uuid, p_ini date) returns jsonb
language sql stable security definer set search_path = public as $$
  with ped as (select count(*) n, coalesce(sum(subtotal + taxa_entrega - desconto_indicacao), 0) valor from pedidos
                where cliente_id = p_cliente and deletado_em is null and estado = 'entregue_pago'
                  and (entregue_em at time zone 'Africa/Luanda')::date >= p_ini
                  and (entregue_em at time zone 'Africa/Luanda')::date < (p_ini + interval '1 month')::date),
  bal as (select count(*) n, coalesce(sum(valor_total), 0) valor from vendas
           where cliente_id = p_cliente and pedido_id is null and deletado_em is null
             and (data at time zone 'Africa/Luanda')::date >= p_ini
             and (data at time zone 'Africa/Luanda')::date < (p_ini + interval '1 month')::date)
  select jsonb_build_object('pedidos', ped.n + bal.n, 'gasto', ped.valor + bal.valor) from ped, bal;
$$;
revoke execute on function metricas_cliente(uuid, date) from public, anon, authenticated;

-- Gera (ou refaz, enquanto só propostos) os estímulos de um mês. Regras de Bandura:
--  * mestria: compara cada pessoa consigo própria no mês anterior, nunca com quem está pior;
--  * meta próxima: um passo pequeno acima do que já fez (+10% ou +5 pontos a horas);
--  * modelo: o melhor registo da equipa no mesmo ponto, como prova de que é possível;
--  * persuasão verbal: elogio concreto, com números; o bónus é pela meta combinada, não pelo ranking.
create or replace function gerar_estimulos_mes(p_ano int, p_mes int) returns int
language plpgsql security definer set search_path = public as $$
declare
  par       parametros;
  v_ini     date := make_date(p_ano, p_mes, 1);
  v_ant     date := (make_date(p_ano, p_mes, 1) - interval '1 month')::date;
  v_seg     int := extract(month from make_date(p_ano, p_mes, 1) + interval '1 month')::int;
  v_mes     text := nome_mes(p_mes);
  v_mes_ant text := nome_mes(extract(month from v_ant)::int);
  v_mes_seg text := nome_mes(v_seg);
  x         record;
  m         jsonb;
  a         jsonb;
  v_foco    text;
  v_val     numeric;
  v_val_ant numeric;
  v_melhor  numeric;
  v_meta    numeric;
  v_unid    text;
  v_conq    text;
  v_modelo  text;
  v_meta_ant jsonb;
  v_atingiu boolean;
  v_bonus   int;
  v_msg     text;
  v_extra   text;
  n         int := 0;
  v_melhores jsonb;
  v_activos int;
begin
  select * into par from parametros where unico;

  -- Melhor registo da equipa em cada ponto (o modelo) e quantos trabalharam no mês
  select jsonb_build_object(
           'pct_a_horas', max((met ->> 'pct_a_horas')::int) filter (where (met ->> 'com_hora')::int >= 5),
           'entregas', max((met ->> 'entregas')::int),
           'vendas_balcao', max((met ->> 'vendas_balcao')::int),
           'confirmados', max((met ->> 'confirmados')::int)),
         count(*) filter (where coalesce((met ->> 'entregas')::int, 0) + coalesce((met ->> 'vendas_balcao')::int, 0)
                                + coalesce((met ->> 'confirmados')::int, 0) > 0)
    into v_melhores, v_activos
    from (select metricas_funcionario(f.id, v_ini) as met from funcionarios f where f.deletado_em is null) s;

  -- Funcionários com actividade no mês
  for x in
    select * from (select f.id as funcionario_id, split_part(trim(f.nome), ' ', 1) as nome,
                          metricas_funcionario(f.id, v_ini) as met, metricas_funcionario(f.id, v_ant) as ant
                     from funcionarios f where f.deletado_em is null) s
     where coalesce((s.met ->> 'entregas')::int, 0) + coalesce((s.met ->> 'vendas_balcao')::int, 0)
           + coalesce((s.met ->> 'confirmados')::int, 0) > 0
  loop
    m := x.met; a := x.ant;
    v_foco := case
      when (m ->> 'com_hora')::int >= 5 then 'pct_a_horas'
      when (m ->> 'entregas')::int > 0 then 'entregas'
      when (m ->> 'vendas_balcao')::int > 0 then 'vendas_balcao'
      else 'confirmados' end;
    v_val := (m ->> v_foco)::numeric;
    v_val_ant := case when v_foco = 'pct_a_horas' and coalesce((a ->> 'com_hora')::int, 0) < 5 then null
                      else nullif((a ->> v_foco)::numeric, 0) end;
    v_melhor := (v_melhores ->> v_foco)::numeric;
    v_unid := case v_foco when 'pct_a_horas' then '% das entregas a horas' when 'entregas' then ' entregas'
                          when 'vendas_balcao' then ' vendas ao balcão' else ' pedidos confirmados' end;

    -- mestria: o progresso em relação a si próprio
    v_conq := case
      when v_foco = 'pct_a_horas' then format('Em %s, %s%% das tuas %s entregas chegaram a horas', v_mes, v_val, m ->> 'entregas')
      else format('Em %s fizeste %s%s', v_mes, v_val, v_unid) end;
    if v_val_ant is not null and v_val > v_val_ant then
      v_conq := v_conq || case when v_foco = 'pct_a_horas' then format(', mais %s pontos do que em %s', v_val - v_val_ant, v_mes_ant)
                               else format(', mais %s do que em %s', v_val - v_val_ant, v_mes_ant) end;
    elsif v_val_ant is not null and v_val < v_val_ant then
      v_conq := v_conq || case when v_foco = 'pct_a_horas' then format('. Em %s chegaste aos %s%%: já mostraste que consegues', v_mes_ant, v_val_ant)
                               else format('. Em %s chegaste a %s: já mostraste que consegues', v_mes_ant, v_val_ant) end;
    end if;
    v_conq := v_conq || '.';

    -- modelo: o melhor da equipa (sem nomes), ou o reconhecimento de ser a referência
    v_modelo := case
      when v_melhor is null then null
      when v_val >= v_melhor and v_activos > 1 then 'Foste a referência da equipa neste ponto.'
      when v_val < v_melhor then case when v_foco = 'pct_a_horas'
                                      then format('Na equipa, o melhor registo foi %s%% a horas: está ao teu alcance.', v_melhor)
                                      else format('Na equipa, o melhor registo foi %s%s: está ao teu alcance.', v_melhor, v_unid) end
      end;

    -- meta próxima: um pequeno passo acima do que já fez
    v_meta := case when v_foco = 'pct_a_horas' then case when v_val >= 95 then 95 else least(100, v_val + 5) end
                   else greatest(v_val + 1, ceil(v_val * 1.1)) end;

    -- meta do mês anterior: atingida?
    select e.meta into v_meta_ant from estimulos_mensais e
     where e.funcionario_id = x.funcionario_id and e.ano = extract(year from v_ant) and e.mes = extract(month from v_ant)
       and e.estado = 'aprovado' and e.deletado_em is null;
    v_atingiu := v_meta_ant is not null and (m ->> (v_meta_ant ->> 'metrica'))::numeric >= (v_meta_ant ->> 'valor')::numeric;
    v_bonus := case when v_atingiu then par.estimulo_bonus_meta else 0 end;

    v_extra := '';
    if (m ->> 'avaliacoes')::int >= 3 and (m ->> 'estrelas')::numeric >= 4.5 then
      v_extra := v_extra || format(' Os clientes deram-te %s estrelas em média.', m ->> 'estrelas');
    end if;
    if (m ->> 'reclamacoes_procedentes')::int > 0 then
      v_extra := v_extra || format(' Houve %s com razão: vale a pena rever com o gerente o que aconteceu.',
                                   case when (m ->> 'reclamacoes_procedentes')::int = 1 then '1 reclamação'
                                        else (m ->> 'reclamacoes_procedentes') || ' reclamações' end);
    end if;
    v_msg := format('%s, %s', x.nome, lower(left(v_conq, 1)) || substr(v_conq, 2))
             || case when v_atingiu then ' Atingiste a meta que combinámos. Parabéns!' else '' end
             || v_extra
             || coalesce(' ' || v_modelo, '')
             || format(' Meta para %s: %s.', v_mes_seg,
                       case when v_foco = 'pct_a_horas' then format('%s%% das entregas a horas', v_meta)
                            else format('%s%s', v_meta, v_unid) end);

    insert into estimulos_mensais (dispositivo_id, sincronizado_em, ano, mes, tipo, funcionario_id, metricas, foco,
                                   conquista, modelo, meta, meta_anterior, mensagem, bonus_sugerido)
    values ('servidor', now(), p_ano, p_mes, 'funcionario', x.funcionario_id,
            jsonb_build_object('mes', m, 'anterior', a), v_foco, v_conq, v_modelo,
            jsonb_build_object('metrica', v_foco, 'valor', v_meta),
            case when v_meta_ant is not null then v_meta_ant || jsonb_build_object('atingida', v_atingiu) end,
            v_msg, v_bonus)
    on conflict (ano, mes, funcionario_id) where funcionario_id is not null do update
       set metricas = excluded.metricas, foco = excluded.foco, conquista = excluded.conquista, modelo = excluded.modelo,
           meta = excluded.meta, meta_anterior = excluded.meta_anterior, mensagem = excluded.mensagem,
           bonus_sugerido = excluded.bonus_sugerido, ia_estado = 'pendente', ia_tentativas = 0, ia_mensagem = null,
           atualizado_em = now()
     where estimulos_mensais.estado = 'proposto';
    n := n + 1;
  end loop;

  -- Clientes que mais compraram (pelo menos 2 compras)
  for x in
    select c.id as cliente_id, split_part(trim(c.nome), ' ', 1) as nome, s.m, metricas_cliente(c.id, v_ant) as a
      from (select cl.id, metricas_cliente(cl.id, v_ini) as m from clientes cl where cl.deletado_em is null) s
      join clientes c on c.id = s.id
     where (s.m ->> 'pedidos')::int >= 2
     order by (s.m ->> 'gasto')::numeric desc, (s.m ->> 'pedidos')::int desc
     limit par.estimulo_top_clientes
  loop
    m := x.m; a := x.a;
    v_val := (m ->> 'pedidos')::numeric;
    v_val_ant := nullif((a ->> 'pedidos')::numeric, 0);
    v_conq := format('Em %s fizeste %s pedidos na Manda Bué', v_mes, v_val)
              || case when v_val_ant is not null and v_val > v_val_ant
                      then format(', mais %s do que em %s', v_val - v_val_ant, v_mes_ant) else '' end || '.';
    v_meta := greatest(v_val + 1, ceil(v_val * 1.1));
    select e.meta into v_meta_ant from estimulos_mensais e
     where e.cliente_id = x.cliente_id and e.ano = extract(year from v_ant) and e.mes = extract(month from v_ant)
       and e.estado = 'aprovado' and e.deletado_em is null;
    v_atingiu := v_meta_ant is not null and (m ->> 'pedidos')::numeric >= (v_meta_ant ->> 'valor')::numeric;
    v_bonus := case when v_atingiu then par.estimulo_premio_cliente else 0 end;
    v_msg := format('Obrigado, %s! %s', x.nome, v_conq)
             || case when v_atingiu then ' Chegaste à meta do mês passado: tens um prémio à tua espera.' else '' end
             || format(' Com %s pedidos em %s%s', v_meta, v_mes_seg,
                       case when par.estimulo_premio_cliente > 0 then ' ganhas um prémio.' else ' ficas entre os nossos melhores clientes.' end);

    insert into estimulos_mensais (dispositivo_id, sincronizado_em, ano, mes, tipo, cliente_id, metricas, foco,
                                   conquista, meta, meta_anterior, mensagem, bonus_sugerido)
    values ('servidor', now(), p_ano, p_mes, 'cliente', x.cliente_id, jsonb_build_object('mes', m, 'anterior', a),
            'pedidos', v_conq, jsonb_build_object('metrica', 'pedidos', 'valor', v_meta),
            case when v_meta_ant is not null then v_meta_ant || jsonb_build_object('atingida', v_atingiu) end,
            v_msg, v_bonus)
    on conflict (ano, mes, cliente_id) where cliente_id is not null do update
       set metricas = excluded.metricas, conquista = excluded.conquista, meta = excluded.meta,
           meta_anterior = excluded.meta_anterior, mensagem = excluded.mensagem, bonus_sugerido = excluded.bonus_sugerido,
           ia_estado = 'pendente', ia_tentativas = 0, ia_mensagem = null, atualizado_em = now()
     where estimulos_mensais.estado = 'proposto';
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function gerar_estimulos_mes(int, int) from public, anon, authenticated;

-- Pela app: quem gere a equipa gera ou refaz os estímulos de um mês (até ao mês corrente)
create or replace function gerar_estimulos(p_ano int, p_mes int) returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  if not tem_permissao('equipa.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_ano is null or p_mes is null or p_mes not between 1 and 12 or p_ano not between 2020 and 2100
     or make_date(p_ano, p_mes, 1) > (now() at time zone 'Africa/Luanda')::date then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  n := gerar_estimulos_mes(p_ano, p_mes);
  perform registar_auditoria('estimulos_gerados', 'estimulos_mensais', null, jsonb_build_object('ano', p_ano, 'mes', p_mes, 'n', n));
  return n;
end $$;
revoke execute on function gerar_estimulos(int, int) from public, anon;
grant execute on function gerar_estimulos(int, int) to authenticated;

-- Dia 1 de cada mês: estímulos do mês que acabou (ficam propostos para o administrador)
create or replace function job_estimulos_mensais() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_ant date := (date_trunc('month', now() at time zone 'Africa/Luanda') - interval '1 month')::date;
begin
  return gerar_estimulos_mes(extract(year from v_ant)::int, extract(month from v_ant)::int);
end $$;
revoke execute on function job_estimulos_mensais() from public, anon, authenticated;

create or replace function estimulos_do_mes(p_ano int, p_mes int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('equipa.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', e.id, 'tipo', e.tipo, 'nome', coalesce(f.nome, c.nome), 'cargo', f.cargo,
             'metricas', e.metricas, 'foco', e.foco, 'conquista', e.conquista, 'modelo', e.modelo,
             'meta', e.meta, 'meta_anterior', e.meta_anterior, 'mensagem', e.mensagem,
             'ia_estado', e.ia_estado, 'ia_mensagem', e.ia_mensagem, 'ia_nota', e.ia_nota,
             'bonus_sugerido', e.bonus_sugerido, 'bonus', e.bonus, 'mensagem_final', e.mensagem_final,
             'estado', e.estado, 'decidido_por', d.nome, 'decidido_em', e.decidido_em)
           order by e.tipo desc, e.bonus_sugerido desc, coalesce(f.nome, c.nome))
      from estimulos_mensais e
      left join funcionarios f on f.id = e.funcionario_id
      left join clientes c on c.id = e.cliente_id
      left join funcionarios d on d.id = e.decidido_por
     where e.deletado_em is null and e.ano = p_ano and e.mes = p_mes), '[]');
end $$;
revoke execute on function estimulos_do_mes(int, int) from public, anon;
grant execute on function estimulos_do_mes(int, int) to authenticated;

-- O administrador aprova (com o bónus e a mensagem, que pode editar) ou descarta; aprovado -> N23
create or replace function decidir_estimulo(p_id uuid, p_aprovar boolean, p_bonus int default null,
                                            p_mensagem text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  e estimulos_mensais;
  v_msg text;
  v_bonus int;
begin
  if not tem_permissao('equipa.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
  select * into e from estimulos_mensais where id = p_id and deletado_em is null for update;
  if not found then raise exception 'estimulo_inexistente' using errcode = 'P0001'; end if;
  if e.estado <> 'proposto' then raise exception 'estimulo_decidido' using errcode = 'P0001'; end if;
  if p_aprovar is null or (p_bonus is not null and p_bonus not between 0 and 1000000) then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  if p_mensagem is not null and char_length(p_mensagem) > 600 then raise exception 'observacao_longa' using errcode = 'P0001'; end if;
  v_msg := coalesce(nullif(trim(p_mensagem), ''), e.ia_mensagem, e.mensagem);
  v_bonus := coalesce(p_bonus, e.bonus_sugerido);
  update estimulos_mensais
     set estado = case when p_aprovar then 'aprovado' else 'descartado' end,
         bonus = case when p_aprovar then v_bonus end,
         mensagem_final = case when p_aprovar then v_msg end,
         decidido_por = funcionario_actual(), decidido_em = now(), atualizado_em = now()
   where id = e.id;
  if p_aprovar then
    insert into notificacoes_fila (funcionario_id, cliente_id, codigo, dados)
    values (e.funcionario_id, e.cliente_id, 'N23',
            jsonb_build_object('estimulo_id', e.id, 'mensagem', v_msg, 'bonus', v_bonus));
  end if;
  perform registar_auditoria(case when p_aprovar then 'estimulo_aprovado' else 'estimulo_descartado' end,
    'estimulos_mensais', e.id,
    jsonb_build_object('ano', e.ano, 'mes', e.mes, 'tipo', e.tipo, 'bonus', v_bonus, 'bonus_sugerido', e.bonus_sugerido));
end $$;
revoke execute on function decidir_estimulo(uuid, boolean, int, text) from public, anon;
grant execute on function decidir_estimulo(uuid, boolean, int, text) to authenticated;

-- ---------------------------------------------------------------- 3. análise automática (Edge Function analisar-ia)
-- Reserva reclamações e estímulos por analisar (só a Edge Function, com a chave de serviço)
create or replace function reservar_analises(p_limite int default 5) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_rec jsonb;
  v_est jsonb;
begin
  with escolhidas as (
    select id from reclamacoes
     where deletado_em is null and estado = 'aberta'
       and (ia_estado = 'pendente' or (ia_estado = 'a_analisar' and atualizado_em < now() - interval '5 minutes'))
     order by criado_em limit greatest(1, least(coalesce(p_limite, 5), 20))
     for update skip locked
  ), r as (
    update reclamacoes k set ia_estado = 'a_analisar', atualizado_em = now()
      from escolhidas e where k.id = e.id
    returning k.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'origem', r.origem, 'estrelas', r.estrelas, 'texto', r.texto,
                                               'factos', factos_reclamacao(r.id))), '[]')
    into v_rec from r;
  with escolhidos as (
    select id from estimulos_mensais
     where deletado_em is null and estado = 'proposto'
       and (ia_estado = 'pendente' or (ia_estado = 'a_analisar' and atualizado_em < now() - interval '5 minutes'))
     order by criado_em limit greatest(1, least(coalesce(p_limite, 5), 20))
     for update skip locked
  ), r as (
    update estimulos_mensais k set ia_estado = 'a_analisar', atualizado_em = now()
      from escolhidos e where k.id = e.id
    returning k.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'tipo', r.tipo, 'ano', r.ano, 'mes', r.mes,
           'nome', (select split_part(trim(coalesce(f.nome, c.nome)), ' ', 1) from (select 1) u
                      left join funcionarios f on f.id = r.funcionario_id left join clientes c on c.id = r.cliente_id),
           'cargo', (select cargo from funcionarios where id = r.funcionario_id),
           'metricas', r.metricas, 'foco', r.foco, 'conquista', r.conquista, 'modelo', r.modelo, 'meta', r.meta,
           'meta_anterior', r.meta_anterior, 'bonus_sugerido', r.bonus_sugerido, 'mensagem_base', r.mensagem)), '[]')
    into v_est from r;
  return jsonb_build_object('reclamacoes', v_rec, 'estimulos', v_est);
end $$;

create or replace function registar_analise_reclamacao(p_id uuid, p_resultado text, p_analise jsonb default null,
                                                       p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  r reclamacoes;
  v_estado text;
begin
  select * into r from reclamacoes where id = p_id for update;
  if not found then raise exception 'reclamacao_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    update reclamacoes
       set ia_tentativas = ia_tentativas + 1,
           ia_estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'pendente' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = r.id returning ia_estado into v_estado;
    return v_estado;
  end if;
  if p_resultado = 'indisponivel' then
    update reclamacoes set ia_estado = 'indisponivel', ia_nota = left(p_nota, 300), atualizado_em = now() where id = r.id;
    return 'indisponivel';
  end if;
  if p_resultado <> 'analisada' or p_analise is null then raise exception 'resultado_invalido' using errcode = 'P0001'; end if;
  update reclamacoes
     set ia_estado = 'analisada',
         ia_categoria = case when p_analise ->> 'categoria' in ('atraso', 'qualidade', 'quantidade', 'pedido_errado', 'estafeta',
                                                                 'pagamento', 'app', 'outro') then p_analise ->> 'categoria' else 'outro' end,
         ia_gravidade = case when p_analise ->> 'gravidade' in ('baixa', 'media', 'alta') then p_analise ->> 'gravidade' end,
         ia_procedente = case when p_analise ->> 'procedente' in ('sim', 'nao', 'incerto') then p_analise ->> 'procedente' else 'incerto' end,
         ia_fundamento = left(p_analise ->> 'fundamento', 600),
         ia_resumo = left(p_analise ->> 'resumo', 300),
         ia_accao = left(p_analise ->> 'accao_sugerida', 300),
         ia_resposta = left(p_analise ->> 'resposta_cliente', 500),
         ia_compensacao = case when p_analise ->> 'compensacao' in ('nenhuma', 'pedido_desculpa', 'desconto', 'reembolso_parcial',
                                                                    'reembolso_total') then p_analise ->> 'compensacao' end,
         ia_nota = left(p_nota, 300), ia_analisada_em = now(), atualizado_em = now()
   where id = r.id;
  perform registar_auditoria('reclamacao_analisada', 'pedidos', r.pedido_id,
    jsonb_build_object('reclamacao_id', r.id, 'procedente', p_analise ->> 'procedente', 'categoria', p_analise ->> 'categoria'));
  return 'analisada';
end $$;

create or replace function registar_mensagem_estimulo(p_id uuid, p_resultado text, p_mensagem text default null,
                                                      p_nota text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  e estimulos_mensais;
  v_estado text;
begin
  select * into e from estimulos_mensais where id = p_id for update;
  if not found then raise exception 'estimulo_inexistente' using errcode = 'P0001'; end if;
  if p_resultado = 'erro' then
    update estimulos_mensais
       set ia_tentativas = ia_tentativas + 1,
           ia_estado = case when ia_tentativas + 1 >= 3 then 'indisponivel' else 'pendente' end,
           ia_nota = left(p_nota, 300), atualizado_em = now()
     where id = e.id returning ia_estado into v_estado;
    return v_estado;
  end if;
  if p_resultado = 'indisponivel' or nullif(trim(p_mensagem), '') is null then
    update estimulos_mensais set ia_estado = 'indisponivel', ia_nota = left(coalesce(p_nota, 'Sem mensagem'), 300),
                                 atualizado_em = now() where id = e.id;
    return 'indisponivel';
  end if;
  if p_resultado <> 'analisada' then raise exception 'resultado_invalido' using errcode = 'P0001'; end if;
  update estimulos_mensais
     set ia_estado = 'analisada', ia_mensagem = left(trim(p_mensagem), 600), ia_nota = left(p_nota, 300), atualizado_em = now()
   where id = e.id;
  return 'analisada';
end $$;

-- Análise de novo (depois de configurar a chave, por exemplo)
create or replace function pedir_nova_analise(p_tipo text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cozinha uuid;
begin
  if p_tipo = 'reclamacao' then
    select cozinha_id into v_cozinha from reclamacoes where id = p_id and deletado_em is null and estado = 'aberta';
    if not found then raise exception 'reclamacao_inexistente' using errcode = 'P0001'; end if;
    if not pode_tratar_reclamacao(v_cozinha) then raise exception 'sem_permissao' using errcode = '42501'; end if;
    update reclamacoes set ia_estado = 'pendente', ia_tentativas = 0, ia_nota = null, atualizado_em = now() where id = p_id;
  elsif p_tipo = 'estimulo' then
    if not tem_permissao('equipa.gerir') then raise exception 'sem_permissao' using errcode = '42501'; end if;
    update estimulos_mensais set ia_estado = 'pendente', ia_tentativas = 0, ia_nota = null, atualizado_em = now()
     where id = p_id and deletado_em is null and estado = 'proposto';
    if not found then raise exception 'estimulo_inexistente' using errcode = 'P0001'; end if;
  else
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
end $$;
revoke execute on function pedir_nova_analise(text, uuid) from public, anon;
grant execute on function pedir_nova_analise(text, uuid) to authenticated;

-- Agenda a análise automática de 2 em 2 minutos (mesmo segredo do envio de avisos)
create or replace function agendar_analises(p_url text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 'pg_cron e pg_net têm de estar activos';
  end if;
  execute format($f$select cron.schedule('analisar-ia', '*/2 * * * *', %L)$f$,
    format('select net.http_post(url := %L, body := ''{}''::jsonb, timeout_milliseconds := 120000, headers := jsonb_build_object('
           '''Content-Type'', ''application/json'', ''x-envio-segredo'', '
           '(select valor from public.segredos_servidor where chave = ''envio_notificacoes'')))', p_url));
  return 'agendado';
end $$;

revoke execute on function reservar_analises(int) from public, anon, authenticated;
revoke execute on function registar_analise_reclamacao(uuid, text, jsonb, text) from public, anon, authenticated;
revoke execute on function registar_mensagem_estimulo(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function agendar_analises(text) from public, anon, authenticated;
revoke execute on function nome_mes(int) from public, anon;
grant execute on function nome_mes(int) to authenticated;
grant execute on function reservar_analises(int) to service_role;
grant execute on function registar_analise_reclamacao(uuid, text, jsonb, text) to service_role;
grant execute on function registar_mensagem_estimulo(uuid, text, text, text) to service_role;

