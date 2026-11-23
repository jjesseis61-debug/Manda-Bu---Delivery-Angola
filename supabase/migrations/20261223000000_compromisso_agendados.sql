-- Compromisso nos pedidos agendados (Cialdini: compromisso activo) e medição das ausências.
--  1. O estafeta regista «cliente ausente / não atendeu» (a «falta à consulta» da entrega): até aqui
--     não se media.
--  2. Teste com grupo de controlo (interruptor 'compromisso_agendados'): no grupo A, o cliente confirma
--     com um toque «Vou estar em <morada> às <hora>»; o grupo B não vê a pergunta.
--  3. Lembrete 1 h antes para os dois grupos; no A repete as palavras do próprio cliente.
--  4. Resultado por grupo: agendados, confirmados, ausências e entregues.

insert into funcionalidades (chave, activa, dispositivo_id) values ('compromisso_agendados', false, 'servidor')
on conflict (chave) do nothing;

alter table pedidos add column if not exists presenca_confirmada_em timestamptz;

-- ------------------------------------------------------------------ 1. ausências
create table if not exists entregas_ausencias (
  id             uuid primary key default gen_random_uuid(),
  pedido_id      uuid not null references pedidos(id),
  funcionario_id uuid references funcionarios(id),
  nota           text,
  criado_em      timestamptz not null default now()
);
create index if not exists entregas_ausencias_pedido_idx on entregas_ausencias (pedido_id);
create index if not exists entregas_ausencias_funcionario_idx on entregas_ausencias (funcionario_id);
alter table entregas_ausencias enable row level security;
revoke all on entregas_ausencias from public, anon, authenticated;

-- O estafeta chegou e o cliente não está ou não atende: fica registado (o pedido continua em entrega;
-- o operador decide se volta, espera ou cancela). Devolve quantas tentativas falhadas tem o pedido.
create or replace function registar_ausencia(p_pedido uuid, p_nota text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  p pedidos;
begin
  select * into p from pedidos where id = p_pedido and deletado_em is null;
  if not found then raise exception 'pedido_inexistente' using errcode = 'P0001'; end if;
  if not (tem_permissao('entregas.registar') or tem_permissao('pedidos.gerir')) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'entregas.registar';
  end if;
  if p.estado <> 'em_entrega' then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
  insert into entregas_ausencias (pedido_id, funcionario_id, nota)
  values (p.id, funcionario_actual(), nullif(trim(coalesce(p_nota, '')), ''));
  perform registar_auditoria('cliente_ausente', 'pedidos', p.id, jsonb_build_object('nota', p_nota));
  return (select count(*)::int from entregas_ausencias where pedido_id = p.id);
end $$;
revoke execute on function registar_ausencia(uuid, text) from public, anon;
grant execute on function registar_ausencia(uuid, text) to authenticated;

-- ------------------------------------------------------------------ 2. compromisso do cliente
-- Grupo do cliente no teste ('A' vê a pergunta, 'B' não), ou null com o interruptor desligado
create or replace function meu_grupo_compromisso() returns text
language sql stable security definer set search_path = public as $$
  select case when cliente_actual() is not null and funcionalidade_activa('compromisso_agendados')
              then variante_experiencia('compromisso_agendados', cliente_actual()) end
$$;
revoke execute on function meu_grupo_compromisso() from public, anon;
grant execute on function meu_grupo_compromisso() to authenticated;

-- «Sim, vou estar»: só no próprio pedido agendado, ainda por entregar
create or replace function confirmar_presenca(p_pedido uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if cliente_actual() is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  update pedidos set presenca_confirmada_em = coalesce(presenca_confirmada_em, now())
   where id = p_pedido and cliente_id = cliente_actual() and deletado_em is null
     and agendado_para is not null and estado in ('pendente', 'confirmado', 'em_preparacao');
  if not found then raise exception 'pedido_nao_agendado' using errcode = 'P0001'; end if;
end $$;
revoke execute on function confirmar_presenca(uuid) from public, anon;
grant execute on function confirmar_presenca(uuid) to authenticated;

-- ------------------------------------------------------------------ 3. lembrete 1 h antes
create or replace function job_lembrete_agendados() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  if not funcionalidade_activa('compromisso_agendados') then return 0; end if;
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select x.cliente_id, 'N31',
         jsonb_build_object(
           'tipo', 'lembrete_agendado', 'pedido_id', x.id,
           'titulo', 'O teu pedido chega daqui a 1 hora',
           'corpo', case when x.presenca_confirmada_em is not null
                         then format('Disseste que estarias em %s às %s. Se mudou, avisa-nos na app.', x.local, x.hora)
                         else format('O teu pedido chega às %s em %s.', x.hora, x.local) end)
    from (select p.id, p.cliente_id, p.presenca_confirmada_em,
                 to_char(p.agendado_para at time zone 'Africa/Luanda', 'HH24"h"MI') as hora,
                 coalesce(nullif(pe.referencia, ''), z.nome, 'casa') as local
            from pedidos p
            left join pontos_entrega pe on pe.id = p.ponto_entrega_id
            left join zonas z on z.id = pe.zona_id
           where p.deletado_em is null and p.agendado_para is not null and p.grupo_id is null
             and p.estado in ('pendente', 'confirmado', 'em_preparacao')
             and p.agendado_para between now() + interval '45 minutes' and now() + interval '75 minutes'
             and not exists (select 1 from notificacoes_fila n
                              where n.codigo = 'N31' and n.dados ->> 'tipo' = 'lembrete_agendado'
                                and n.dados ->> 'pedido_id' = p.id::text)) x;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function job_lembrete_agendados() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_lembrete_agendados', '*/5 * * * *', 'select public.job_lembrete_agendados()');
  end if;
end $$;

-- ------------------------------------------------------------------ 4. resultado do teste
create or replace function resultado_compromisso(p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao('analista.usar') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'analista.usar';
  end if;
  return coalesce((
    select jsonb_object_agg(g.grupo, jsonb_build_object(
             'agendados', g.agendados, 'confirmados', g.confirmados,
             'com_ausencia', g.com_ausencia, 'entregues', g.entregues, 'cancelados', g.cancelados))
      from (select variante_experiencia('compromisso_agendados', p.cliente_id) as grupo,
                   count(*)::int as agendados,
                   count(*) filter (where p.presenca_confirmada_em is not null)::int as confirmados,
                   count(*) filter (where exists (select 1 from entregas_ausencias a where a.pedido_id = p.id))::int as com_ausencia,
                   count(*) filter (where p.estado = 'entregue_pago')::int as entregues,
                   count(*) filter (where p.estado = 'cancelado')::int as cancelados
              from pedidos p
             where p.deletado_em is null and p.agendado_para is not null and p.grupo_id is null
               and (p.agendado_para at time zone 'Africa/Luanda')::date between p_de and p_ate
             group by 1) g), '{}'::jsonb);
end $$;
revoke execute on function resultado_compromisso(date, date) from public, anon;
grant execute on function resultado_compromisso(date, date) to authenticated;
