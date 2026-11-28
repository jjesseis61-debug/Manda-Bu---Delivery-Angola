-- =============================================================================
-- Avisos do cliente: (A) sino dentro da app/PWA e (B) notificações push na web (PWA)
-- -----------------------------------------------------------------------------
-- A) O cliente passa a ter, como a equipa, um histórico dos avisos dentro da app (e da PWA),
--    com contador de não lidos. Lê a mesma fila (notificacoes_fila) que o push já usa.
-- B) Na PWA o navegador regista uma "assinatura" Web Push (endpoint + chaves). Guarda-se em
--    dispositivos_push com app = 'web'; a função de envio (enviar-notificacoes) manda estas
--    pelo protocolo Web Push (chaves VAPID) e as outras pela Expo, como até aqui.
--    As chaves VAPID são geradas pela PRÓPRIA função de envio na 1.ª vez e guardadas em
--    segredos_servidor (só o servidor lê): a chave privada nunca passa por pessoas nem pelo
--    repositório. A app pede só a chave pública (chave_publica_push_web).
-- =============================================================================

-- ---------------------------------------------------------------- A. Sino do cliente
create index if not exists notificacoes_fila_cliente_novas_idx
  on notificacoes_fila (cliente_id, criado_em desc)
  where cliente_id is not null and deletado_em is null;

create or replace function meus_avisos(p_limite int default 30)
returns table (id uuid, codigo text, titulo text, corpo text, dados jsonb,
               criado_em timestamptz, vista_em timestamptz)
language sql stable security definer set search_path = public as $$
  select n.id, n.codigo, t.titulo, t.corpo, n.dados, n.criado_em, n.vista_em
    from notificacoes_fila n
    cross join lateral texto_notificacao(n.codigo, n.dados) t
   where n.cliente_id = cliente_actual() and n.deletado_em is null
     and t.corpo is not null
   order by n.criado_em desc
   limit greatest(1, least(coalesce(p_limite, 30), 100));
$$;

create or replace function contar_avisos_novos()
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from notificacoes_fila
   where cliente_id = cliente_actual() and deletado_em is null and vista_em is null;
$$;

create or replace function marcar_avisos_vistos(p_ids uuid[] default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v int;
begin
  if cliente_actual() is null then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  update notificacoes_fila set vista_em = now(), atualizado_em = now()
   where cliente_id = cliente_actual() and deletado_em is null and vista_em is null
     and (p_ids is null or id = any(p_ids));
  get diagnostics v = row_count;
  return v;
end $$;

revoke execute on function meus_avisos(int), contar_avisos_novos(), marcar_avisos_vistos(uuid[]) from public, anon;
grant  execute on function meus_avisos(int), contar_avisos_novos(), marcar_avisos_vistos(uuid[]) to authenticated;

-- ---------------------------------------------------------------- B. Push na web (PWA)
alter table dispositivos_push drop constraint if exists dispositivos_push_app_chk;
alter table dispositivos_push add constraint dispositivos_push_app_chk
  check (app is null or app in ('cliente', 'operador', 'estafeta', 'web'));

-- Assinatura Web Push deste navegador. O "token" guardado é o JSON da assinatura
-- ({endpoint, keys:{p256dh, auth}}), que a função de envio usa tal e qual.
create or replace function registar_push_web(p_endpoint text, p_p256dh text, p_auth text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  v_token   text;
begin
  if v_cliente is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  if p_endpoint is null or p_endpoint !~ '^https://[^\s]+$' or length(p_endpoint) > 1000
     or p_p256dh is null or p_p256dh !~ '^[A-Za-z0-9_=-]{40,200}$'
     or p_auth is null or p_auth !~ '^[A-Za-z0-9_=-]{8,100}$' then
    raise exception 'token_invalido' using errcode = 'P0001';
  end if;
  v_token := jsonb_build_object('endpoint', p_endpoint,
                                'keys', jsonb_build_object('p256dh', p_p256dh, 'auth', p_auth))::text;
  -- O mesmo navegador pode renovar as chaves: a assinatura antiga deste endpoint sai
  update dispositivos_push set activo = false, atualizado_em = now()
   where app = 'web' and token <> v_token
     and (case when app = 'web' and token like '{%' then token::jsonb ->> 'endpoint' end) = p_endpoint;
  insert into dispositivos_push (cliente_id, token, plataforma, activo, dispositivo_id, app)
  values (v_cliente, v_token, 'web', true, 'servidor', 'web')
  on conflict (token) do update
    set cliente_id = excluded.cliente_id, funcionario_id = null, plataforma = 'web',
        activo = true, atualizado_em = now(), deletado_em = null, app = 'web';
end $$;
revoke execute on function registar_push_web(text, text, text) from public, anon;
grant  execute on function registar_push_web(text, text, text) to authenticated;

-- Desligar os avisos deste navegador (ou ao sair da conta)
create or replace function remover_push_web(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  update dispositivos_push set activo = false, atualizado_em = now()
   where app = 'web' and cliente_id = cliente_actual()
     and (case when app = 'web' and token like '{%' then token::jsonb ->> 'endpoint' end) = p_endpoint;
$$;
revoke execute on function remover_push_web(text) from public, anon;
grant  execute on function remover_push_web(text) to authenticated;

-- Chaves VAPID (Web Push), guardadas só no servidor
create or replace function chaves_push_web()
returns table (publica text, privada text)
language sql stable security definer set search_path = public as $$
  select (select valor from segredos_servidor where chave = 'vapid_publica'),
         (select valor from segredos_servidor where chave = 'vapid_privada');
$$;
revoke execute on function chaves_push_web() from public, anon, authenticated;
grant  execute on function chaves_push_web() to service_role;

-- A função de envio grava o par que gerou; se já existir um (corrida), fica o primeiro
create or replace function guardar_chaves_push_web(p_publica text, p_privada text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_publica !~ '^[A-Za-z0-9_-]{80,100}$' or p_privada !~ '^[A-Za-z0-9_-]{40,50}$' then
    raise exception 'chave_invalida' using errcode = 'P0001';
  end if;
  if exists (select 1 from segredos_servidor where chave in ('vapid_publica', 'vapid_privada')) then
    return;
  end if;
  insert into segredos_servidor (chave, valor) values ('vapid_publica', p_publica), ('vapid_privada', p_privada);
end $$;
revoke execute on function guardar_chaves_push_web(text, text) from public, anon, authenticated;
grant  execute on function guardar_chaves_push_web(text, text) to service_role;

-- A chave PÚBLICA (é pública por natureza: o navegador precisa dela para se inscrever)
create or replace function chave_publica_push_web()
returns text language sql stable security definer set search_path = public as $$
  select valor from segredos_servidor where chave = 'vapid_publica';
$$;
revoke execute on function chave_publica_push_web() from public, anon;
grant  execute on function chave_publica_push_web() to authenticated;
