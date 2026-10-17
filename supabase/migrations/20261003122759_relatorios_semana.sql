-- Correcções dos relatórios encontradas na simulação de uma semana de operação.
--  * relatorio_cozinha: o "prato mais pedido" agrupava por prato_base_id; sem fichas técnicas todos
--    os pratos caíam no mesmo grupo (soma de tudo, nome do primeiro por ordem alfabética). Agrupa
--    pela ficha técnica, senão pelo prato do cardápio, e mostra o nome do prato do cardápio.
--  * metricas_turno: as entregas só contavam pedidos com hora prometida (só os de grupo a têm), por
--    isso o ecrã Equipa mostrava 0 entregas. Conta todas as entregas do turno; "a horas" e a
--    percentagem continuam a ser só sobre as que tinham hora prometida.

CREATE OR REPLACE FUNCTION public.metricas_turno(p_cozinha uuid, p_semana date)
 RETURNS TABLE(periodo text, quebras integer, quantidade_quebra numeric, entregas integer, entregas_a_horas integer, pct_a_horas numeric, diferenca_caixa numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (tem_permissao('equipa.reconhecer')
          or membro_da_cozinha(p_cozinha)) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
  with janelas as (
    select t.data, t.periodo,
           (t.data + min(t.hora_inicio)) at time zone 'Africa/Luanda' as ini,
           (t.data + max(t.hora_fim))    at time zone 'Africa/Luanda' as fim,
           array_agg(t.funcionario_id) as membros
      from turnos t
     where t.cozinha_id = p_cozinha and t.deletado_em is null and t.periodo is not null
       and t.data between p_semana and p_semana + 6
     group by t.data, t.periodo),
  q as (
    select j.periodo, count(d.id)::int as n, coalesce(sum(d.quantidade_quebra), 0) as qtd
      from janelas j
      left join distribuicoes d on d.cozinha_id = p_cozinha and d.deletado_em is null
       and d.quantidade_quebra > 0 and d.criado_em between j.ini and j.fim
     group by j.periodo),
  e as (
    select j.periodo, count(x.id)::int as n,
           count(x.id) filter (where x.hora_prometida is not null)::int as com_hora,
           count(x.id) filter (where x.entregue_em <= x.hora_prometida
                                 + make_interval(mins => (select tolerancia_entrega_min from parametros where unico)))::int as a_horas
      from janelas j
      left join pedidos x on x.cozinha_id = p_cozinha and x.deletado_em is null
       and x.estado = 'entregue_pago'
       and x.entregue_em between j.ini and j.fim
     group by j.periodo),
  c as (
    select j.periodo, coalesce(sum(abs((cx.fechamento ->> 'diferenca')::numeric)), 0) as dif
      from janelas j
      left join caixa cx on cx.cozinha_id = p_cozinha and cx.deletado_em is null
       and cx.data = j.data and cx.funcionario_id = any (j.membros)
       and cx.fechamento ? 'diferenca'
     group by j.periodo)
  select q.periodo, q.n, q.qtd, e.n, e.a_horas,
         case when e.com_hora > 0 then round(100.0 * e.a_horas / e.com_hora, 1) end,
         c.dif
    from q join e using (periodo) join c using (periodo)
   order by array_position(array['manha','tarde','noite'], q.periodo);
end $function$;

CREATE OR REPLACE FUNCTION public.relatorio_cozinha(p_cozinha uuid, p_inicio date, p_fim date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  r     jsonb;
begin
  perform exigir_permissao('relatorios.exportar');
  with pagos as (
    select * from pedidos
     where cozinha_id = p_cozinha and estado = 'entregue_pago' and deletado_em is null),
  primeiro as (
    select cliente_id, min(entregue_em) as primeiro_em from pagos group by cliente_id),
  novos as (
    select * from primeiro where primeiro_em >= v_ini and primeiro_em < v_fim),
  retencao as (
    select d.dias,
           count(*) filter (where n.primeiro_em + make_interval(days => d.dias) <= now()) as elegiveis,
           count(*) filter (where n.primeiro_em + make_interval(days => d.dias) <= now()
                              and exists (select 1 from pagos x
                                           where x.cliente_id = n.cliente_id
                                             and x.entregue_em >= n.primeiro_em + make_interval(days => d.dias))) as retidos
      from novos n cross join (values (30), (60), (90)) d(dias)
     group by d.dias),
  -- Cada linha do pedido conta pelo seu prato: a ficha técnica se existir, senão o prato do cardápio
  linhas as (
    select i ->> 'prato_base_id' as prato_base_id, i ->> 'cardapio_id' as cardapio_id, i ->> 'nome' as nome,
           coalesce(i ->> 'prato_base_id', i ->> 'cardapio_id', i ->> 'nome') as chave,
           coalesce((i ->> 'qtd')::numeric, 1) as qtd
      from pagos x, jsonb_array_elements(x.itens) i
     where x.entregue_em >= v_ini and x.entregue_em < v_fim)
  select jsonb_build_object(
    'pedidos_por_dia', coalesce((
       select jsonb_agg(jsonb_build_object('dia', dia, 'pedidos', n) order by dia)
         from (select (entregue_em at time zone 'Africa/Luanda')::date as dia, count(*) as n
                 from pagos where entregue_em >= v_ini and entregue_em < v_fim
                group by 1) s), '[]'),
    'clientes_novos', (select count(*) from novos),
    'clientes_indicacao', (select count(*) from novos n
                            where exists (select 1 from ligacoes_indicacao l where l.indicado_id = n.cliente_id)),
    'retencao', coalesce((
       select jsonb_object_agg(dias::text, case when elegiveis > 0
                                                 then round(100.0 * retidos / elegiveis, 1) end)
         from retencao), '{}'),
    'media_avaliacao', (select round(avg(estrelas)::numeric, 1) from avaliacoes
                         where cozinha_id = p_cozinha and not oculta and deletado_em is null
                           and criado_em >= v_ini and criado_em < v_fim),
    'prato_mais_pedido', (
       select jsonb_build_object('prato_base_id', max(l.prato_base_id),
                                 'cardapio_id', max(l.cardapio_id),
                                 'nome', coalesce((select trim(c.nome) from cardapio c where c.id::text = max(l.cardapio_id)),
                                                  max(l.nome)),
                                 'quantidade', sum(l.qtd))
         from linhas l
        group by l.chave
        order by sum(l.qtd) desc, max(l.nome)
        limit 1))
  into r;
  return r;
end $function$;
