-- Permissões endurecidas (teste geral de segurança, 19/11/2026): ninguém de fora pode esvaziar
-- tabelas (TRUNCATE ignora as regras por linha) e o visitante não tem permissões directas nas
-- tabelas que só o servidor usa. Vale também para tabelas criadas depois (permissões por defeito).
begin;
\ir _helpers.psql
select plan(4);

select is((select count(*)::int from information_schema.role_table_grants
            where table_schema = 'public' and grantee in ('anon', 'authenticated')
              and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')),
          0, 'visitante e utilizador com conta não podem esvaziar tabelas nem criar referências/triggers');
select is((select count(*)::int from information_schema.role_table_grants
            where table_schema = 'public' and grantee = 'anon'
              and table_name in ('aparelhos_conta', 'custos_cardapio', 'doses_historico', 'expiracoes_saldo', 'receitas')),
          0, 'o visitante não tem permissões nas tabelas só do servidor');

create table public.tabela_nova_teste (id int);
select is((select count(*)::int from information_schema.role_table_grants
            where table_name = 'tabela_nova_teste' and grantee in ('anon', 'authenticated')
              and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')),
          0, 'tabelas novas também nascem sem TRUNCATE/REFERENCES/TRIGGER para fora');

grant usage on schema testes to anon;
set local role anon;
select testes.def('e_truncate', testes.erro('truncate receitas'));
reset role;
select matches(testes.v('e_truncate'), '^42501', 'o visitante não consegue esvaziar a tabela de receitas');

select * from finish();
rollback;
