-- Ecrã geral de auditoria: só com auditoria.ver; filtra por categoria.
begin;
\ir _helpers.psql
select plan(4);

select testes.def('admin',     testes.funcionario('Admin Aud', array['auditoria.ver']));
select testes.def('sem_acesso', testes.funcionario('Sem Aud', array[]::text[]));

-- Algumas linhas de auditoria de categorias diferentes
insert into auditoria (acao, ref_tipo, funcionario_nome) values
  ('otp_login', 'otp', 'cliente'),
  ('funcionario_criado', 'funcionarios', 'Admin Aud'),
  ('caixa_aberta', 'caixa', 'Admin Aud');

-- 1) Sem a permissão: recusa
select testes.entrar_funcionario(testes.u('sem_acesso'));
set local role authenticated;
select throws_ok($$select * from auditoria_lista()$$, '42501', 'sem_permissao', 'sem auditoria.ver não vê o registo');
reset role; select testes.sair();

select testes.entrar_funcionario(testes.u('admin'));
set local role authenticated;
-- 2) Com a permissão: vê as linhas
select is((select count(*)::int from auditoria_lista()
            where acao in ('otp_login', 'funcionario_criado', 'caixa_aberta')), 3,
          'com auditoria.ver vê o registo completo');
-- 3) Categoria 'login': só traz as de OTP
select is((select bool_and(ref_tipo = 'otp') from auditoria_lista('login')), true,
          'a categoria login só traz eventos de OTP');
-- 4) Categoria 'cardapio': não traz nenhuma destas (não há eventos de cardápio)
select is((select count(*)::int from auditoria_lista('cardapio')
            where acao in ('otp_login', 'funcionario_criado', 'caixa_aberta')), 0,
          'a categoria cardápio não traz os eventos de outras áreas');
reset role; select testes.sair();

select * from finish();
rollback;
