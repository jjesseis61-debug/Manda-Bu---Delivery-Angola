-- =============================================================================
-- Convida e Ganha: validade do saldo (12 meses) + relatório dos saldos expirados
-- -----------------------------------------------------------------------------
-- Regra (decisão do dono, 15/11/2026): cada ganho vale durante parametros.validade_saldo_meses
-- (12) a contar de quando foi confirmado. O que se usa (refeições) ou levanta gasta primeiro os
-- ganhos MAIS ANTIGOS. Só expira a parte dos ganhos antigos que ainda não foi usada:
--     a expirar = ganhos confirmados há mais de 12 meses − tudo o que já foi usado/levantado − já expirado
-- Um job diário (03h10 de Luanda) regista as expirações em expiracoes_saldo (o saldo desce) e avisa:
--   * aviso_expiracao_dias (30) antes: "daqui a N dias expiram X Kz — usa ou levanta";
--   * no dia: "expiraram X Kz".
-- Nada é apagado: os ganhos e pagamentos ficam como estão; a expiração é um movimento à parte.
-- Relatório (operador, indicacoes.verificar): tudo o que expirou num período, por mês e por cliente,
-- e o que vai expirar nos próximos 30/60/90 dias.
-- =============================================================================

alter table parametros
  add column if not exists validade_saldo_meses int not null default 12
    check (validade_saldo_meses between 1 and 60),
  add column if not exists aviso_expiracao_dias int not null default 30
    check (aviso_expiracao_dias between 0 and 90);
comment on column parametros.validade_saldo_meses is 'Meses de validade de cada ganho do Convida (a contar da confirmação)';
comment on column parametros.aviso_expiracao_dias is 'Dias antes da expiração em que se avisa o cliente (0 = não avisa)';

create table if not exists expiracoes_saldo (
  id              uuid primary key default gen_random_uuid(),
  dispositivo_id  text not null default 'servidor',
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  sincronizado_em timestamptz,
  deletado_em     timestamptz,
  indicador_id    uuid not null references clientes(id),
  valor           int not null check (valor > 0),
  -- Ganhos confirmados até esta data (inclusive) já passaram a validade
  ganhos_ate      timestamptz not null,
  ganhos_antigos  int not null,   -- soma desses ganhos
  usado           int not null,   -- usado/levantado/expirado antes (gasta primeiro os antigos)
  saldo_antes     int not null
);
create index if not exists expiracoes_saldo_indicador_idx on expiracoes_saldo (indicador_id, criado_em);
create index if not exists expiracoes_saldo_data_idx on expiracoes_saldo (criado_em);
alter table expiracoes_saldo enable row level security;
drop policy if exists ler on expiracoes_saldo;
create policy ler on expiracoes_saldo for select to authenticated
  using (indicador_id = (select cliente_actual()) or (select tem_permissao('indicacoes.verificar')));
drop trigger if exists trg_0_so_servidor on expiracoes_saldo;
create trigger trg_0_so_servidor before insert or update or delete on expiracoes_saldo
  for each row execute function bloquear_escrita_dispositivo();
comment on table expiracoes_saldo is 'Saldo do Convida que expirou (ganhos com mais de validade_saldo_meses ainda por usar)';

-- Quanto do saldo terá expirado no instante p_quando (regra: os mais antigos gastam-se primeiro)
create or replace function saldo_a_expirar(p_indicador uuid, p_quando timestamptz default now())
returns int language sql stable security definer set search_path = public as $$
  with p as (select validade_saldo_meses as m from parametros where unico),
  antigos as (
    select coalesce(sum(g.valor), 0) as v
      from ganhos_indicacao g, p
     where g.indicador_id = p_indicador and g.estado in ('confirmado', 'pago') and g.deletado_em is null
       and coalesce(g.confirmado_em, g.criado_em) + make_interval(months => p.m) <= p_quando
  ),
  usado as (
    select (select coalesce(sum(valor), 0) from pagamentos_indicacao
             where indicador_id = p_indicador and estado in ('pedido', 'aprovado', 'pago') and deletado_em is null)
         + (select coalesce(sum(valor), 0) from expiracoes_saldo
             where indicador_id = p_indicador and deletado_em is null) as v
  )
  -- Só o próprio cliente, quem verifica o Convida, ou o servidor (job, sem sessão)
  select case when auth.uid() is null or p_indicador = cliente_actual() or tem_permissao('indicacoes.verificar')
              then greatest(0, (select v from antigos) - (select v from usado))::int
              else 0 end;
