-- =============================================================================
-- Embaixador — fecho da Fase 2: parabéns ao subir de nível + descida SUAVE
-- -----------------------------------------------------------------------------
--  1. Aviso N43 ("Subiste de nível!") sempre que o nível de um cliente sobe — pela
--     promoção automática (processar_ganho_indicacao) ou à mão (definir_nivel_indicador).
--  2. Descida suave (job semanal, segunda às 05h de Luanda). "Activos" contam só amigos com
--     ganho confirmado e vínculo vivo; como os vínculos expiram, um embaixador pode deixar de
--     ter amigos activos. Para não ser injusto nem dar "efeito ioiô":
--       * carência: só se avalia quem está no nível há pelo menos despromocao_carencia_dias (30);
--       * margem: só desce quem ficou abaixo de despromocao_margem_pct (80%) do limiar do nível
--         (ex.: Embaixador com limiar 5 só desce com menos de 4 activos);
--       * um degrau de cada vez (Ouro → Embaixador; nova carência antes de qualquer outra descida);
--       * aviso N44, simpático, a dizer quantos amigos faltam para voltar.
--     Ganhos já confirmados e o valor garantido de cada ligação NÃO mudam.
--     Desliga-se pondo parametros.despromocao_activa = false.
--  3. Bónus de boas-vindas: já existe (parametros.bonus_boas_vindas, 0 = desligado).
-- =============================================================================

alter table parametros
  add column if not exists despromocao_activa        boolean not null default true,
  add column if not exists despromocao_carencia_dias int not null default 30
    check (despromocao_carencia_dias between 7 and 365),
  add column if not exists despromocao_margem_pct    int not null default 80
    check (despromocao_margem_pct between 50 and 100);
comment on column parametros.despromocao_activa is 'Descida suave de nível do embaixador (job semanal) ligada?';
comment on column parametros.despromocao_carencia_dias is 'Dias mínimos num nível antes de poder descer';
comment on column parametros.despromocao_margem_pct is 'Só desce quem tem menos do que esta % do limiar do nível';

-- Desde quando o cliente está no nível actual (para a carência)
alter table codigos_indicacao add column if not exists nivel_desde timestamptz not null default now();

-- Indicados ACTIVOS de um indicador (a mesma regra da promoção automática)
create or replace function indicados_activos(p_indicador uuid)
returns int language sql stable set search_path = public as $$
  select count(distinct g.indicado_id)::int
    from ganhos_indicacao g
    join ligacoes_indicacao l
      on l.indicado_id = g.indicado_id and l.indicador_id = g.indicador_id
     and l.deletado_em is null
   where g.indicador_id = p_indicador
     and g.estado in ('confirmado', 'pago')
     and (l.expira_em is null or l.expira_em > now());
