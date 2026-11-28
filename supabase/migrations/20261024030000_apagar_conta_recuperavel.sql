-- Apagar a conta passa a ser RECUPERÁVEL durante 60 dias (soft-delete). A purga definitiva é por job.
-- Retenção: os dados financeiros ficam para sempre (anónimos); o nome+NIF ficam ligados às transações
-- enquanto houver obrigação fiscal (5 anos); o resto do pessoal sai aos 60 dias. Apagar revoga todas
-- as sessões (logout em todos os dispositivos), mas mantém o utilizador da Auth para poder recuperar.

alter table clientes
  add column if not exists suspensa_em   timestamptz,
  add column if not exists purgar_em     timestamptz,
  add column if not exists desativada_em timestamptz;

-- 1. Apagar = soft-delete recuperável. Mantém dados e utilizador da Auth; revoga sessões.
create or replace function apagar_conta() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_cliente uuid := cliente_actual();
begin
  if v_uid is null or v_cliente is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  if exists (select 1 from pedidos where cliente_id = v_cliente and deletado_em is null
                and estado in ('pendente', 'confirmado', 'em_preparacao', 'em_entrega')) then
    raise exception 'pedido_em_curso' using errcode = 'P0001';
  end if;
  if exists (select 1 from pagamentos_indicacao where indicador_id = v_cliente and deletado_em is null
                and estado in ('pedido', 'aprovado')) then
    raise exception 'levantamento_em_curso' using errcode = 'P0001';
  end if;
  if exists (select 1 from pedidos_grupo where organizador_id = v_cliente and deletado_em is null
                and estado in ('aberto', 'fechado', 'em_preparacao')) then
    raise exception 'grupo_em_curso' using errcode = 'P0001';
  end if;

  update clientes
     set suspensa_em = now(), purgar_em = now() + interval '60 days', atualizado_em = now()
   where id = v_cliente;
  update dispositivos_push set activo = false, atualizado_em = now()
   where cliente_id = v_cliente and deletado_em is null;
  update perfil_destaques set sair_da_lista = true, mostrar_nome_real = false, atualizado_em = now()
   where cliente_id = v_cliente;

  -- Logout em todos os dispositivos (revoga as sessões); mantém o utilizador da Auth p/ recuperar
  if to_regclass('auth.sessions') is not null then
    delete from auth.sessions where user_id = v_uid;
  end if;

  perform registar_auditoria('cliente_suspendeu_conta', 'clientes', v_cliente, '{}'::jsonb, false);
end $$;

-- 2. Recuperar a conta dentro dos 60 dias
create or replace function recuperar_conta() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  v_susp    timestamptz;
  v_purgar  timestamptz;
  v_desat   timestamptz;
begin
  if v_cliente is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  select suspensa_em, purgar_em, desativada_em into v_susp, v_purgar, v_desat
    from clientes where id = v_cliente;
  if v_susp is null then
    raise exception 'conta_activa' using errcode = 'P0001';
  end if;
  if v_desat is not null or (v_purgar is not null and v_purgar < now()) then
    raise exception 'fora_do_prazo' using errcode = 'P0001';
  end if;
  update clientes set suspensa_em = null, purgar_em = null, atualizado_em = now() where id = v_cliente;
  update perfil_destaques set sair_da_lista = false, atualizado_em = now() where cliente_id = v_cliente;
  perform registar_auditoria('cliente_recuperou_conta', 'clientes', v_cliente, '{}'::jsonb, false);
end $$;

-- 3. meu_perfil passa a indicar se a conta está suspensa (recuperável) e até quando
create or replace function meu_perfil() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'cliente_id', c.id,
           'nome', c.nome,
           'primeiro_nome', split_part(trim(c.nome), ' ', 1),
           'tipo', c.tipo,
           'telefone', c.telefone,
           'codigo', ci.codigo,
           'pseudonimo', pd.pseudonimo,
           'suspensa', c.suspensa_em is not null,
           'recuperar_ate', c.purgar_em,
           'tem_ligacao', exists (select 1 from ligacoes_indicacao l
                                   where l.indicado_id = c.id and l.deletado_em is null),
           'cliente_novo', not cliente_ja_comprou(c.id))
    from clientes c
    left join codigos_indicacao ci on ci.cliente_id = c.id
    left join perfil_destaques pd on pd.cliente_id = c.id
   where c.auth_user_id = auth.uid() and auth.uid() is not null and c.deletado_em is null;
$$;

-- 4. Purga automática (job diário): 60 dias (pessoal de app) e 5 anos (nome+NIF, fiscal)
create or replace function job_purgar_contas() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_auth uuid[];
begin
  -- a) 60 dias: anonimiza o pessoal de app, liberta o número e apaga o utilizador da Auth.
  --    Guarda nome + NIF (ligados às transações) por obrigação fiscal.
  select array_agg(c.auth_user_id)
    into v_auth
    from clientes c
   where c.suspensa_em is not null and c.desativada_em is null
     and c.purgar_em is not null and c.purgar_em < now() and c.auth_user_id is not null;

  update enderecos_cliente e set deletado_em = now(), atualizado_em = now()
    from clientes c
   where e.cliente_id = c.id and e.deletado_em is null
     and c.suspensa_em is not null and c.desativada_em is null
     and c.purgar_em is not null and c.purgar_em < now();

  update clientes c
     set telefone = null, pessoa_contacto = null, auth_user_id = null,
         desativada_em = now(), deletado_em = now(), dispositivo_id = 'servidor', atualizado_em = now()
   where c.suspensa_em is not null and c.desativada_em is null
     and c.purgar_em is not null and c.purgar_em < now();

  if to_regclass('auth.users') is not null and v_auth is not null then
    delete from auth.users u
     where u.id = any (v_auth)
       and not exists (select 1 from funcionarios f where f.auth_user_id = u.id);
  end if;

  -- b) 5 anos sem atividade: apaga o nome e o NIF (erasure fiscal final).
  update clientes c
     set nome = 'Cliente removido', nif = null, atualizado_em = now()
   where c.desativada_em is not null and c.nome <> 'Cliente removido'
     and not exists (
       select 1 from pedidos p
        where p.cliente_id = c.id and p.deletado_em is null
          and coalesce(p.entregue_em, p.criado_em) > now() - interval '5 years');
end $$;

-- 5. Privilégios
revoke execute on function recuperar_conta()  from public, anon;
grant  execute on function recuperar_conta()  to authenticated;
revoke execute on function job_purgar_contas() from public, anon, authenticated;

-- 6. Agendar a purga (de madrugada). Guardado: o pg_cron não existe no cluster de testes.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('mb_purgar_contas', '0 3 * * *', 'select public.job_purgar_contas()');
  end if;
end $$;
