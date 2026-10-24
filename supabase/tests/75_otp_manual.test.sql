-- OTP manual (Opção B): o hook grava o código quando o interruptor está ligado; reenvio invalida o
-- anterior; a lista e a entrega exigem otp.entregar; a limpeza apaga os antigos.
begin;
\ir _helpers.psql
select plan(10);

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

-- 2) Ligado: o hook grava o código
select is(enviar_sms_otp(testes.v('ev1')::jsonb), '{}'::jsonb, 'ligado o hook devolve sucesso (vazio)');
select is((select count(*)::int from otp_pendentes where codigo = '123456' and not usado), 1, 'grava o código pendente');

-- 3) Reenvio: invalida o anterior, fica só o novo
select is(enviar_sms_otp(testes.v('ev2')::jsonb), '{}'::jsonb, 'reenvio aceite');
select is((select codigo from otp_pendentes where not usado), '654321', 'o pendente é o código mais recente');
select is((select count(*)::int from otp_pendentes where usado), 1, 'o código anterior fica invalidado');

-- 4) A lista exige otp.entregar
select testes.entrar_funcionario(testes.u('sem_acesso'));
set local role authenticated;
select throws_ok($$select * from otp_pendentes_lista()$$, '42501', 'sem_permissao', 'sem otp.entregar não vê os códigos');
reset role; select testes.sair();

select testes.entrar_funcionario(testes.u('entregador'));
set local role authenticated;
select is((select codigo from otp_pendentes_lista()), '654321', 'quem tem otp.entregar vê o código pendente');
reset role; select testes.sair();

-- 5) Limpeza: apaga os códigos antigos (> 1 dia)
insert into otp_pendentes (telefone, codigo, criado_em) values ('+244000000000', '000000', now() - interval '2 days');
select otp_limpar();
select is((select count(*)::int from otp_pendentes where telefone = '+244000000000'), 0, 'a limpeza apaga os códigos com mais de 1 dia');

select * from finish();
rollback;
