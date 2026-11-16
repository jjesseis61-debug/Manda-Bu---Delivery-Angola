-- =============================================================================
-- Cozinha de condomínio — Fase 1
-- -----------------------------------------------------------------------------
-- Decisões do dono (16/11/2026):
--  * O condomínio é uma área no mapa (centro + raio). O GPS do telemóvel decide o que o cliente VÊ;
--    o servidor confirma que o ENDEREÇO de entrega do pedido está dentro do condomínio (o GPS do
--    telemóvel pode ser falsificado). Margem de 50 m para não piscar à entrada.
--  * Só os membros activos da lista vêem a cozinha do condomínio, e só lá dentro. Com ela aberta vêem
--    só essa cozinha; fechada vêem "Cozinha fechada" e as outras cozinhas; ao fim de 12 horas fechada
--    deixa de aparecer (volta quando reabrir).
--  * Entregas: estafeta da cozinha ou serviço contratado (modo_entrega + nome do parceiro).
--  * Lista de moradores: a cozinha acrescenta pelo telefone ou o morador pede pelo link (código).
--    O operador define as vagas; com as vagas cheias (ou depois da data limite, ou fechada à mão) a
--    lista fecha sozinha. Entrada automática até encher, ou com aprovação da cozinha (opcional).
--  * Taxa de entrega: a da zona do condomínio, se tiver uma (assim também conta a entrega grátis por
--    zona e o relatório "o que mais sai em cada zona").
-- Tudo atrás do interruptor 'condominios' (nasce desligado). Precisa de 'multi_cozinha' ligado.
-- =============================================================================

insert into funcionalidades (chave, activa, dispositivo_id) values ('condominios', false, 'servidor')
  on conflict (chave) do nothing;

-- -----------------------------------------------------------------------------
-- Cozinha aberta / fechada (serve todas as cozinhas; por defeito aberta, nada muda)
-- -----------------------------------------------------------------------------
alter table cozinhas add column if not exists aberta boolean not null default true;
alter table cozinhas add column if not exists fechada_desde timestamptz;
alter table cozinhas add column if not exists reabre_em timestamptz;
comment on column cozinhas.aberta is 'A cozinha está a aceitar pedidos agora (botão Abrir/Fechar). Só o servidor escreve.';
comment on column cozinhas.fechada_desde is 'Quando foi fechada (conta as 12 horas da cozinha de condomínio)';
comment on column cozinhas.reabre_em is 'Hora prevista de reabertura indicada pela cozinha (opcional)';

-- As colunas de abrir/fechar só mudam pela função abrir_fechar_cozinha
create or replace function cozinhas_proteger_abertura() returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('mb.abrir_fechar', true), '') <> '1' then
    new.aberta := old.aberta;
    new.fechada_desde := old.fechada_desde;
    new.reabre_em := old.reabre_em;
  end if;
  return new;
end $$;
revoke execute on function cozinhas_proteger_abertura() from public, anon, authenticated;
drop trigger if exists trg_cozinhas_abertura on cozinhas;
create trigger trg_cozinhas_abertura before update on cozinhas
  for each row execute function cozinhas_proteger_abertura();

-- Uma cozinha fechada não aceita pedidos (acrescentado à definição actual, sem a copiar)
do $$
declare
  v_def  text := pg_get_functiondef('cozinha_aceita_pedidos(uuid)'::regprocedure);
  v_novo text;
