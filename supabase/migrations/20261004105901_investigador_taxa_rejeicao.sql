-- Investigador financeiro: os comprovativos rejeitados contam pela taxa (encontrado no teste de 12 meses).
-- Um só comprovativo rejeitado abria um caso (3 pontos, limite 3): com 1 % de rejeições normais, 14 dos 18
-- funcionários teriam um caso todos os meses. Agora toleram-se rejeições até 2 % dos comprovativos do
-- período; só as que passam disso pontuam (3 cada). Com poucos comprovativos nada é tolerado: 1 rejeitado
-- em 10 continua a abrir caso. Os outros sinais ficam iguais.

create or replace function sinais_financeiros(p_func uuid, p_inicio date, p_fim date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with comp as (
    select c.*,
           exists (select 1 from extratos e where e.deletado_em is null and e.estado in ('lido', 'manual')
                     and (c.criado_em at time zone 'Africa/Luanda')::date between e.periodo_inicio and e.periodo_fim) as coberto,
           exists (select 1 from extrato_movimentos m where m.comprovativo_id = c.id and m.deletado_em is null) as no_extrato
      from comprovativos_pagamento c
     where c.registado_por = p_func and c.deletado_em is null
       and (c.criado_em at time zone 'Africa/Luanda')::date between p_inicio and p_fim),
  cx as (
    select c.*, (c.fechamento ->> 'diferenca')::numeric as diferenca from caixa c
     where c.deletado_em is null and c.fechamento is not null and (c.fechamento ->> 'funcionario_id')::uuid = p_func
       and c.data between p_inicio and p_fim),
  s as (
    select (select count(*) from comp) comprovativos,
           (select coalesce(sum(valor), 0) from comp) valor_comprovativos,
           (select count(*) from comp where estado = 'rejeitado') rejeitados,
           (select count(*) from comp where ia_estado = 'diverge') nao_conferem,
           (select count(*) from comp where ia_estado = 'ilegivel') ilegiveis,
           (select count(*) from comp where coberto and not no_extrato and estado <> 'rejeitado') sem_extrato,
           (select coalesce(sum(valor), 0) from comp where coberto and not no_extrato and estado <> 'rejeitado') valor_sem_extrato,
           (select count(*) from cx) caixas_fechadas,
           (select count(*) from cx where diferenca <> 0) caixas_com_diferenca,
           (select coalesce(sum(diferenca), 0) from cx) soma_diferencas)
  select jsonb_build_object(
    'comprovativos', comprovativos, 'valor_comprovativos', valor_comprovativos, 'rejeitados', rejeitados,
    'nao_conferem', nao_conferem, 'ilegiveis', ilegiveis, 'sem_extrato', sem_extrato,
    'valor_sem_extrato', valor_sem_extrato, 'caixas_fechadas', caixas_fechadas,
    'caixas_com_diferenca', caixas_com_diferenca, 'soma_diferencas', soma_diferencas,
    'rejeitados_tolerados', floor(comprovativos * 0.02)::int,
    'pontuacao', greatest(0, rejeitados - floor(comprovativos * 0.02))::int * 3
                 + sem_extrato * 3 + nao_conferem * 2 + caixas_com_diferenca * 2 + ilegiveis)
  from s;
$function$;
