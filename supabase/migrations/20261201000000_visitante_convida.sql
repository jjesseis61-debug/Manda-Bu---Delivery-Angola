-- =============================================================================
-- Visitante: «Convida e ganha» como montra (sem conta não há código nem ganhos)
-- -----------------------------------------------------------------------------
-- O visitante vê as regras do programa (quanto ganha, quanto o amigo ganha, níveis de
-- embaixador, levantamento) para ter mais um motivo para criar conta. O código e o link só
-- nascem com a conta (gerados no registo), por isso não há convites nem ganhos sem cadastro.
-- Só os montantes e as regras públicas (as mesmas do texto «Como funciona»); nada de saldos,
-- nomes ou contas. null = o programa (interruptor «indicacao») está desligado.
-- =============================================================================

create or replace function visitante_convida() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when funcionalidade_activa('indicacao') then (
    select jsonb_build_object(
      'ganho_por_pedido', p.ganho_por_pedido,
      'duracao_dias', p.duracao_dias,
      'comissao_primeiro_pedido', p.comissao_primeiro_pedido,
      'desconto_indicado', p.desconto_indicado,
      'desconto_subtotal_minimo', p.desconto_subtotal_minimo,
      'levantamento_minimo', p.levantamento_minimo,
      'validade_saldo_meses', p.validade_saldo_meses,
      'limite_verificacao_semanal', p.limite_verificacao_semanal,
      'bonus_boas_vindas', p.bonus_boas_vindas,
      'limiar_embaixador', p.limiar_embaixador,
      'limiar_ouro', p.limiar_ouro,
      'ganho_por_pedido_embaixador', p.ganho_por_pedido_embaixador,
      'ganho_por_pedido_ouro', p.ganho_por_pedido_ouro)
      from parametros p where p.unico)
  end;
$$;
revoke execute on function visitante_convida() from public;
grant  execute on function visitante_convida() to anon, authenticated;
