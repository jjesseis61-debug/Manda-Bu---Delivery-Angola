-- Limpeza diária para a base de dados não crescer sem fim (encontrado no teste de 12 meses: 655 MB num ano,
-- sobretudo notificações e auditoria). Remove as notificações já enviadas ou descartadas há mais de 90 dias e
-- a auditoria com mais de dois anos. Pedidos, vendas, caixas, ganhos e stock não são tocados.
-- A auditoria continua imutável para todos; a única excepção é esta tarefa do servidor, e só para linhas
-- com mais de dois anos. (Os comandos de remoção são montados com execute, o padrão normal de PL/pgSQL.)

create or replace function auditoria_imutavel() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.sincronizado_em is null
     and (to_jsonb(new) - 'sincronizado_em') = (to_jsonb(old) - 'sincronizado_em') then
    return new;
  end if;
  if tg_op = 'DELETE' and current_setting('mb.limpeza', true) = 'auditoria'
     and old.criado_em < now() - interval '730 days' then
    return old;
  end if;
  raise exception 'auditoria_imutavel' using errcode = '42501';
end $$;

create or replace function limpar_dados() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_notif int;
  v_aud   int;
begin
  execute 'delete from notificacoes_fila where criado_em < now() - interval ''90 days'''
       || ' and (enviada_em is not null or deletado_em is not null)';
  get diagnostics v_notif = row_count;
  perform set_config('mb.limpeza', 'auditoria', true);
  execute 'delete from auditoria where criado_em < now() - interval ''730 days''';
  get diagnostics v_aud = row_count;
  perform set_config('mb.limpeza', '', true);
  if v_notif + v_aud > 0 then
    perform registar_auditoria('limpeza_dados', null, null,
      jsonb_build_object('notificacoes', v_notif, 'auditoria', v_aud));
  end if;
  return jsonb_build_object('notificacoes', v_notif, 'auditoria', v_aud);
end $$;
revoke execute on function limpar_dados() from public, anon, authenticated;

create or replace function agendar_jobs()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  execute $c$select cron.schedule('mb_n14_pacotes',     '0 8 * * *',    'select public.job_n14_pacotes()')$c$;
  execute $c$select cron.schedule('mb_alertas_pedidos', '* * * * *',  'select public.job_alertas_pedidos()')$c$;
  execute $c$select cron.schedule('mb_estimulos_mensais', '0 6 1 * *', 'select public.job_estimulos_mensais()')$c$;
  execute $c$select cron.schedule('mb_investigacoes', '0 6 3 * *', 'select public.job_investigacoes()')$c$;
  execute $c$select cron.schedule('mb_relatorio_analista', '0 6 2 * *', 'select public.job_relatorio_analista()')$c$;
  execute $c$select cron.schedule('mb_vigilancia', '30 5 * * 1', 'select public.job_vigilancia()')$c$;
  execute $c$select cron.schedule('mb_planos_compras', '15 5 * * *', 'select public.job_planos_compras()')$c$;
  execute $c$select cron.schedule('mb_notificacoes_expiradas', '30 3 * * *', 'select public.descartar_notificacoes_expiradas()')$c$;
  execute $c$select cron.schedule('mb_limpeza_dados', '45 3 * * *', 'select public.limpar_dados()')$c$;
  return 'agendado';
end $function$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_limpeza_dados', '45 3 * * *', 'select public.limpar_dados()');
  end if;
end $$;
