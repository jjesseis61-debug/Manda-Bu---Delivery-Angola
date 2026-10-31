-- Auditoria de login para TODOS os números, incluindo os números de teste do painel.
-- Antes, o 'otp_login' só era registado quando havia um código pendente (o hook grava-o). Os números
-- de teste do Supabase não passam pelo hook, logo o login deles não ficava registado. Agora o
-- otp_confirmar regista o login na mesma, mesmo sem código pendente (com dedup curto para não
-- duplicar quando a app chama o RPC mais do que uma vez).
create or replace function otp_confirmar()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tel     text;
  v_nome    text;
  v_mascara text;
  v_rid     uuid;
  v_houve   boolean := false;
begin
  select phone into v_tel from auth.users where id = auth.uid();
  if v_tel is null then
    return;  -- sessão sem telefone: nada a fazer
  end if;
  v_mascara := right(regexp_replace(v_tel, '\D', '', 'g'), 3);
  -- primeiro nome do perfil (se já existir); senão …últimos 3 dígitos
  select split_part(trim(nome), ' ', 1) into v_nome
    from clientes where auth_user_id = auth.uid() and deletado_em is null
    order by criado_em limit 1;
  v_nome := coalesce(nullif(v_nome, ''), '…' || v_mascara);
  -- fecha o(s) código(s) do próprio número e regista a confirmação
  for v_rid in
    update otp_pendentes
       set usado = true, entregue_em = coalesce(entregue_em, now()),
           confirmado_em = now(), confirmado_nome = v_nome
     where not usado
       and regexp_replace(telefone, '\D', '', 'g') = regexp_replace(v_tel, '\D', '', 'g')
    returning id
  loop
    perform registar_auditoria('otp_login', 'otp', v_rid, jsonb_build_object('tel_mascarado', v_mascara));
    v_houve := true;
  end loop;
  -- número sem código pendente (ex.: número de teste): regista o login na mesma, sem duplicar se já
  -- houve um registo com estes 3 dígitos há menos de 2 minutos (dedup aproximado, por privacidade)
  if not v_houve
     and not exists (select 1 from auditoria
                      where acao = 'otp_login' and ref_tipo = 'otp'
                        and criado_em > now() - interval '2 minutes'
                        and detalhe::jsonb ->> 'tel_mascarado' = v_mascara) then
    perform registar_auditoria('otp_login', 'otp', null,
      jsonb_build_object('tel_mascarado', v_mascara, 'sem_codigo', true));
  end if;
end $$;
revoke execute on function otp_confirmar() from public, anon;
grant  execute on function otp_confirmar() to authenticated;
