-- =============================================================================
-- Endurecer permissões (teste geral de segurança, 19/11/2026)
-- -----------------------------------------------------------------------------
-- 1. O esquema "testes" (utilitários dos testes automáticos) ficou em produção depois de uma
--    corrida dos testes pelo editor de SQL. As funções correm com as permissões de quem chama e
--    foram recusadas no teste de ataque, mas código de teste não deve ficar em produção.
--    (Os testes voltam a criá-lo dentro da própria transacção e desfazem-no no fim.)
-- 2. Permissões a mais herdadas dos valores por defeito do Supabase:
--      * o visitante (anon) tinha todas as permissões em 5 tabelas que só o servidor usa;
--      * o visitante e o utilizador com conta podiam esvaziar tabelas (TRUNCATE, que ignora as
--        regras por linha), criar referências ou triggers.
--    Nenhuma era utilizável pela API pública, mas ficam retiradas (segunda camada de protecção),
--    também para as tabelas que se criarem no futuro.
-- Nada muda para as apps: leituras e escritas continuam a passar pelas mesmas regras e funções.
-- =============================================================================

drop schema if exists testes cascade;

revoke all on table aparelhos_conta, custos_cardapio, doses_historico, expiracoes_saldo, receitas from anon;

do $$
declare t record;
begin
  for t in select c.relname from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm', 'f')
  loop
    execute format('revoke truncate, references, trigger on table public.%I from anon, authenticated', t.relname);
  end loop;
end $$;

-- Tabelas futuras (criadas pelo postgres nas migrações): sem estas permissões por defeito
alter default privileges for role postgres in schema public revoke truncate, references, trigger on tables from anon, authenticated;
