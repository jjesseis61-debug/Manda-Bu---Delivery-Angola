-- Endurecimento de I1: garantias verificadas pelos avisos do Supabase
-- (search_path, funções de trigger não expostas, índices nas chaves estrangeiras).
begin;
\ir _helpers.psql
select plan(5);

-- Todas as funções do esquema public têm search_path fixo
-- (rls_auto_enable é criada pelo próprio Supabase e não é nossa)
select is((select string_agg(p.proname, ', ' order by p.proname)
             from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname <> 'rls_auto_enable'
              and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')),
          null, 'todas as funções têm search_path fixo');

-- Nenhuma função de trigger é executável por anon/authenticated
select is((select string_agg(p.proname, ', ' order by p.proname)
             from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.prorettype = 'trigger'::regtype
              and (has_function_privilege('anon', p.oid, 'execute')
                   or has_function_privilege('authenticated', p.oid, 'execute'))),
          null, 'funções de trigger não são chamáveis pelas apps');

select is((select count(*)::int from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname = 'mesmo_ponto_entrega'
              and has_function_privilege('authenticated', p.oid, 'execute')), 0,
          'mesmo_ponto_entrega só é usada dentro do servidor');

-- Todas as chaves estrangeiras têm um índice que começa pelas suas colunas
select is((select string_agg(c.conrelid::regclass || '.' || c.conname, ', ')
             from pg_constraint c
            where c.contype = 'f' and c.connamespace = 'public'::regnamespace
              and not exists (select 1 from pg_index i
                               where i.indrelid = c.conrelid
                                 and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] = c.conkey)),
          null, 'todas as chaves estrangeiras têm índice');

select has_index('vendas', 'vendas_local_idx', 'índice de vendas.local com o nome correcto');

select * from finish();
rollback;
