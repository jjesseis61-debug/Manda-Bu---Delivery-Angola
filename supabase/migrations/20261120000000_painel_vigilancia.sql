-- =============================================================================
-- Painel de vigilância do Convida e Ganha (#9): fraudes e abusos num só ecrã
-- -----------------------------------------------------------------------------
-- Junta, para um período (por defeito os últimos 14 dias):
--   * ganhos em verificação (à espera de decisão) e ganhos anulados por motivo
--     (mesmo telemóvel, mesmo local, número de pagamento partilhado, limite semanal…);
--   * levantamentos pendentes (pedidos/aprovados por pagar), com o mais antigo;
--   * picos: contas novas, códigos usados (ligações) e ganhos por dia, com o dia marcado
--     quando passa o dobro da média (e pelo menos 5);
--   * quem mais ganhou no período e quantos dos seus convidados só fizeram 1 pedido;
--   * telemóveis com várias contas (contagem; a lista detalhada já está no ecrã).
-- Só lê dados; quem decide é a pessoa, na Verificação dos ganhos.
-- =============================================================================

create or replace function painel_vigilancia(p_dias int default 14)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_dias int := greatest(1, least(coalesce(p_dias, 14), 90));
  v_ini  timestamptz := ((now() at time zone 'Africa/Luanda')::date - (v_dias - 1))::timestamp at time zone 'Africa/Luanda';
  r      jsonb;
begin
  perform exigir_permissao('indicacoes.verificar');

  with dias as (
    select d::date as dia
      from generate_series((now() at time zone 'Africa/Luanda')::date - (v_dias - 1),
                           (now() at time zone 'Africa/Luanda')::date, interval '1 day') d
  ),
  serie as (
    select x.dia,
           (select count(*) from clientes c where c.deletado_em is null
              and (c.criado_em at time zone 'Africa/Luanda')::date = x.dia)::int as contas,
           (select count(*) from ligacoes_indicacao l where l.deletado_em is null
              and (l.criado_em at time zone 'Africa/Luanda')::date = x.dia)::int as ligacoes,
           (select count(*) from ganhos_indicacao g where g.deletado_em is null
              and (g.criado_em at time zone 'Africa/Luanda')::date = x.dia)::int as ganhos
      from dias x
  ),
  medias as (
    select avg(contas) as m_contas, avg(ligacoes) as m_ligacoes, avg(ganhos) as m_ganhos from serie
  ),
  topo as (
    select g.indicador_id,
           count(*)::int as ganhos,
           sum(g.valor)::int as valor,
           count(distinct g.indicado_id)::int as indicados,
           count(*) filter (where g.estado = 'anulado')::int as anulados
      from ganhos_indicacao g
     where g.deletado_em is null and g.criado_em >= v_ini
     group by g.indicador_id
     order by sum(g.valor) filter (where g.estado <> 'anulado') desc nulls last
     limit 10
  )
  select jsonb_build_object(
    'dias', v_dias,
    'em_verificacao', (select jsonb_build_object('n', count(*), 'valor', coalesce(sum(valor), 0),
                                                 'mais_antigo', min(criado_em))
                         from ganhos_indicacao where deletado_em is null and estado = 'em_verificacao'),
    'anulados', (select jsonb_build_object(
                   'n', coalesce(sum(n_m), 0), 'valor', coalesce(sum(valor), 0),
                   'por_motivo', coalesce(jsonb_agg(m order by n_m desc), '[]'))
                   from (select jsonb_build_object('motivo', coalesce(motivo, 'sem motivo'), 'n', count(*),
                                                   'valor', sum(valor)) as m, count(*) as n_m, sum(valor) as valor
                           from ganhos_indicacao
                          where deletado_em is null and estado = 'anulado' and criado_em >= v_ini
                          group by coalesce(motivo, 'sem motivo')
                          order by count(*) desc) a),
    'levantamentos', (select jsonb_build_object('n', count(*), 'valor', coalesce(sum(valor), 0),
                                                'pedidos', count(*) filter (where estado = 'pedido'),
                                                'aprovados', count(*) filter (where estado = 'aprovado'),
                                                'mais_antigo', min(criado_em))
                        from pagamentos_indicacao
                       where deletado_em is null and tipo = 'levantamento' and estado in ('pedido', 'aprovado')),
    'serie', coalesce((select jsonb_agg(jsonb_build_object(
                         'dia', s.dia, 'contas', s.contas, 'ligacoes', s.ligacoes, 'ganhos', s.ganhos,
                         'pico', (s.contas >= 5 and s.contas > 2 * m.m_contas)
                              or (s.ligacoes >= 5 and s.ligacoes > 2 * m.m_ligacoes)
                              or (s.ganhos >= 5 and s.ganhos > 2 * m.m_ganhos)) order by s.dia)
                         from serie s cross join medias m), '[]'),
    'medias', (select jsonb_build_object('contas', round(m_contas, 1), 'ligacoes', round(m_ligacoes, 1),
                                         'ganhos', round(m_ganhos, 1)) from medias),
    'topo', coalesce((select jsonb_agg(jsonb_build_object(
                        'cliente_id', t.indicador_id,
                        'nome', c.nome,
                        'codigo', ci.codigo,
                        'nivel', ci.nivel,
                        'ganhos', t.ganhos, 'valor', t.valor, 'indicados', t.indicados, 'anulados', t.anulados,
                        -- convidados com 1 só pedido entregue (o do desconto): sinal de contas "de favor"
                        'so_um_pedido', (select count(*) from ligacoes_indicacao l
                                          where l.indicador_id = t.indicador_id and l.deletado_em is null
                                            and (select count(*) from pedidos p where p.cliente_id = l.indicado_id
                                                   and p.estado = 'entregue_pago' and p.deletado_em is null) = 1))
                        order by t.valor desc)
                        from topo t join clientes c on c.id = t.indicador_id
                        left join codigos_indicacao ci on ci.cliente_id = t.indicador_id), '[]'),
    'aparelhos_partilhados', (select count(*) from (
                                select coalesce(ac.aparelho_id, 'web:' || ac.instalacao_id)
                                  from aparelhos_conta ac
                                 group by 1
                                having count(distinct ac.cliente_id) >= (select alerta_contas_por_aparelho from parametros where unico)) x)
  ) into r;
  return r;
end $$;
revoke execute on function painel_vigilancia(int) from public, anon;
grant  execute on function painel_vigilancia(int) to authenticated;
