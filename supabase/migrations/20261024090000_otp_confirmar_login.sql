-- OTP manual — fecho automático ao entrar.
-- Hoje o operador carrega em "Marcar como entregue" à mão. Como o GoTrue não tem hook de "código
-- validado", é a app do cliente que, logo após o login com sucesso, chama este RPC para marcar como
-- usado o código do PRÓPRIO número. A linha sai da lista do operador no próximo refresh (o ecrã
-- recarrega de 8 em 8 s). Rede de segurança: o código expira na mesma em 10 min.
--
-- Segurança: SECURITY DEFINER (a tabela está revogada de authenticated), mas o telefone vem de
-- auth.users pelo auth.uid() da sessão, por isso um cliente só pode fechar o SEU próprio código.
create or replace function otp_confirmar()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tel text;
begin
  select phone into v_tel from auth.users where id = auth.uid();
  if v_tel is null then
    return;  -- sessão sem telefone (ex.: login por outro meio): nada a fazer
  end if;
  -- compara só os dígitos (a tabela guarda "+244…"; o auth.users pode ter sem "+")
  update otp_pendentes
     set usado = true, entregue_em = coalesce(entregue_em, now())
   where not usado
     and regexp_replace(telefone, '\D', '', 'g') = regexp_replace(v_tel, '\D', '', 'g');
end $$;

revoke execute on function otp_confirmar() from public, anon;
grant  execute on function otp_confirmar() to authenticated;
