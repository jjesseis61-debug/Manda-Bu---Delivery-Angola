-- OTP manual — confirmação visível de login ("login realizado").
-- Quando o cliente entra, além de fechar o código em silêncio, mostra-se ao operador uma confirmação
-- ("✓ Login de Ana realizado · há N min") que dura 5 minutos e some sozinha (sem agendador, filtro na
-- leitura). O nome é capturado no login (primeiro nome do perfil; se ainda não houver perfil — 1.º
-- login — fica …últimos 3 dígitos). A confirmação não mostra o código (já foi usado). Fica na auditoria.

alter table otp_pendentes
  add column confirmado_em   timestamptz,
  add column confirmado_nome text;

-- otp_confirmar: fecha o código do próprio número, guarda a confirmação (nome + instante) e audita.
create or replace function otp_confirmar()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tel  text;
  v_nome text;
  v_rid  uuid;
begin
  select phone into v_tel from auth.users where id = auth.uid();
  if v_tel is null then
    return;  -- sessão sem telefone: nada a fazer
  end if;
  -- primeiro nome do perfil (se já existir); senão …últimos 3 dígitos do telefone
  select split_part(trim(nome), ' ', 1) into v_nome
    from clientes where auth_user_id = auth.uid() and deletado_em is null
    order by criado_em limit 1;
  v_nome := coalesce(nullif(v_nome, ''), '…' || right(regexp_replace(v_tel, '\D', '', 'g'), 3));
  -- fecha o(s) código(s) do próprio número (compara só dígitos) e regista a confirmação
  for v_rid in
    update otp_pendentes
       set usado = true,
           entregue_em = coalesce(entregue_em, now()),
           confirmado_em = now(),
           confirmado_nome = v_nome
     where not usado
       and regexp_replace(telefone, '\D', '', 'g') = regexp_replace(v_tel, '\D', '', 'g')
    returning id
  loop
    perform registar_auditoria('otp_login', 'otp', v_rid,
      jsonb_build_object('tel_mascarado', right(regexp_replace(v_tel, '\D', '', 'g'), 3)));
  end loop;
end $$;
revoke execute on function otp_confirmar() from public, anon;
grant  execute on function otp_confirmar() to authenticated;

-- Lista do operador: os códigos pendentes (como antes) e, por cima, as confirmações de login dos
-- últimos 5 minutos (no máximo as 10 mais recentes), sem o código. `estado` distingue as duas.
-- (Muda o tipo de retorno — é preciso largar a função antiga primeiro.)
drop function if exists otp_pendentes_lista();
create or replace function otp_pendentes_lista()
returns table (id uuid, telefone text, codigo text, criado_em timestamptz, expira_em timestamptz,
               estado text, nome text, confirmado_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_permissao('otp.entregar');
  return query
  with pend as (
    select o.id, o.telefone, o.codigo, o.criado_em, o.expira_em,
           'pendente'::text as estado, null::text as nome, null::timestamptz as confirmado_em
      from otp_pendentes o
     where not o.usado and o.expira_em > now()
     order by o.criado_em desc
     limit 50
  ), conf as (
    select o.id, o.telefone, null::text as codigo, o.criado_em, o.expira_em,
           'confirmado'::text as estado, o.confirmado_nome as nome, o.confirmado_em
      from otp_pendentes o
     where o.usado and o.confirmado_em is not null and o.confirmado_em > now() - interval '5 minutes'
     order by o.confirmado_em desc
     limit 10
  )
  select * from pend
  union all
  select * from conf;
end $$;
revoke execute on function otp_pendentes_lista() from public, anon;
grant  execute on function otp_pendentes_lista() to authenticated;