$$;
revoke execute on function saldo_a_expirar(uuid, timestamptz) from public, anon;
grant  execute on function saldo_a_expirar(uuid, timestamptz) to authenticated;

-- Data em que o próximo ganho ainda por usar expira (null se nada por usar)
create or replace function proxima_expiracao_saldo(p_indicador uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  with p as (select validade_saldo_meses as m from parametros where unico),
  consumido as (
    select (select coalesce(sum(valor), 0) from pagamentos_indicacao
             where indicador_id = p_indicador and estado in ('pedido', 'aprovado', 'pago') and deletado_em is null)
         + (select coalesce(sum(valor), 0) from expiracoes_saldo
             where indicador_id = p_indicador and deletado_em is null) as v
  ),
  g as (
    select coalesce(confirmado_em, criado_em) as quando,
           sum(valor) over (order by coalesce(confirmado_em, criado_em), id) as acumulado
      from ganhos_indicacao
     where indicador_id = p_indicador and estado in ('confirmado', 'pago') and deletado_em is null
  )
  select case when auth.uid() is null or p_indicador = cliente_actual() or tem_permissao('indicacoes.verificar')
              then (select min(g.quando) + make_interval(months => (select m from p))
                      from g where g.acumulado > (select v from consumido)) end;
$$;
revoke execute on function proxima_expiracao_saldo(uuid) from public, anon;
grant  execute on function proxima_expiracao_saldo(uuid) to authenticated;

-- O saldo disponível desconta o que expirou
create or replace function saldo_disponivel_de(p_indicador uuid)
returns int language sql stable security definer set search_path = public as $$
  select ((select coalesce(sum(valor), 0) from ganhos_indicacao
            where indicador_id = p_indicador and estado in ('confirmado','pago')
              and deletado_em is null)
        - (select coalesce(sum(valor), 0) from pagamentos_indicacao
            where indicador_id = p_indicador and estado in ('pedido','aprovado','pago')
              and deletado_em is null)
        - (select coalesce(sum(valor), 0) from expiracoes_saldo
            where indicador_id = p_indicador and deletado_em is null))::int;
$$;

-- A vista do saldo (app do cliente): desconta o expirado e diz quanto expira em breve e quando
create or replace view saldo_indicacao with (security_invoker = true) as
 select c.cliente_id as indicador_id,
    ((( select coalesce(sum(g.valor), 0::bigint)
           from ganhos_indicacao g
          where g.indicador_id = c.cliente_id and g.estado = any (array['confirmado'::text, 'pago'::text]) and g.deletado_em is null))
     - (( select coalesce(sum(pg.valor), 0::bigint)
           from pagamentos_indicacao pg
          where pg.indicador_id = c.cliente_id and pg.estado = any (array['pedido'::text, 'aprovado'::text, 'pago'::text]) and pg.deletado_em is null))
     - (( select coalesce(sum(e.valor), 0::bigint)
           from expiracoes_saldo e
          where e.indicador_id = c.cliente_id and e.deletado_em is null)))::integer as saldo_disponivel,
    (( select coalesce(sum(g.valor), 0::bigint)
           from ganhos_indicacao g
          where g.indicador_id = c.cliente_id and g.estado = 'em_verificacao'::text and g.deletado_em is null))::integer as em_verificacao,
    (( select coalesce(sum(g.valor), 0::bigint)
           from ganhos_indicacao g
          where g.indicador_id = c.cliente_id and g.estado = any (array['confirmado'::text, 'pago'::text]) and g.confirmado_em >= inicio_dia_luanda()))::integer as ganho_hoje,
    (( select coalesce(sum(g.valor), 0::bigint)
           from ganhos_indicacao g
          where g.indicador_id = c.cliente_id and g.estado = any (array['confirmado'::text, 'pago'::text]) and g.confirmado_em >= inicio_semana_luanda()))::integer as ganho_semana,
    (( select coalesce(sum(pg.valor), 0::bigint)
           from pagamentos_indicacao pg
          where pg.indicador_id = c.cliente_id and pg.estado = 'pago'::text))::integer as total_recebido,
    saldo_a_expirar(c.cliente_id, now() + make_interval(days => greatest((select aviso_expiracao_dias from parametros where unico), 30))) as a_expirar_em_breve,
    proxima_expiracao_saldo(c.cliente_id) as proxima_expiracao,
    (( select coalesce(sum(e.valor), 0::bigint)
           from expiracoes_saldo e
          where e.indicador_id = c.cliente_id and e.deletado_em is null))::integer as total_expirado
   from codigos_indicacao c
  where c.deletado_em is null;

-- -----------------------------------------------------------------------------
-- Job diário: regista as expirações e avisa os clientes
-- -----------------------------------------------------------------------------
create or replace function job_expirar_saldos() returns int
language plpgsql security definer set search_path = public as $$
declare
  p     parametros%rowtype;
  c     record;
  v     int;
  v_ant int;
  v_us  int;
  v_brv int;
  v_qd  timestamptz;
  n     int := 0;
begin
  select * into p from parametros where unico;
  for c in select distinct g.indicador_id as id from ganhos_indicacao g
            where g.estado in ('confirmado', 'pago') and g.deletado_em is null loop
    v := saldo_a_expirar(c.id, now());
    if v > 0 then
      select coalesce(sum(valor), 0) into v_ant from ganhos_indicacao
       where indicador_id = c.id and estado in ('confirmado', 'pago') and deletado_em is null
         and coalesce(confirmado_em, criado_em) + make_interval(months => p.validade_saldo_meses) <= now();
      v_us := v_ant - v;
      insert into expiracoes_saldo (indicador_id, valor, ganhos_ate, ganhos_antigos, usado, saldo_antes)
      values (c.id, v, now() - make_interval(months => p.validade_saldo_meses), v_ant, v_us, saldo_disponivel_de(c.id));
      insert into notificacoes_fila (cliente_id, codigo, dados)
      values (c.id, 'N31', jsonb_build_object(
        'titulo', 'Parte do teu saldo expirou',
        'corpo', format('Expiraram %s do teu saldo do Convida e Ganha (ganhos com mais de %s meses que não usaste). Usa ou levanta o resto antes de expirar.',
                        formatar_kz(v), p.validade_saldo_meses),
        'tipo', 'saldo_expirado', 'link', '/convida'));
      perform registar_auditoria('saldo_expirado', 'clientes', c.id, jsonb_build_object('valor', v));
      n := n + 1;
    end if;
    -- Aviso antes de expirar (uma vez por período de aviso)
    if p.aviso_expiracao_dias > 0 then
      v_brv := saldo_a_expirar(c.id, now() + make_interval(days => p.aviso_expiracao_dias));
      if v_brv > 0 and not exists (
           select 1 from notificacoes_fila
            where cliente_id = c.id and codigo = 'N31' and dados ->> 'tipo' = 'saldo_a_expirar'
              and criado_em > now() - make_interval(days => p.aviso_expiracao_dias)) then
        v_qd := proxima_expiracao_saldo(c.id);
        insert into notificacoes_fila (cliente_id, codigo, dados)
        values (c.id, 'N31', jsonb_build_object(
          'titulo', 'O teu saldo vai expirar',
          'corpo', format('%s do teu saldo do Convida e Ganha expiram a partir de %s. Usa em refeições ou levanta antes disso.',
                          formatar_kz(v_brv), to_char(v_qd at time zone 'Africa/Luanda', 'DD/MM/YYYY')),
          'tipo', 'saldo_a_expirar', 'valor', v_brv, 'link', '/convida'));
      end if;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function job_expirar_saldos() from public, anon, authenticated;

-- 03h10 de Luanda = 02h10 UTC
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_expirar_saldos', '10 2 * * *', 'select public.job_expirar_saldos()');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Relatório dos saldos expirados (operador)
-- -----------------------------------------------------------------------------
create or replace function relatorio_saldos_expirados(p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  r     jsonb;
begin
  perform exigir_permissao('indicacoes.verificar');
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 731 then
    raise exception 'periodo_invalido' using errcode = 'P0001';
  end if;
  with e as (
    select x.*, c.nome, c.telefone, ci.codigo, ci.nivel,
           exists (select 1 from notificacoes_fila n where n.cliente_id = x.indicador_id and n.codigo = 'N31'
                     and n.dados ->> 'tipo' = 'saldo_a_expirar' and n.criado_em < x.criado_em) as avisado
      from expiracoes_saldo x
      join clientes c on c.id = x.indicador_id
      left join codigos_indicacao ci on ci.cliente_id = x.indicador_id
     where x.deletado_em is null and x.criado_em >= v_ini and x.criado_em < v_fim
  ),
  ind as (select distinct g.indicador_id as id from ganhos_indicacao g where g.estado in ('confirmado', 'pago') and g.deletado_em is null),
  proj as (
    select i.id,
           saldo_a_expirar(i.id, now() + interval '30 days') as d30,
           saldo_a_expirar(i.id, now() + interval '60 days') as d60,
           saldo_a_expirar(i.id, now() + interval '90 days') as d90
      from ind i
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
    'validade_meses', (select validade_saldo_meses from parametros where unico),
    'resumo', (select jsonb_build_object(
                 'total', coalesce(sum(valor), 0), 'expiracoes', count(*), 'clientes', count(distinct indicador_id),
                 'media', coalesce(round(avg(valor)), 0), 'maior', coalesce(max(valor), 0),
                 'avisados', count(*) filter (where avisado)) from e),
    'por_mes', coalesce((select jsonb_agg(jsonb_build_object('mes', m, 'valor', v, 'clientes', n) order by m)
                           from (select to_char(criado_em at time zone 'Africa/Luanda', 'YYYY-MM') as m,
                                        sum(valor) as v, count(distinct indicador_id) as n
                                   from e group by 1) t), '[]'),
    'lista', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', id, 'data', criado_em, 'cliente_id', indicador_id, 'nome', nome, 'telefone', telefone,
                          'codigo', codigo, 'nivel', nivel, 'valor', valor, 'ganhos_ate', ganhos_ate,
                          'ganhos_antigos', ganhos_antigos, 'usado', usado, 'saldo_antes', saldo_antes,
                          'avisado', avisado) order by criado_em desc)
                         from (select * from e order by criado_em desc limit 1000) l), '[]'),
    'a_expirar', (select jsonb_build_object(
                    'd30', coalesce(sum(d30), 0), 'clientes_30', count(*) filter (where d30 > 0),
                    'd60', coalesce(sum(d60), 0), 'clientes_60', count(*) filter (where d60 > 0),
                    'd90', coalesce(sum(d90), 0), 'clientes_90', count(*) filter (where d90 > 0)) from proj),
    'a_expirar_lista', coalesce((select jsonb_agg(jsonb_build_object(
                          'cliente_id', p.id, 'nome', c.nome, 'telefone', c.telefone, 'valor', p.d90,
                          'em_30_dias', p.d30, 'expira_em', proxima_expiracao_saldo(p.id),
                          'saldo', saldo_disponivel_de(p.id)) order by p.d90 desc)
                         from (select * from proj where d90 > 0 order by d90 desc limit 200) p
                         join clientes c on c.id = p.id), '[]'),
    'saldo_activo_total', (select coalesce(sum(saldo_disponivel_de(i.id)), 0) from ind i),
    'expirado_sempre', (select coalesce(sum(valor), 0) from expiracoes_saldo where deletado_em is null)
  ) into r;
  return r;
end $$;
revoke execute on function relatorio_saldos_expirados(date, date) from public, anon;
grant  execute on function relatorio_saldos_expirados(date, date) to authenticated;