$$;
revoke execute on function indicados_activos(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 1. Mudança de nível → actualiza nivel_desde e avisa o cliente (N43 sobe / N44 desce)
-- -----------------------------------------------------------------------------
create or replace function aviso_mudanca_nivel()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p        parametros%rowtype;
  r_old    int := case old.nivel when 'ouro' then 2 when 'embaixador' then 1 else 0 end;
  r_new    int := case new.nivel when 'ouro' then 2 when 'embaixador' then 1 else 0 end;
  v_activos int;
begin
  if new.nivel is not distinct from old.nivel then
    return new;
  end if;
  new.nivel_desde := now();
  select * into p from parametros where unico;
  if r_new > r_old then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (new.cliente_id, 'N43', jsonb_build_object(
      'nivel', new.nivel,
      'ganho_por_pedido', case new.nivel when 'ouro' then p.ganho_por_pedido_ouro
                                         else p.ganho_por_pedido_embaixador end,
      'limiar_ouro', p.limiar_ouro));
  else
    v_activos := indicados_activos(new.cliente_id);
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (new.cliente_id, 'N44', jsonb_build_object(
      'nivel', new.nivel,
      'nivel_anterior', old.nivel,
      'activos', v_activos,
      'faltam', greatest(1, (case old.nivel when 'ouro' then p.limiar_ouro else p.limiar_embaixador end) - v_activos)));
  end if;
  return new;
end $$;
revoke execute on function aviso_mudanca_nivel() from public, anon, authenticated;

drop trigger if exists trg_aviso_mudanca_nivel on codigos_indicacao;
create trigger trg_aviso_mudanca_nivel
  before update of nivel on codigos_indicacao
  for each row execute function aviso_mudanca_nivel();

-- -----------------------------------------------------------------------------
-- 2. Descida suave (um degrau, com carência e margem)
-- -----------------------------------------------------------------------------
create or replace function job_despromocao_embaixador() returns int
language plpgsql security definer set search_path = public as $$
declare
  p      parametros%rowtype;
  c      record;
  v_n    int;
  v_novo text;
  v_tot  int := 0;
begin
  select * into p from parametros where unico;
  if not p.despromocao_activa then
    return 0;
  end if;
  for c in
    select ci.cliente_id, ci.nivel
      from codigos_indicacao ci
     where ci.deletado_em is null
       and ci.nivel in ('embaixador', 'ouro')
       and ci.nivel_desde < now() - make_interval(days => p.despromocao_carencia_dias)
  loop
    v_n := indicados_activos(c.cliente_id);
    v_novo := null;
    if c.nivel = 'ouro' and v_n < ceil(p.limiar_ouro * p.despromocao_margem_pct / 100.0) then
      v_novo := 'embaixador';
    elsif c.nivel = 'embaixador' and v_n < ceil(p.limiar_embaixador * p.despromocao_margem_pct / 100.0) then
      v_novo := 'normal';
    end if;
    if v_novo is not null then
      update codigos_indicacao set nivel = v_novo, atualizado_em = now() where cliente_id = c.cliente_id;
      perform registar_auditoria('nivel_indicador_despromovido', 'codigos_indicacao', c.cliente_id,
                                 jsonb_build_object('de', c.nivel, 'para', v_novo, 'indicados_activos', v_n));
      v_tot := v_tot + 1;
    end if;
  end loop;
  return v_tot;
end $$;
revoke execute on function job_despromocao_embaixador() from public, anon, authenticated;

-- Segunda-feira às 05h de Luanda = 04h UTC
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_despromocao_embaixador', '0 4 * * 1', 'select public.job_despromocao_embaixador()');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Texto, envio e interruptor dos avisos N43/N44 (acrescentados às definições actuais)
-- -----------------------------------------------------------------------------
do $$
declare
  v_def  text;
  v_novo text;
begin
  -- Já aplicado (migração corrida duas vezes): não faz nada
  if position($s$'N43'$s$ in pg_get_functiondef('notificacoes_por_enviar(integer)'::regprocedure)) > 0 then
    return;
  end if;

  v_def := pg_get_functiondef('texto_notificacao(text, jsonb)'::regprocedure);
  v_novo := replace(v_def,
    $s$when p_codigo = 'N40' then 'Novo código de login'$s$,
    $s$when p_codigo = 'N40' then 'Novo código de login' when p_codigo = 'N43' then '🎉 Subiste de nível!' when p_codigo = 'N44' then 'O teu nível foi ajustado'$s$);
  v_novo := replace(v_novo,
    $s$when 'N31' then p_dados ->> 'corpo'$s$,
    $s$when 'N43' then case when p_dados ->> 'nivel' = 'ouro'
                                then format('Parabéns, és Embaixador Ouro! Ganhas %s por cada pedido dos teus amigos e os teus ganhos já não esperam pela verificação semanal.',
                                            formatar_kz((p_dados ->> 'ganho_por_pedido')::numeric))
                                else format('Parabéns, és Embaixador! Agora ganhas %s por cada pedido dos teus amigos. Com %s amigos activos chegas a Ouro.',
                                            formatar_kz((p_dados ->> 'ganho_por_pedido')::numeric),
                                            coalesce(p_dados ->> 'limiar_ouro', '30')) end
           when 'N44' then format('Passaste a %s porque tens %s amigo(s) activo(s) neste momento. Faltam só %s para voltares a %s. Os ganhos que já tens não mudam.',
                                  case p_dados ->> 'nivel' when 'embaixador' then 'Embaixador' else 'nível normal' end,
                                  coalesce(p_dados ->> 'activos', '0'),
                                  coalesce(p_dados ->> 'faltam', '1'),
                                  case p_dados ->> 'nivel_anterior' when 'ouro' then 'Ouro' else 'Embaixador' end)
           when 'N31' then p_dados ->> 'corpo'$s$);
  if v_novo = v_def or (length(v_novo) - length(v_def)) < 400 then
    raise exception 'N43: texto_notificacao não tem o formato esperado';
  end if;
  execute v_novo;

  v_def := pg_get_functiondef('notificacoes_por_enviar(integer)'::regprocedure);
  v_novo := regexp_replace(v_def, $s$'N41',\s*'N42'\)$s$, $s$'N41', 'N42', 'N43', 'N44')$s$);
  if v_novo = v_def then
    raise exception 'N43: notificacoes_por_enviar não tem o formato esperado';
  end if;
  execute v_novo;

  -- Os avisos de nível são do Convida e Ganha: com o programa desligado, não saem
  v_def := pg_get_functiondef('funcionalidade_da_notificacao(text)'::regprocedure);
  v_novo := regexp_replace(v_def, $s$'N6',\s*'N8'\)$s$, $s$'N6','N8','N43','N44')$s$);
  if v_novo = v_def then
    raise exception 'N43: funcionalidade_da_notificacao não tem o formato esperado';
  end if;
  execute v_novo;
end $$;
