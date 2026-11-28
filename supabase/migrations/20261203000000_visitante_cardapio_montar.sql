-- =============================================================================
-- Visitante: o cardápio igual ao de quem tem conta (pratos para montar, esgotados e «desde»)
-- -----------------------------------------------------------------------------
-- Corrige visitante_cardapio para seguir as mesmas regras da app com conta:
--   * «montar» só com pelo menos uma opção disponível num grupo, ou mais de um ingrediente para
--     tirar (antes bastava existir um grupo, mesmo vazio: um prato aparecia no topo sem nada
--     para escolher);
--   * esgotado também quando um grupo obrigatório não tem nenhuma opção disponível;
--   * «desde»: o preço mais baixo possível dos pratos com grupos obrigatórios (base + as opções
--     mais baratas que é preciso escolher), como o «desde X Kz» do Início com conta.
-- =============================================================================

create or replace function visitante_cardapio(p_cozinha uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when cozinha_aceita_pedidos(p_cozinha) and condominio_da_cozinha(p_cozinha) is null then (
    select jsonb_build_object(
      'cozinha', jsonb_build_object('id', k.id, 'nome', k.nome),
      'pratos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', c.id, 'nome', btrim(c.nome), 'descricao', c.descricao, 'categoria', c.categoria,
                 'preco', c.preco, 'foto_url', c.foto_url, 'do_dia', c.do_dia, 'cozinha_id', c.cozinha_id,
                 'prato_base_id', c.prato_base_id, 'minimo_montavel', c.minimo_montavel, 'pedidos_mes', 0,
                 'esgotado', coalesce(doses_restantes(c.id) = 0, false) or (m.ligado and m.obrigatorio_vazio),
                 'montar', m.ligado and (m.com_opcoes or m.ingredientes > 1),
                 'desde', case when m.ligado and m.tem_obrigatorio then c.preco + m.extra_minimo end)
                 order by c.do_dia desc, c.ordem, c.nome)
          from cardapio c
          cross join lateral (
            select funcionalidade_activa('pratos_montaveis') as ligado,
                   exists (select 1 from opcoes_grupos g join opcoes o on o.grupo_id = g.id
                            where g.cardapio_id = c.id and g.deletado_em is null
                              and o.disponivel and o.deletado_em is null) as com_opcoes,
                   exists (select 1 from opcoes_grupos g
                            where g.cardapio_id = c.id and g.deletado_em is null and g.minimo > 0
                              and not exists (select 1 from opcoes o where o.grupo_id = g.id
                                                 and o.disponivel and o.deletado_em is null)) as obrigatorio_vazio,
                   exists (select 1 from opcoes_grupos g
                            where g.cardapio_id = c.id and g.deletado_em is null and g.minimo > 0) as tem_obrigatorio,
                   coalesce((select sum(x.preco_extra)
                               from opcoes_grupos g
                               cross join lateral (
                                 select o.preco_extra from opcoes o
                                  where o.grupo_id = g.id and o.disponivel and o.deletado_em is null
                                  order by o.preco_extra
                                  limit g.minimo) x
                              where g.cardapio_id = c.id and g.deletado_em is null and g.minimo > 0), 0) as extra_minimo,
                   jsonb_array_length(componentes_dos_pratos(array[c.id])) as ingredientes
          ) m
         where c.cozinha_id = k.id and prato_para_visitante(c.id)), '[]'::jsonb))
      from cozinhas k where k.id = p_cozinha)
  end;
$$;
revoke execute on function visitante_cardapio(uuid) from public;
grant  execute on function visitante_cardapio(uuid) to anon, authenticated;