begin
  if position('c.aberta' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(c\.estado\s*=\s*''activa'')', E'\\1 and c.aberta');
  if v_novo = v_def then raise exception 'cozinha_aceita_pedidos não tem o formato esperado'; end if;
  execute v_novo;
end $$;

create or replace function abrir_fechar_cozinha(p_cozinha uuid, p_aberta boolean, p_reabre_em timestamptz default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not pode_na_cozinha('pedidos.gerir', p_cozinha) then
    raise exception 'sem_permissao' using errcode = '42501', detail = 'pedidos.gerir';
  end if;
  if not exists (select 1 from cozinhas where id = p_cozinha and deletado_em is null) then
    raise exception 'cozinha_inexistente' using errcode = 'P0001';
  end if;
  if not coalesce(p_aberta, true) and p_reabre_em is not null
     and (p_reabre_em < now() or p_reabre_em > now() + interval '30 days') then
    raise exception 'hora_invalida' using errcode = 'P0001';
  end if;
  perform set_config('mb.abrir_fechar', '1', true);
  update cozinhas
     set aberta = coalesce(p_aberta, true),
         fechada_desde = case when coalesce(p_aberta, true) then null
                              when aberta then now() else coalesce(fechada_desde, now()) end,
         reabre_em = case when coalesce(p_aberta, true) then null else p_reabre_em end,
         atualizado_em = now()
   where id = p_cozinha;
  perform set_config('mb.abrir_fechar', '', true);
  perform registar_auditoria(case when coalesce(p_aberta, true) then 'cozinha_aberta' else 'cozinha_fechada' end,
                             'cozinhas', p_cozinha, jsonb_build_object('reabre_em', p_reabre_em));
end $$;
revoke execute on function abrir_fechar_cozinha(uuid, boolean, timestamptz) from public, anon;
grant  execute on function abrir_fechar_cozinha(uuid, boolean, timestamptz) to authenticated;

-- -----------------------------------------------------------------------------
-- Condomínios e membros
-- -----------------------------------------------------------------------------
create table if not exists condominios (
  id                 uuid primary key default gen_random_uuid(),
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  deletado_em        timestamptz,
  nome               text not null check (length(trim(nome)) between 2 and 80),
  cozinha_id         uuid not null references cozinhas(id),
  zona_id            uuid references zonas(id),
  centro_lat         double precision not null check (centro_lat between -90 and 90),
  centro_lng         double precision not null check (centro_lng between -180 and 180),
  raio_m             int not null default 300 check (raio_m between 30 and 5000),
  vagas              int not null default 50 check (vagas between 1 and 100000),
  inscricoes_ate     timestamptz,
  inscricoes_abertas boolean not null default true,
  aprovacao_manual   boolean not null default false,
  modo_entrega       text not null default 'cozinha' check (modo_entrega in ('cozinha', 'parceiro')),
  parceiro_nome      text check (parceiro_nome is null or length(parceiro_nome) <= 80),
  codigo             text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8))
);
comment on table condominios is 'Cozinha de condomínio: área (centro + raio), lista de moradores com vagas e modo de entrega';
-- Uma cozinha serve no máximo um condomínio
create unique index if not exists condominios_cozinha_unica on condominios (cozinha_id) where deletado_em is null;

create table if not exists condominio_membros (
  id             uuid primary key default gen_random_uuid(),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  condominio_id  uuid not null references condominios(id),
  cliente_id     uuid not null references clientes(id),
  estado         text not null default 'activo' check (estado in ('pendente', 'activo', 'recusado', 'removido')),
  bloco          text check (bloco is null or length(bloco) <= 40),
  casa           text check (casa is null or length(casa) <= 40),
  origem         text not null default 'link' check (origem in ('link', 'cozinha')),
  aprovado_em    timestamptz,
  removido_em    timestamptz
);
create unique index if not exists condominio_membros_um_por_cliente
  on condominio_membros (condominio_id, cliente_id) where estado in ('pendente', 'activo');
create index if not exists condominio_membros_cliente on condominio_membros (cliente_id);
create index if not exists condominios_zona on condominios (zona_id);

-- Só pelas funções abaixo (sem acesso directo das apps)
alter table condominios enable row level security;
alter table condominio_membros enable row level security;
revoke all on condominios, condominio_membros from anon, authenticated;

drop trigger if exists trg_auditar on condominios;
create trigger trg_auditar after insert or update or delete on condominios
  for each row execute function auditar_alteracao_tabela();

-- Distância em metros entre dois pontos (haversine)
create or replace function distancia_m(lat1 double precision, lng1 double precision,
                                       lat2 double precision, lng2 double precision)
returns double precision language sql immutable set search_path = public as $$
  select 6371000 * acos(least(1, greatest(-1,
           cos(radians(lat1)) * cos(radians(lat2)) * cos(radians(lng2) - radians(lng1))
           + sin(radians(lat1)) * sin(radians(lat2)))));
$$;
revoke execute on function distancia_m(double precision, double precision, double precision, double precision) from public, anon, authenticated;

