-- Validade das notificações (análise de 1 de Outubro de 2026).
--
-- Até aqui uma notificação ficava na fila sem prazo: depois de uma paragem do
-- envio (Expo, pg_net, envio ainda por agendar) o lembrete do almoço (N5) podia
-- chegar à tarde e um aviso de grupo horas depois de o grupo fechar. Cada código
-- passa a ter uma validade; o que passou do prazo deixa de ser enviado e um job
-- diário tira-o da fila (deletado_em).

create or replace function notificacao_valida(p_codigo text, p_criado_em timestamptz) returns boolean
language sql stable set search_path = public as $$
  select p_criado_em > now() - case p_codigo
           when 'N5'  then interval '2 hours'    -- lembrete do almoço: 11h, só até às 13h
           when 'N10' then interval '3 hours'    -- colega aderiu ao grupo
           when 'N11' then interval '3 hours'    -- grupo fechado
           when 'N7'  then interval '24 hours'   -- destaques da semana
           when 'N9'  then interval '24 hours'   -- pedido para avaliar
           when 'N6'  then interval '48 hours'   -- ligação a expirar
           else            interval '7 days'     -- ganhos, levantamentos, reconhecimentos
         end;
$$;

comment on function notificacao_valida(text, timestamptz) is
  'Prazo de envio de cada notificação. Passado o prazo, notificacoes_por_enviar ignora-a e descartar_notificacoes_expiradas tira-a da fila.';

-- Igual à versão da I6, mais a validade
create or replace function notificacoes_por_enviar(p_limite integer default 100)
returns table (id uuid, cliente_id uuid, funcionario_id uuid, destino text, codigo text,
               titulo text, corpo text, dados jsonb, tokens text[])
language sql stable security definer set search_path = public as $$
  select n.id, n.cliente_id, n.funcionario_id,
         case when n.funcionario_id is not null then 'funcionario' else 'cliente' end,
         n.codigo, t.titulo, t.corpo, n.dados,
         coalesce((select array_agg(d.token order by d.atualizado_em desc) from dispositivos_push d
                    where d.activo and d.deletado_em is null
                      and (d.cliente_id = n.cliente_id or d.funcionario_id = n.funcionario_id)), '{}')
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
    left join preferencias_notificacao pn on pn.cliente_id = n.cliente_id and pn.deletado_em is null
   where n.enviada_em is null and n.deletado_em is null
     and n.codigo in ('N2', 'N3', 'N4', 'N5', 'N6', 'N7', 'N8', 'N9', 'N10', 'N11', 'N12')
     and notificacao_valida(n.codigo, n.criado_em)
     and funcionalidade_activa(funcionalidade_da_notificacao(n.codigo))
     and not (n.codigo = 'N5' and pn.lembrete_almoco is false)
     and not (n.codigo = 'N7' and pn.destaques is false)
     and not (n.codigo = 'N9' and exists (select 1 from avaliacoes a where a.pedido_id::text = n.dados ->> 'pedido_id'))
   order by n.criado_em
   limit greatest(coalesce(p_limite, 100), 1);
$$;

-- Tira da fila o que passou do prazo sem ser enviado
create or replace function descartar_notificacoes_expiradas() returns integer
language sql security definer set search_path = public as $$
  with u as (update notificacoes_fila
                set deletado_em = now(), atualizado_em = now(), dispositivo_id = 'servidor'
              where enviada_em is null and deletado_em is null
                and not notificacao_valida(codigo, criado_em)
             returning 1)
  select count(*)::int from u;
$$;

-- agendar_jobs(): os 6 jobs anteriores e a limpeza diária da fila (03h30 UTC)
create or replace function agendar_jobs() returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron_ausente';
  end if;
  execute $c$select cron.schedule('mb_contadores_zona', '0 * * * *',    'select public.job_contadores_zona()')$c$;
  execute $c$select cron.schedule('mb_n6_expiracao',    '0 7 * * *',    'select public.job_n6_expiracao()')$c$;
  execute $c$select cron.schedule('mb_n5_lembrete',     '0 10 * * 1-5', 'select public.job_n5_lembrete()')$c$;
  execute $c$select cron.schedule('mb_n7_destaques',    '0 7 * * 1',    'select public.job_n7_destaques()')$c$;
  execute $c$select cron.schedule('mb_n9_avaliacao',    '*/15 * * * *', 'select public.job_n9_avaliacao()')$c$;
  execute $c$select cron.schedule('mb_grupos',          '*/5 * * * *',  'select public.job_grupos()')$c$;
  execute $c$select cron.schedule('mb_notificacoes_expiradas', '30 3 * * *', 'select public.descartar_notificacoes_expiradas()')$c$;
  return 'agendado';
end $$;

revoke execute on function notificacao_valida(text, timestamptz)   from public, anon, authenticated;
revoke execute on function descartar_notificacoes_expiradas()       from public, anon, authenticated;
revoke execute on function agendar_jobs()                           from public, anon, authenticated;
revoke execute on function notificacoes_por_enviar(integer)         from public, anon, authenticated;
grant  execute on function notificacoes_por_enviar(integer)         to service_role;
