-- Relatório da cozinha rápido com um ano de pedidos (encontrado no teste de 12 meses: 12,8 s → 0,19 s).
-- A retenção ("voltou a pedir aos 30, 60 e 90 dias?") comparava cada cliente novo com todos os pedidos
-- pagos da cozinha. Voltou a pedir depois de primeiro + N dias ⇔ o último pedido pago é depois disso:
-- basta o último pedido de cada cliente, e o resultado é exactamente o mesmo.

create or replace function relatorio_cozinha(p_cozinha uuid, p_inicio date, p_fim date)
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
    select cliente_id, min(entregue_em) as primeiro_em, max(entregue_em) as ultimo_em from pagos group by cliente_id),
  novos as (
    select * from primeiro where primeiro_em >= v_ini and primeiro_em < v_fim),
  retencao as (
    select d.dias,
           count(*) filter (where n.primeiro_em + make_interval(days => d.dias) <= now()) as elegiveis,
           count(*) filter (where n.primeiro_em + make_interval(days => d.dias) <= now()
                              and n.ultimo_em >= n.primeiro_em + make_interval(days => d.dias)) as retidos
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
