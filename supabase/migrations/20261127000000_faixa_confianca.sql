-- =============================================================================
-- Faixa de confiança (app do cliente) — decisão do dono com os especialistas (17/11/2026)
-- -----------------------------------------------------------------------------
-- "Pagas na entrega · Comida de casa · <3.ª frase>". A 3.ª frase depende de factos, nunca de promessas:
--   * B (início): "Problema? Resolvemos";
--   * A: "Na tua porta em ~N min" só quando, nos últimos 30 dias, pelo menos 90% das entregas
--     imediatas chegaram até à hora prometida e houve pelo menos 30 dessas entregas;
--   * C (alterna na app): "X pedidos hoje no teu bairro" quando o contador da zona tem número.
-- Esta função dá à app a pontualidade (só números agregados, sem dados de ninguém).
-- =============================================================================

create or replace function pontualidade_entregas()
returns jsonb language sql stable security definer set search_path = public as $$
  with e as (
    select entregue_em <= hora_prometida as a_tempo
      from pedidos
     where deletado_em is null and estado = 'entregue_pago' and agendado_para is null
       and hora_prometida is not null and entregue_em is not null
       and entregue_em > now() - interval '30 days'
  )
  select jsonb_build_object(
    'entregas', (select count(*) from e),
    'a_tempo_pct', (select round(100.0 * count(*) filter (where a_tempo) / nullif(count(*), 0)) from e),
    'tempo_min', (select tempo_entrega_min from parametros where unico),
    'cumpre', coalesce((select count(*) >= 30 and count(*) filter (where a_tempo) >= 0.9 * count(*) from e), false));
$$;
revoke execute on function pontualidade_entregas() from public, anon;
grant  execute on function pontualidade_entregas() to authenticated;
