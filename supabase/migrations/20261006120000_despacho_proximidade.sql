-- Auto-despacho por proximidade (sugestão) + base para batching.
-- Para cada pedido pronto a sair (confirmado/em preparação) de uma cozinha, sugere o estafeta
-- ONLINE (a partilhar posição) mais perto do ponto de entrega, desempatando pela carga actual.
-- É só uma sugestão para quem despacha: não muda a atribuição (o estafeta continua a marcar
-- "em entrega" como hoje). A UI agrupa por zona — pedidos da mesma zona com o mesmo estafeta
-- sugerido são candidatos a ir na mesma viagem (batching).

create or replace function sugestao_despacho(p_cozinha uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  if not tem_permissao('pedidos.gerir') then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir';
  end if;

  with online as (
    select pe.funcionario_id, f.nome, pe.lat, pe.lng,
           (select count(*) from pedidos p
             where p.entregador_id = pe.funcionario_id and p.estado = 'em_entrega' and p.deletado_em is null) as carga
      from posicoes_entregadores pe
      join funcionarios f on f.id = pe.funcionario_id and f.deletado_em is null
     where tem_permissao_de(pe.funcionario_id, 'entregas.registar')
  ),
  prontos as (
    select x.id, x.itens, pt.lat, pt.lng, pt.referencia, z.nome as zona
      from pedidos x
      left join pontos_entrega pt on pt.id = x.ponto_entrega_id
      left join zonas z on z.id = coalesce(pt.zona_id, x.zona_id)
     where x.deletado_em is null and x.cozinha_id = p_cozinha
       and x.estado in ('confirmado', 'em_preparacao')
       and (x.agendado_para is null or x.agendado_para <= now() + interval '90 minutes')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'pedido_id', pr.id,
           'zona', coalesce(pr.zona, 'Sem zona'),
           'referencia', pr.referencia,
           'itens', pr.itens,
           'sugestao', (
             select jsonb_build_object('funcionario_id', o.funcionario_id, 'nome', o.nome,
                                       'distancia_km', round(distancia_km(pr.lat, pr.lng, o.lat, o.lng)::numeric, 1),
                                       'pedidos_a_levar', o.carga)
               from online o
              where pr.lat is not null and pr.lng is not null
              order by distancia_km(pr.lat, pr.lng, o.lat, o.lng) asc, o.carga asc
              limit 1
           )
         ) order by coalesce(pr.zona, 'Sem zona'), pr.id), '[]'::jsonb)
    into v
    from prontos pr;
  return v;
end $$;

revoke execute on function sugestao_despacho(uuid) from public, anon;
grant  execute on function sugestao_despacho(uuid) to authenticated;