-- A cozinha é de um condomínio?
create or replace function condominio_da_cozinha(p_cozinha uuid)
returns condominios language sql stable security definer set search_path = public as $$
  select * from condominios where cozinha_id = p_cozinha and deletado_em is null limit 1;
$$;
revoke execute on function condominio_da_cozinha(uuid) from public, anon, authenticated;

-- Vagas ocupadas (activos + pendentes, para a lista não passar das vagas)
create or replace function condominio_ocupadas(p_cond uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from condominio_membros where condominio_id = p_cond and estado in ('activo', 'pendente');
$$;
revoke execute on function condominio_ocupadas(uuid) from public, anon, authenticated;

-- A lista aceita entradas? (aberta à mão, antes da data limite e com vagas)
create or replace function condominio_lista_aberta(c condominios)
returns boolean language sql stable security definer set search_path = public as $$
  select c.deletado_em is null and c.inscricoes_abertas
     and (c.inscricoes_ate is null or now() < c.inscricoes_ate)
     and condominio_ocupadas(c.id) < c.vagas;
$$;
revoke execute on function condominio_lista_aberta(condominios) from public, anon, authenticated;

-- O cliente é membro activo do condomínio?
create or replace function condominio_membro_activo(p_cond uuid, p_cliente uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from condominio_membros
                  where condominio_id = p_cond and cliente_id = p_cliente and estado = 'activo');
$$;
revoke execute on function condominio_membro_activo(uuid, uuid) from public, anon, authenticated;

-- Quem gere um condomínio: cozinhas.gerir, ou pedidos.gerir na cozinha do condomínio
create or replace function pode_gerir_condominio(p_cond uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select tem_permissao('cozinhas.gerir')
      or exists (select 1 from condominios c where c.id = p_cond and pode_na_cozinha('pedidos.gerir', c.cozinha_id));
$$;
revoke execute on function pode_gerir_condominio(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Operador: criar/editar condomínios e ver a lista
-- -----------------------------------------------------------------------------
create or replace function guardar_condominio(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid := nullif(p ->> 'id', '')::uuid;
  v_coz  uuid := (p ->> 'cozinha_id')::uuid;
begin
  perform exigir_permissao('cozinhas.gerir');
  if v_coz is null or not exists (select 1 from cozinhas where id = v_coz and deletado_em is null) then
    raise exception 'cozinha_inexistente' using errcode = 'P0001';
  end if;
  -- A cozinha principal recebe os pedidos de todos; não pode ficar escondida num condomínio
  if v_coz = cozinha_padrao() then
    raise exception 'cozinha_principal_nao' using errcode = 'P0001';
  end if;
  if exists (select 1 from condominios where cozinha_id = v_coz and deletado_em is null and id is distinct from v_id) then
    raise exception 'cozinha_ja_tem_condominio' using errcode = 'P0001';
  end if;
  if v_id is null then
    insert into condominios (nome, cozinha_id, zona_id, centro_lat, centro_lng, raio_m, vagas, inscricoes_ate,
                             inscricoes_abertas, aprovacao_manual, modo_entrega, parceiro_nome)
    values (trim(p ->> 'nome'), v_coz, nullif(p ->> 'zona_id', '')::uuid,
            (p ->> 'centro_lat')::double precision, (p ->> 'centro_lng')::double precision,
            coalesce((p ->> 'raio_m')::int, 300), coalesce((p ->> 'vagas')::int, 50),
            nullif(p ->> 'inscricoes_ate', '')::timestamptz, coalesce((p ->> 'inscricoes_abertas')::boolean, true),
            coalesce((p ->> 'aprovacao_manual')::boolean, false), coalesce(p ->> 'modo_entrega', 'cozinha'),
            nullif(trim(p ->> 'parceiro_nome'), ''))
    returning id into v_id;
  else
    update condominios
       set nome = trim(p ->> 'nome'), cozinha_id = v_coz, zona_id = nullif(p ->> 'zona_id', '')::uuid,
           centro_lat = (p ->> 'centro_lat')::double precision, centro_lng = (p ->> 'centro_lng')::double precision,
           raio_m = coalesce((p ->> 'raio_m')::int, raio_m), vagas = coalesce((p ->> 'vagas')::int, vagas),
           inscricoes_ate = nullif(p ->> 'inscricoes_ate', '')::timestamptz,
           inscricoes_abertas = coalesce((p ->> 'inscricoes_abertas')::boolean, inscricoes_abertas),
           aprovacao_manual = coalesce((p ->> 'aprovacao_manual')::boolean, aprovacao_manual),
           modo_entrega = coalesce(p ->> 'modo_entrega', modo_entrega),
           parceiro_nome = nullif(trim(p ->> 'parceiro_nome'), ''),
           atualizado_em = now()
     where id = v_id and deletado_em is null;
    if not found then raise exception 'condominio_inexistente' using errcode = 'P0001'; end if;
  end if;
  return v_id;
end $$;
revoke execute on function guardar_condominio(jsonb) from public, anon;
grant  execute on function guardar_condominio(jsonb) to authenticated;

create or replace function apagar_condominio(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('cozinhas.gerir');
  update condominios set deletado_em = now(), atualizado_em = now() where id = p_id and deletado_em is null;
  if not found then raise exception 'condominio_inexistente' using errcode = 'P0001'; end if;
end $$;
revoke execute on function apagar_condominio(uuid) from public, anon;
grant  execute on function apagar_condominio(uuid) to authenticated;

-- Condomínios que o funcionário gere, com os números da lista
create or replace function condominios_lista()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'nome', c.nome, 'cozinha_id', c.cozinha_id, 'cozinha', k.nome, 'zona_id', c.zona_id, 'zona', z.nome,
    'centro_lat', c.centro_lat, 'centro_lng', c.centro_lng, 'raio_m', c.raio_m, 'vagas', c.vagas,
    'inscricoes_ate', c.inscricoes_ate, 'inscricoes_abertas', c.inscricoes_abertas,
    'aprovacao_manual', c.aprovacao_manual, 'modo_entrega', c.modo_entrega, 'parceiro_nome', c.parceiro_nome,
    'codigo', c.codigo, 'lista_aberta', condominio_lista_aberta(c),
    'cozinha_aberta', k.aberta, 'fechada_desde', k.fechada_desde, 'reabre_em', k.reabre_em,
    'activos', (select count(*) from condominio_membros m where m.condominio_id = c.id and m.estado = 'activo'),
    'pendentes', (select count(*) from condominio_membros m where m.condominio_id = c.id and m.estado = 'pendente'),
    'activos_30d', (select count(distinct m.cliente_id) from condominio_membros m
                      join pedidos p on p.cliente_id = m.cliente_id and p.cozinha_id = c.cozinha_id
                     where m.condominio_id = c.id and m.estado = 'activo' and p.deletado_em is null
                       and p.criado_em > now() - interval '30 days')
  ) order by c.nome), '[]')
  from condominios c
  join cozinhas k on k.id = c.cozinha_id
  left join zonas z on z.id = c.zona_id
  where c.deletado_em is null and pode_gerir_condominio(c.id);
$$;
revoke execute on function condominios_lista() from public, anon;
grant  execute on function condominios_lista() to authenticated;

-- Membros de um condomínio (só para quem o gere)
create or replace function condominio_membros_lista(p_cond uuid)
returns table (id uuid, cliente_nome text, telefone text, bloco text, casa text, estado text, origem text,
               criado_em timestamptz, ultimo_pedido timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not pode_gerir_condominio(p_cond) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
  select m.id, cl.nome, cl.telefone, m.bloco, m.casa, m.estado, m.origem, m.criado_em,
         (select max(p.criado_em) from pedidos p join condominios c on c.id = m.condominio_id
           where p.cliente_id = m.cliente_id and p.cozinha_id = c.cozinha_id and p.deletado_em is null)
    from condominio_membros m join clientes cl on cl.id = m.cliente_id
   where m.condominio_id = p_cond and m.estado in ('pendente', 'activo')
   order by m.estado = 'pendente' desc, cl.nome;
end $$;
revoke execute on function condominio_membros_lista(uuid) from public, anon;
grant  execute on function condominio_membros_lista(uuid) to authenticated;

-- A cozinha acrescenta um morador pelo telefone (fica activo; respeita as vagas, não a data limite)
create or replace function condominio_adicionar_membro(p_cond uuid, p_telefone text, p_bloco text default null, p_casa text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  c        condominios;
  v_cli    uuid;
  v_id     uuid;
begin
  if not pode_gerir_condominio(p_cond) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select * into c from condominios where id = p_cond and deletado_em is null for update;
  if not found then raise exception 'condominio_inexistente' using errcode = 'P0001'; end if;
  select id into v_cli from clientes
   where normalizar_telefone(telefone) = normalizar_telefone(p_telefone) and deletado_em is null
   order by criado_em limit 1;
  if v_cli is null then
    raise exception 'cliente_nao_encontrado' using errcode = 'P0001',
      detail = 'O morador tem de criar conta na app com este número';
  end if;
  select id into v_id from condominio_membros
   where condominio_id = p_cond and cliente_id = v_cli and estado in ('pendente', 'activo');
  if v_id is not null then
    update condominio_membros
       set estado = 'activo', aprovado_em = coalesce(aprovado_em, now()), atualizado_em = now(),
           bloco = coalesce(nullif(trim(p_bloco), ''), bloco), casa = coalesce(nullif(trim(p_casa), ''), casa)
     where id = v_id;
    return v_id;
  end if;
  if condominio_ocupadas(p_cond) >= c.vagas then
    raise exception 'lista_cheia' using errcode = 'P0001';
  end if;
  insert into condominio_membros (condominio_id, cliente_id, estado, bloco, casa, origem, aprovado_em)
  values (p_cond, v_cli, 'activo', nullif(trim(p_bloco), ''), nullif(trim(p_casa), ''), 'cozinha', now())
  returning id into v_id;
  perform registar_auditoria('condominio_membro_adicionado', 'condominio_membros', v_id, jsonb_build_object('condominio_id', p_cond));
  return v_id;
end $$;
revoke execute on function condominio_adicionar_membro(uuid, text, text, text) from public, anon;
grant  execute on function condominio_adicionar_membro(uuid, text, text, text) to authenticated;

-- Aprovar / recusar / remover um membro
create or replace function condominio_decidir_membro(p_membro uuid, p_accao text)
returns void language plpgsql security definer set search_path = public as $$
declare
  m  condominio_membros;
  c  condominios;
begin
  select * into m from condominio_membros where id = p_membro for update;
  if not found then raise exception 'membro_inexistente' using errcode = 'P0001'; end if;
  if not pode_gerir_condominio(m.condominio_id) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_accao = 'aprovar' then
    if m.estado <> 'pendente' then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
    update condominio_membros set estado = 'activo', aprovado_em = now(), atualizado_em = now() where id = p_membro;
    select * into c from condominios where id = m.condominio_id;
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (m.cliente_id, 'N31', jsonb_build_object('titulo', 'Bem-vindo ao ' || c.nome || ' 🏘️',
              'corpo', 'Já podes pedir na cozinha do condomínio quando estiveres lá.', 'link', '/inicio'));
  elsif p_accao = 'recusar' then
    if m.estado <> 'pendente' then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
    update condominio_membros set estado = 'recusado', atualizado_em = now() where id = p_membro;
  elsif p_accao = 'remover' then
    if m.estado not in ('pendente', 'activo') then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
    update condominio_membros set estado = 'removido', removido_em = now(), atualizado_em = now() where id = p_membro;
  else
    raise exception 'accao_invalida' using errcode = 'P0001';
  end if;
  perform registar_auditoria('condominio_membro_' || p_accao, 'condominio_membros', p_membro,
                             jsonb_build_object('condominio_id', m.condominio_id));
end $$;
revoke execute on function condominio_decidir_membro(uuid, text) from public, anon;
grant  execute on function condominio_decidir_membro(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- App do cliente
-- -----------------------------------------------------------------------------
-- O link: o que o morador vê antes de pedir para entrar (nome, se há vagas e o seu estado)
create or replace function condominio_pelo_codigo(p_codigo text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  c   condominios;
  v_e text;
begin
  if cliente_actual() is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not funcionalidade_activa('condominios') then return null; end if;
  select * into c from condominios where codigo = upper(trim(p_codigo)) and deletado_em is null;
  if not found then return null; end if;
  select estado into v_e from condominio_membros
   where condominio_id = c.id and cliente_id = cliente_actual() and estado in ('pendente', 'activo');
  return jsonb_build_object(
    'nome', c.nome,
    'cozinha', (select nome from cozinhas where id = c.cozinha_id),
    'lista_aberta', condominio_lista_aberta(c),
    'vagas_livres', greatest(c.vagas - condominio_ocupadas(c.id), 0),
    'inscricoes_ate', c.inscricoes_ate,
    'aprovacao_manual', c.aprovacao_manual,
    'meu_estado', v_e);
end $$;
revoke execute on function condominio_pelo_codigo(text) from public, anon;
grant  execute on function condominio_pelo_codigo(text) to authenticated;

-- O morador pede para entrar (pelo link). Devolve 'activo' ou 'pendente'.
create or replace function condominio_pedir_entrada(p_codigo text, p_bloco text, p_casa text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_cli uuid := cliente_actual();
  c     condominios;
  v_e   text;
begin
  if v_cli is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not funcionalidade_activa('condominios') then raise exception 'funcionalidade_inactiva' using errcode = 'P0001'; end if;
  select * into c from condominios where codigo = upper(trim(p_codigo)) and deletado_em is null for update;
  if not found then raise exception 'condominio_inexistente' using errcode = 'P0001'; end if;
  select estado into v_e from condominio_membros
   where condominio_id = c.id and cliente_id = v_cli and estado in ('pendente', 'activo');
  if v_e is not null then return v_e; end if;
  if length(coalesce(trim(p_bloco), '') || coalesce(trim(p_casa), '')) = 0 then
    raise exception 'casa_obrigatoria' using errcode = 'P0001';
  end if;
  if not condominio_lista_aberta(c) then
    raise exception 'lista_fechada' using errcode = 'P0001';
  end if;
  v_e := case when c.aprovacao_manual then 'pendente' else 'activo' end;
  insert into condominio_membros (condominio_id, cliente_id, estado, bloco, casa, origem, aprovado_em)
  values (c.id, v_cli, v_e, nullif(trim(p_bloco), ''), nullif(trim(p_casa), ''), 'link',
          case when v_e = 'activo' then now() end);
  return v_e;
end $$;
revoke execute on function condominio_pedir_entrada(text, text, text) from public, anon;
grant  execute on function condominio_pedir_entrada(text, text, text) to authenticated;

-- O cliente está num condomínio de que é membro? (pelo GPS do telemóvel; só decide o que se vê)
-- visivel = aberta, ou fechada há menos de 12 horas.
create or replace function condominio_aqui(p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r record;
begin
  if cliente_actual() is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if not funcionalidade_activa('condominios') or p_lat is null or p_lng is null then return null; end if;
  select c.id, c.nome, c.cozinha_id, k.nome as cozinha, k.foto_url, k.historia, k.aberta, k.fechada_desde, k.reabre_em,
         k.estado = 'activa' and k.deletado_em is null as activa
    into r
    from condominios c
    join condominio_membros m on m.condominio_id = c.id and m.cliente_id = cliente_actual() and m.estado = 'activo'
    join cozinhas k on k.id = c.cozinha_id
   where c.deletado_em is null
     and distancia_m(p_lat, p_lng, c.centro_lat, c.centro_lng) <= c.raio_m + 50
   order by distancia_m(p_lat, p_lng, c.centro_lat, c.centro_lng)
   limit 1;
  if not found or not r.activa then return null; end if;
  return jsonb_build_object(
    'condominio_id', r.id, 'nome', r.nome, 'cozinha_id', r.cozinha_id, 'cozinha', r.cozinha,
    'foto_url', r.foto_url, 'historia', r.historia,
    'aberta', r.aberta, 'reabre_em', r.reabre_em,
    'visivel', r.aberta or r.fechada_desde is null or r.fechada_desde > now() - interval '12 hours',
    'pratos', (select count(*)::int from cardapio m where m.cozinha_id = r.cozinha_id and m.disponivel and m.deletado_em is null));
end $$;
revoke execute on function condominio_aqui(double precision, double precision) from public, anon;
grant  execute on function condominio_aqui(double precision, double precision) to authenticated;

-- Os meus condomínios (estado da entrada)
create or replace function meus_condominios()
returns table (nome text, estado text, bloco text, casa text)
language sql stable security definer set search_path = public as $$
  select c.nome, m.estado, m.bloco, m.casa
    from condominio_membros m join condominios c on c.id = m.condominio_id and c.deletado_em is null
   where m.cliente_id = cliente_actual() and m.estado in ('pendente', 'activo')
   order by c.nome;
$$;
revoke execute on function meus_condominios() from public, anon;
grant  execute on function meus_condominios() to authenticated;

-- -----------------------------------------------------------------------------
-- O pedido: só membros activos, com o endereço dentro do condomínio; taxa da zona do condomínio
-- -----------------------------------------------------------------------------
create or replace function validar_pedido_condominio(p_cozinha uuid, p_cliente uuid, p_ponto uuid, p_grupo uuid)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  c  condominios := condominio_da_cozinha(p_cozinha);
  pe pontos_entrega;
begin
  if c.id is null or p_cliente is null then return null; end if; -- cozinha normal, ou pedido feito pela equipa
  if not funcionalidade_activa('condominios') then
    raise exception 'cozinha_indisponivel' using errcode = 'P0001';
  end if;
  if p_grupo is not null then
    raise exception 'condominio_sem_grupos' using errcode = 'P0001';
  end if;
  if not condominio_membro_activo(c.id, p_cliente) then
    raise exception 'so_membros_condominio' using errcode = 'P0001';
  end if;
  select * into pe from pontos_entrega where id = p_ponto;
  if pe.lat is null or pe.lng is null
     or distancia_m(pe.lat, pe.lng, c.centro_lat, c.centro_lng) > c.raio_m + 50 then
    raise exception 'fora_do_condominio' using errcode = 'P0001';
  end if;
  return c.zona_id;
end $$;
revoke execute on function validar_pedido_condominio(uuid, uuid, uuid, uuid) from public, anon, authenticated;

do $$
declare
  v_def  text := pg_get_functiondef('orcamento_pedido(jsonb,uuid,uuid,uuid)'::regprocedure);
  v_novo text;
begin
  if position('validar_pedido_condominio' in v_def) > 0 then return; end if; -- já aplicado
  v_novo := regexp_replace(v_def, '(v_sem\s+text;)', E'\\1\n  v_zona_cond uuid;');
  v_novo := regexp_replace(v_novo, '(\n\s*select\s+\*\s+into\s+v_desc\s+from\s+avaliar_desconto_indicacao)',
    E'\n  -- Cozinha de condomínio: só membros, com o endereço lá dentro; a taxa é a da zona do condomínio\n'
    || E'  v_zona_cond := validar_pedido_condominio(v_cozinha, v_cliente, v_ponto.id, p_grupo);\n'
    || E'  if v_zona_cond is not null and p_grupo is null then\n'
    || E'    select * into v_zona from zonas where id = v_zona_cond and deletado_em is null;\n'
    || E'    v_taxa := round(coalesce(v_zona.taxa, 0))::int;\n'
    || E'  end if;\\1');
  if position('v_zona_cond uuid;' in v_novo) = 0 or position('v_zona_cond := validar_pedido_condominio' in v_novo) = 0 then
    raise exception 'orcamento_pedido não tem o formato esperado';
  end if;
  execute v_novo;
end $$;

-- -----------------------------------------------------------------------------
-- A cozinha do condomínio não aparece nas listas gerais nem no "mais pedido na tua zona"
-- -----------------------------------------------------------------------------
do $$
declare
  f      text;
  v_def  text;
  v_novo text;
begin
  foreach f in array array['cozinhas_para_pedir()', 'cozinhas_perto(uuid)'] loop
    v_def := pg_get_functiondef(f::regprocedure);
    continue when position('condominio_da_cozinha' in v_def) > 0; -- já aplicado
    v_novo := regexp_replace(v_def, '(cozinha_aceita_pedidos\(c\.id\))', E'\\1 and condominio_da_cozinha(c.id) is null');
    if v_novo = v_def then raise exception '% não tem o formato esperado', f; end if;
    execute v_novo;
  end loop;
  v_def := pg_get_functiondef('mais_pedidos_na_zona(uuid)'::regprocedure);
  if position('condominio_da_cozinha' in v_def) = 0 then
    v_novo := regexp_replace(v_def, '(cozinha_aceita_pedidos\(cd\.cozinha_id\))', E'\\1 and condominio_da_cozinha(cd.cozinha_id) is null');
    if v_novo = v_def then raise exception 'mais_pedidos_na_zona não tem o formato esperado'; end if;
    execute v_novo;
  end if;
end $$;
