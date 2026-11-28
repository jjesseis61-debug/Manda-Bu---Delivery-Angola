-- OTP manual (Opção B): o hook grava o código quando o interruptor está ligado; reenvio invalida o
-- anterior; a lista e a entrega exigem otp.entregar; a limpeza apaga os antigos.
begin;
\ir _helpers.psql
select plan(22);

select testes.def('sem_acesso', testes.funcionario('Sem Acesso', array[]::text[]));
select testes.def('entregador', testes.funcionario('Entregador OTP', array['otp.entregar']));

-- Payloads do GoTrue (user.phone + sms.otp)
select testes.def('ev1', jsonb_build_object('user', jsonb_build_object('phone', '+244924000111'),
                                            'sms',  jsonb_build_object('otp', '123456'))::text);
select testes.def('ev2', jsonb_build_object('user', jsonb_build_object('phone', '+244924000111'),
                                            'sms',  jsonb_build_object('otp', '654321'))::text);

-- 1) Interruptor DESLIGADO (por omissão): o hook recusa e não grava nada
select is(enviar_sms_otp(testes.v('ev1')::jsonb) ? 'error', true, 'com otp_manual desligado o hook devolve erro');
select is((select count(*)::int from otp_pendentes), 0, 'desligado não grava nenhum código');

-- Ligar o interruptor
select testes.funcionalidade('otp_manual', true);

-- Dispositivos push: o entregador (com otp.entregar) e o sem_acesso (sem a permissão)
insert into dispositivos_push (funcionario_id, token, plataforma) values (testes.u('entregador'), 'tok-entregador', 'android');
insert into dispositivos_push (funcionario_id, token, plataforma) values (testes.u('sem_acesso'), 'tok-semacesso', 'android');

-- 2) Ligado: o hook grava o código
select is(enviar_sms_otp(testes.v('ev1')::jsonb), '{}'::jsonb, 'ligado o hook devolve sucesso (vazio)');
select is((select count(*)::int from otp_pendentes where codigo = '123456' and not usado), 1, 'grava o código pendente');

-- 2b) Aviso N40 só a quem tem otp.entregar e dispositivo
select is((select count(*)::int from notificacoes_fila where codigo = 'N40' and funcionario_id = testes.u('entregador')), 1,
          'avisa (N40) o funcionário com otp.entregar e dispositivo');
select is((select count(*)::int from notificacoes_fila where codigo = 'N40' and funcionario_id = testes.u('sem_acesso')), 0,
          'não avisa quem não tem otp.entregar');

-- 2c) O N40 recente é DESPACHADO como push (com o token do entregador), não fica só no sino
select is((select count(*)::int from notificacoes_por_enviar(200)
            where codigo = 'N40' and tokens @> array['tok-entregador']), 1,
          'o N40 recente é despachado como push ao entregador');

-- 3) Reenvio: invalida o anterior, fica só o novo
select is(enviar_sms_otp(testes.v('ev2')::jsonb), '{}'::jsonb, 'reenvio aceite');
select is((select codigo from otp_pendentes where not usado), '654321', 'o pendente é o código mais recente');
select is((select count(*)::int from otp_pendentes where usado), 1, 'o código anterior fica invalidado');
select is((select count(*)::int from notificacoes_fila where codigo = 'N40'), 1, 'anti-spam: o reenvio não cria novo aviso');

-- 4) A lista exige otp.entregar
select testes.entrar_funcionario(testes.u('sem_acesso'));
set local role authenticated;
select throws_ok($$select * from otp_pendentes_lista()$$, '42501', 'sem_permissao', 'sem otp.entregar não vê os códigos');
reset role; select testes.sair();

select testes.entrar_funcionario(testes.u('entregador'));
set local role authenticated;
select is((select codigo from otp_pendentes_lista()), '654321', 'quem tem otp.entregar vê o código pendente');
reset role; select testes.sair();

-- 4b) Um N40 com mais de 10 min já não é despachado (validade curta: o código de login já expirou)
insert into notificacoes_fila (funcionario_id, codigo, dados, criado_em)
  values (testes.u('entregador'), 'N40', jsonb_build_object('tel_mascarado', '999'), now() - interval '20 minutes');
select is((select count(*)::int from notificacoes_por_enviar(200) where dados ->> 'tel_mascarado' = '999'), 0,
          'um N40 com mais de 10 min já não é despachado como push');

-- 4c) otp_confirmar: o cliente fecha o SEU código ao entrar (lê o telefone de auth.users, compara dígitos)
select testes.def('cli_otp', testes.cliente('Cliente OTP', 'Particular', '+244924000111'));
select testes.entrar(testes.u('cli_otp'));
set local role authenticated;
select lives_ok($$select otp_confirmar()$$, 'otp_confirmar corre na sessão do cliente');
reset role; select testes.sair();
select is((select count(*)::int from otp_pendentes where codigo = '654321' and not usado), 0,
          'otp_confirmar fecha o código pendente do próprio número ao entrar');

-- 4d) A confirmação aparece ao operador (5 min): com o primeiro nome e SEM o código; e fica na auditoria
select testes.entrar_funcionario(testes.u('entregador'));
set local role authenticated;
select is((select nome   from otp_pendentes_lista() where estado = 'confirmado'), 'Cliente',
          'a confirmação mostra o primeiro nome do cliente');
select is((select codigo from otp_pendentes_lista() where estado = 'confirmado'), null,
          'a confirmação não mostra o código (já usado)');
reset role; select testes.sair();
select is((select count(*)::int from auditoria where acao = 'otp_login'), 1,
          'o login fica registado na auditoria');

-- 4e) Login de um número SEM código pendente (ex.: número de teste do painel) também fica auditado
--     (3 dígitos diferentes do caso acima para não cair no dedup)
select testes.def('cli_teste', testes.cliente('Teste Num', 'Particular', '+244999000222'));
select testes.entrar(testes.u('cli_teste'));
set local role authenticated;
select lives_ok($$select otp_confirmar()$$, 'otp_confirmar corre para número sem código pendente');
reset role; select testes.sair();
select is((select count(*)::int from auditoria where acao = 'otp_login' and (detalhe::jsonb ->> 'sem_codigo') = 'true'), 1,
          'o login de um número sem código pendente fica registado na auditoria');

-- 5) Limpeza: apaga os códigos antigos (> 1 dia)
insert into otp_pendentes (telefone, codigo, criado_em) values ('+244000000000', '000000', now() - interval '2 days');
select otp_limpar();
select is((select count(*)::int from otp_pendentes where telefone = '+244000000000'), 0, 'a limpeza apaga os códigos com mais de 1 dia');

select * from finish();
rollback;
