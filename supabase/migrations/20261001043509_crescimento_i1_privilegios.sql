-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I1 · Privilégios das funções SECURITY DEFINER
--
--   1. Guarda do consumo de stock sem funções expostas: a guarda passa a
--      SECURITY DEFINER (lê a venda e regista na auditoria como dona). Para
--      continuar a reconhecer uma sessão do telemóvel, um trigger anterior,
--      SECURITY INVOKER e sem privilégios especiais, troca o dispositivo_id
--      'servidor' enviado por uma sessão authenticated/anon por uma marca que
--      a guarda rejeita. origem_venda e auditar_consumo_bloqueado deixam de
--      ser chamáveis pelas apps.
--   2. Funções auxiliares internas deixam de ser chamáveis pelas apps:
--      gerar_codigo_grupo (o código de convite passa a ser gerado num trigger
--      SECURITY DEFINER próprio).
--      Ficam chamáveis, por necessidade, as auxiliares usadas em políticas RLS,
--      em valores por defeito de colunas ou em triggers SECURITY INVOKER (essas
--      expressões correm com o papel de quem escreve): cliente_actual,
--      funcionario_actual, e_funcionario, tem_permissao, membro_da_cozinha,
--      funcionalidade_activa, avaliacao_permitida, cozinha_padrao.
--      rls_auto_enable não é nossa (event trigger ensure_rls do Supabase).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Guarda do consumo de stock
-- -----------------------------------------------------------------------------
-- SECURITY INVOKER: só aqui se sabe quem escreve (e_escrita_cliente). Não lê
-- tabelas nem chama funções do servidor.
create or replace function estoque_lp_marcar_sessao_app() returns trigger
language plpgsql set search_path = public as $$
begin
  if e_escrita_cliente() and new.dispositivo_id is not distinct from 'servidor' then
    new.dispositivo_id := 'app (indicou servidor)';
  end if;
  return new;
end $$;

-- Corre antes de trg_estoque_lp_0_consumo_servidor (ordem por nome)
create trigger trg_estoque_lp_00_sessao_app
before insert or update on estoque_longo_prazo
for each row execute function estoque_lp_marcar_sessao_app();

create or replace function estoque_lp_guardar_consumo_servidor() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_venda  uuid := coalesce(new.venda_id, case when tg_op = 'UPDATE' then old.venda_id end);
  v_origem text;
begin
  if v_venda is null then
    return new;
  end if;
  v_origem := origem_venda(v_venda);
  if v_origem like 'App cliente%' and new.dispositivo_id is distinct from 'servidor' then
    perform auditar_consumo_bloqueado(new.id, v_venda,
      jsonb_build_object('origem', v_origem, 'operacao', tg_op,
                         'dispositivo_id', new.dispositivo_id, 'produto_id', new.produto_id,
                         'quantidade', new.quantidade, 'papel', current_setting('role', true)));
    return null;
  end if;
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Código de convite do grupo num trigger SECURITY DEFINER
-- -----------------------------------------------------------------------------
create or replace function pedidos_grupo_antes_inserir() returns trigger
language plpgsql set search_path = public as $$
begin
  if e_escrita_cliente() then
    new.organizador_id := cliente_actual();
    new.estado := 'aberto';
  end if;
  return new;
end $$;

create or replace function pedidos_grupo_codigo_convite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.codigo_convite := gerar_codigo_grupo();
  return new;
end $$;

create trigger trg_pedidos_grupo_codigo_convite
before insert on pedidos_grupo
for each row execute function pedidos_grupo_codigo_convite();

-- -----------------------------------------------------------------------------
-- 3. Privilégios
-- -----------------------------------------------------------------------------
revoke execute on function origem_venda(uuid)                          from public, anon, authenticated;
revoke execute on function auditar_consumo_bloqueado(uuid, uuid, jsonb) from public, anon, authenticated;
revoke execute on function gerar_codigo_grupo()                        from public, anon, authenticated;
revoke execute on function estoque_lp_marcar_sessao_app()              from public, anon, authenticated;
revoke execute on function estoque_lp_guardar_consumo_servidor()       from public, anon, authenticated;
revoke execute on function pedidos_grupo_antes_inserir()               from public, anon, authenticated;
revoke execute on function pedidos_grupo_codigo_convite()              from public, anon, authenticated;
