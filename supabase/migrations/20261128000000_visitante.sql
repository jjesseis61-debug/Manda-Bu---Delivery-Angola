-- =============================================================================
-- Visitante (Fase A do link partilhado) — quem abre o link de um prato sem conta
-- -----------------------------------------------------------------------------
-- Antes: o link caía logo no registo. Agora o visitante vê o prato e o cardápio daquela cozinha,
-- monta o carrinho e só lhe pedimos a conta ao carregar em «Pedir».
-- O visitante não tem sessão (papel anon), que não lê nenhuma tabela. Estas duas leituras abrem
-- só o que o cliente já vê na app: pratos visíveis online, dentro da janela, de cozinhas que
-- aceitam pedidos e não são de condomínio. Nada de custos, clientes ou moradas.
-- O pedido continua a exigir conta: o servidor recalcula tudo no orçamento, como sempre.
-- =============================================================================

-- Prato que um visitante pode ver (as mesmas regras da app do cliente)
create or replace function prato_para_visitante(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from cardapio c
     where c.id = p_id and c.deletado_em is null and c.disponivel and c.visivel_online
       and janela_aberta(c.disponivel_de, c.disponivel_ate)
       and cozinha_aceita_pedidos(c.cozinha_id)
       and condominio_da_cozinha(c.cozinha_id) is null);
$$;
revoke execute on function prato_para_visitante(uuid) from public, anon, authenticated;

-- Grupos de opções (só com o interruptor dos pratos montáveis), já só com as opções disponíveis
create or replace function opcoes_para_visitante(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id, 'cardapio_id', g.cardapio_id, 'nome', g.nome, 'minimo', g.minimo,
           'maximo', g.maximo, 'ordem', g.ordem,
           'opcoes', coalesce((select jsonb_agg(jsonb_build_object(
                                 'id', o.id, 'nome', o.nome, 'preco_extra', o.preco_extra,
                                 'ordem', o.ordem, 'foto_url', o.foto_url) order by o.ordem, o.nome)
                                from opcoes o
                               where o.grupo_id = g.id and o.disponivel and o.deletado_em is null), '[]'::jsonb))
           order by g.ordem, g.nome), '[]'::jsonb)
    from opcoes_grupos g
   where g.cardapio_id = p_id and g.deletado_em is null and funcionalidade_activa('pratos_montaveis');
$$;
revoke execute on function opcoes_para_visitante(uuid) from public, anon, authenticated;

/**
 * O prato partilhado, para quem ainda não tem conta: o prato, a cozinha, as opções, os
 * ingredientes que se podem tirar e, com um código de convite válido, o desconto do 1.º pedido
 * (o mesmo que a pré-visualização do WhatsApp já mostra). null = o prato não está disponível.
 */
create or replace function visitante_prato(p_id uuid, p_codigo text default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when prato_para_visitante(p_id) then (
    select jsonb_build_object(
      'prato', jsonb_build_object(
        'id', c.id, 'nome', btrim(c.nome), 'descricao', c.descricao, 'categoria', c.categoria,
        'preco', c.preco, 'foto_url', c.foto_url, 'do_dia', c.do_dia, 'cozinha_id', c.cozinha_id,
        'prato_base_id', c.prato_base_id, 'minimo_montavel', c.minimo_montavel, 'pedidos_mes', 0),
      'cozinha', jsonb_build_object('id', k.id, 'nome', k.nome),
      'esgotado', coalesce(doses_restantes(c.id) = 0, false),
      'grupos', opcoes_para_visitante(c.id),
      'componentes', case when funcionalidade_activa('pratos_montaveis')
                          then componentes_dos_pratos(array[c.id]) else '[]'::jsonb end,
      'convite', (
        select jsonb_build_object('desconto', p.desconto_indicado, 'minimo', p.desconto_subtotal_minimo)
          from parametros p
         where p.unico and p.desconto_indicado > 0 and funcionalidade_activa('indicacao')
           and exists (select 1 from codigos_indicacao ci
                        where ci.codigo = upper(btrim(p_codigo)) and ci.deletado_em is null)))
      from cardapio c join cozinhas k on k.id = c.cozinha_id
     where c.id = p_id)
  end;
$$;
revoke execute on function visitante_prato(uuid, text) from public;
grant  execute on function visitante_prato(uuid, text) to anon, authenticated;

/**
 * O cardápio da cozinha do prato partilhado, para o visitante. `montar` = tem opções ou
 * ingredientes para tirar (abre o ecrã de montar em vez de ir direto ao carrinho).
 */
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
                 'esgotado', coalesce(doses_restantes(c.id) = 0, false),
                 'montar', funcionalidade_activa('pratos_montaveis') and (
                     exists (select 1 from opcoes_grupos g where g.cardapio_id = c.id and g.deletado_em is null)
                     or jsonb_array_length(componentes_dos_pratos(array[c.id])) > 1))
                 order by c.do_dia desc, c.ordem, c.nome)
          from cardapio c
         where c.cozinha_id = k.id and prato_para_visitante(c.id)), '[]'::jsonb))
      from cozinhas k where k.id = p_cozinha)
  end;
$$;
revoke execute on function visitante_cardapio(uuid) from public;
grant  execute on function visitante_cardapio(uuid) to anon, authenticated;
