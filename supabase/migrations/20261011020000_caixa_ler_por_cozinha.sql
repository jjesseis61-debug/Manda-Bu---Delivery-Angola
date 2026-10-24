-- Segurança: a leitura da tabela caixa verificava só a permissão global, sem olhar à cozinha — um
-- operador via as caixas (e os totais) de TODAS as cozinhas. As acções (abrir, fechar, sangria,
-- resumo) já exigiam pode_na_cozinha; faltava a listagem.
--
-- Há dois usos da listagem:
--   * o ecrã de Entregas, onde o estafeta escolhe a caixa ABERTA da cozinha do pedido (precisa de ver
--     as caixas abertas, mesmo de cozinhas onde não é membro), e
--   * o ecrã de gestão da Caixa (abrir/fechar/sangria), que deve mostrar só a(s) cozinha(s) do operador.
-- Por isso: a RLS deixa o estafeta ver as caixas ABERTAS; o ecrã de gestão passa a usar um RPC com
-- escopo por cozinha (caixas_geridas). O administrador e quem tem cozinhas.gerir continuam a ver tudo.

alter policy "ler" on public.caixa using (
  deletado_em is null
  and ( (fechamento is null and (select tem_permissao('entregas.registar')))
     or pode_na_cozinha('vendas.registar', cozinha_id)
     or pode_na_cozinha('pedidos.gerir',   cozinha_id) ));

-- Lista para o ecrã de gestão da Caixa: só as caixas que o funcionário pode mesmo gerir (a sua cozinha).
create or replace function caixas_geridas(p_limite int default 20)
returns table (id uuid, posto text, data date, cozinha_id uuid, troco_inicial numeric,
               funcionario_nome text, fechamento jsonb)
language sql stable security definer set search_path = public as $$
  select c.id, c.posto, c.data, c.cozinha_id, c.troco_inicial, c.funcionario_nome, c.fechamento
    from caixa c
   where c.deletado_em is null
     and (pode_na_cozinha('vendas.registar', c.cozinha_id) or pode_na_cozinha('pedidos.gerir', c.cozinha_id))
   order by c.criado_em desc
   limit greatest(1, least(coalesce(p_limite, 20), 100));
$$;
revoke execute on function caixas_geridas(int) from public, anon;
grant  execute on function caixas_geridas(int) to authenticated;
