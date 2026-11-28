-- =============================================================================
-- App aberta: o Início é o primeiro ecrã para todos (com ou sem conta)
-- -----------------------------------------------------------------------------
-- O visitante (sem sessão) precisa de saber que funcionalidades estão ligadas para a app mostrar
-- o mesmo Início (várias cozinhas, pratos montáveis, Convida…). Os interruptores não são segredo:
-- só a chave e se está ligada. Os dados continuam fechados; o número só é pedido no «Pedir».
-- =============================================================================

create or replace function funcionalidades_publicas() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(chave, activa), '{}'::jsonb) from funcionalidades;
$$;
revoke execute on function funcionalidades_publicas() from public;
grant  execute on function funcionalidades_publicas() to anon, authenticated;
