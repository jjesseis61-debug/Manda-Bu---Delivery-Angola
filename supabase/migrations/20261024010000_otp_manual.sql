-- OTP manual (Opção B, backend): em vez de pagar SMS, o GoTrue chama o "Send SMS Hook" e este
-- GRAVA o código de uso único numa tabela; um operador entrega-o ao cliente (WhatsApp/chamada).
-- Interruptor: a funcionalidade "otp_manual" liga/desliga o serviço. A troca real para um fornecedor
-- de SMS (Twilio/Africell) faz-se no painel do Supabase (provider do telefone); este interruptor
-- controla o lado da app e, por segurança, o hook recusa (bloqueia login) se for desligado enquanto
-- ainda é o provider — o cutover correto é: ligar o fornecedor no painel e só depois desligar isto.

-- 1. Interruptor (começa DESLIGADO; liga-se quando o hook estiver configurado no painel)
insert into funcionalidades (chave, activa, dispositivo_id) values ('otp_manual', false, 'servidor')
on conflict (chave) do nothing;

-- 2. Permissão para ver/entregar os códigos
insert into permissoes (dispositivo_id, chave, grupo, descricao) values
  ('servidor', 'otp.entregar', 'Clientes',
   'Ver e entregar os códigos de login (OTP manual) aos clientes')
on conflict (chave) do nothing;

-- 3. Tabela dos códigos pendentes (só servidor; o operador lê por RPC)
create table otp_pendentes (
  id           uuid primary key default gen_random_uuid(),
  telefone     text not null,              -- como vem do GoTrue (ex.: +244924000111)
  codigo       text not null,
  criado_em    timestamptz not null default now(),
  expira_em    timestamptz not null default now() + interval '10 minutes',
  usado        boolean not null default false,   -- entregue/confirmado ou substituído por um novo
  entregue_em  timestamptz,
  entregue_por uuid references funcionarios(id)
);
create index otp_pendentes_pendentes_idx on otp_pendentes (criado_em desc) where not usado;
create index otp_pendentes_entregue_por_idx on otp_pendentes (entregue_por);
alter table otp_pendentes enable row level security;
revoke all on otp_pendentes from anon, authenticated;

-- 4. O hook do GoTrue (Send SMS Hook): recebe {user:{phone}, sms:{otp}} e grava o código.
--    Com o interruptor desligado, devolve erro (bloqueia o login de propósito — ver nota acima).
create or replace function enviar_sms_otp(event jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_tel text := event -> 'user' ->> 'phone';
  v_otp text := event -> 'sms'  ->> 'otp';
begin
  if not funcionalidade_activa('otp_manual') then
    return jsonb_build_object('error', jsonb_build_object('http_code', 500, 'message', 'otp_manual_desligado'));
  end if;
  if v_tel is null or v_otp is null then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400, 'message', 'payload_invalido'));
  end if;
  -- Reenvio: invalida os códigos anteriores do mesmo número, fica só o mais recente
  update otp_pendentes set usado = true where telefone = v_tel and not usado;
  insert into otp_pendentes (telefone, codigo) values (v_tel, v_otp);
  return '{}'::jsonb;   -- 200 vazio = sucesso
end $$;

-- 5. Lista dos códigos pendentes (para o ecrã do operador), só com otp.entregar
create or replace function otp_pendentes_lista()
returns table (id uuid, telefone text, codigo text, criado_em timestamptz, expira_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('otp.entregar');
  return query
    select o.id, o.telefone, o.codigo, o.criado_em, o.expira_em
      from otp_pendentes o
     where not o.usado and o.expira_em > now()
     order by o.criado_em desc
     limit 50;
end $$;

-- 6. Marcar um código como entregue (regista quem e quando)
create or replace function otp_marcar_entregue(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('otp.entregar');
  update otp_pendentes
     set usado = true, entregue_em = now(), entregue_por = funcionario_actual()
   where id = p_id;
  perform registar_auditoria('otp_entregue', 'otp', p_id, '{}'::jsonb);
end $$;

-- 7. Limpeza das linhas antigas (housekeeping; sem gate, só apaga o que já passou)
create or replace function otp_limpar()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from otp_pendentes where criado_em < now() - interval '1 day';
end $$;

-- 8. Privilégios
revoke execute on function enviar_sms_otp(jsonb)   from public, anon, authenticated;
revoke execute on function otp_pendentes_lista()   from public, anon;
revoke execute on function otp_marcar_entregue(uuid) from public, anon;
revoke execute on function otp_limpar()            from public, anon;
grant  execute on function otp_pendentes_lista()   to authenticated;
grant  execute on function otp_marcar_entregue(uuid) to authenticated;
grant  execute on function otp_limpar()            to authenticated;

-- O hook é chamado pelo GoTrue, que corre como supabase_auth_admin (existe só no Supabase, não no
-- cluster de testes local — por isso o grant é guardado).
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant usage on schema public to supabase_auth_admin';
    execute 'grant execute on function enviar_sms_otp(jsonb) to supabase_auth_admin';
  end if;
end $$;
