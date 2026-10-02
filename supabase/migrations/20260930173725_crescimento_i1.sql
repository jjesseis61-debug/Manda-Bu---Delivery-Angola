-- =============================================================================
-- Manda Bué — Delivery Angola
-- Programa de Crescimento · Fase I1 (Fundações)
-- Especificação: PROJECTO_CRESCIMENTO_MANDA_BUE.md, secções 5 a 8.
--
-- Ajustes ao SQL do projecto (acordados antes da implementação):
--   pedidos            -> tabela do esquema base; aqui só os campos novos (5.4)
--   locais (geo)       -> locais_entrega (locais já existe: pontos de venda)
--   zonas_entrega      -> zonas
--   pratos             -> pratos_base
--   caixas             -> caixa
--   movimentos_stock   -> estoque_diario, estoque_longo_prazo (+ distribuicoes)
--   turnos             -> + coluna periodo; reconhecimentos por (cozinha, semana, periodo)
--   credito_usado      -> credito_indicacao_usado
--   pagamentos.grupo_id-> lote_id
--   actualizado_em     -> atualizado_em (grafia do MODELO_DE_DADOS.md)
--   Todas as tabelas novas levam os campos de sincronização comuns.
--
-- No fim desta migração TODOS os interruptores ficam desligados.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Ligação ao utilizador autenticado
-- -----------------------------------------------------------------------------
alter table clientes     add column if not exists auth_user_id uuid unique references auth.users(id);
alter table funcionarios add column if not exists auth_user_id uuid unique references auth.users(id);

-- -----------------------------------------------------------------------------
-- 5.1 Configuração
-- -----------------------------------------------------------------------------
create table parametros (
  id                          int primary key default 1 check (id = 1),
  -- indicação
  ganho_por_pedido            int not null default 100,
  duracao_dias                int not null default 60,
  desconto_indicado           int not null default 500,
  limite_verificacao_semanal  int not null default 10000,
  levantamento_minimo         int not null default 2000,
  limite_parcelamento         int not null default 20000,
  limiar_embaixador           int not null default 30,
  -- anti-fraude
  raio_mesmo_local_m          int not null default 25,
  max_indicados_por_local     int not null default 3,
  max_descontos_por_local     int not null default 3,
  -- prova social
  tamanho_top                 int not null default 10,
  limiar_intervalos           int not null default 20,
  tamanho_intervalo           int not null default 10000,
  pessoas_como_tu_min         int not null default 3,
  pessoas_como_tu_max         int not null default 10,
  contador_minimo             int not null default 10,
  -- avaliações
  prazo_avaliacao_dias        int not null default 3,
  avaliacoes_minimo           int not null default 5,
  -- grupos e equipa
  regra_taxa_grupo            text not null default 'dividir'
                              check (regra_taxa_grupo in ('dividir','empresa')),
  tolerancia_entrega_min      int not null default 15,
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  atualizado_por              uuid
);
insert into parametros (id) values (1);

create table funcionalidades (
  chave           text primary key,
  activa          boolean not null default false,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid
);
insert into funcionalidades (chave) values
  ('indicacao'),('destaques'),('pessoas_como_tu'),('contadores_zona'),
  ('perfil_cozinha'),('avaliacoes'),('avaliacoes_fotos'),
  ('reconhecimento_equipa'),('pedidos_grupo'),('multi_cozinha');

-- -----------------------------------------------------------------------------
-- 5.2 Cozinhas
-- -----------------------------------------------------------------------------
create table cozinhas (
  id                     uuid primary key default gen_random_uuid(),
  dispositivo_id         text,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now(),
  sincronizado_em        timestamptz,
  deletado_em            timestamptz,
  nome                   text not null,
  responsavel            text not null,
  foto_url               text,
  historia               text,
  estado                 text not null default 'activa'
                         check (estado in ('activa','pausada','inactiva')),
  consentimento_publico  boolean not null default false
);

insert into cozinhas (nome, responsavel) values ('Cozinha da Alexandra', 'Alexandra');

-- Cozinha usada por defeito enquanto só há uma (multi_cozinha desligado).
create or replace function cozinha_padrao() returns uuid
language sql stable security definer set search_path = public as $$
  select id from cozinhas
   where estado = 'activa' and deletado_em is null
   order by criado_em, id
   limit 1;
$$;

-- Tabelas operacionais existentes passam a pertencer a uma cozinha.
-- Migração: preencher com a Cozinha da Alexandra e tornar not null.
do $$
declare
  t text;
  alexandra uuid := (select id from cozinhas where nome = 'Cozinha da Alexandra');
begin
  foreach t in array array['pratos_base','turnos','caixa','estoque_diario','estoque_longo_prazo',
                           'distribuicoes','vendas','pre_encomendas','pedidos_especiais'] loop
    execute format('alter table %I add column if not exists cozinha_id uuid references cozinhas(id)', t);
    execute format('update %I set cozinha_id = $1 where cozinha_id is null', t) using alexandra;
    execute format('alter table %I alter column cozinha_id set default cozinha_padrao()', t);
    execute format('alter table %I alter column cozinha_id set not null', t);
    execute format('create index if not exists %I on %I (cozinha_id)', t || '_cozinha_idx', t);
  end loop;
end $$;

-- Turno de cozinha (equipa), para reconhecimento sem expor pessoas
alter table turnos add column if not exists periodo text
  check (periodo in ('manha','tarde','noite'));

-- -----------------------------------------------------------------------------
-- 5.3 Locais de entrega e endereços
-- -----------------------------------------------------------------------------
create table locais_entrega (
  id                   uuid primary key default gen_random_uuid(),
  dispositivo_id       text,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),
  sincronizado_em      timestamptz,
  deletado_em          timestamptz,
  tipo                 text not null check (tipo in ('residencial','empresa')),
  lat                  double precision not null check (lat between -90 and 90),
  lng                  double precision not null check (lng between -180 and 180),
  zona_id              uuid references zonas(id),
  referencia           text,                          -- 'Prédio azul, 3.º andar, porta 12'
  criado_por_cliente   uuid references clientes(id)
);
create index on locais_entrega (zona_id);
create index on locais_entrega (lat, lng);

create table enderecos_cliente (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid not null references clientes(id),
  local_id         uuid not null references locais_entrega(id),
  nome             text not null default 'Casa',       -- 'Casa', 'Trabalho'
  principal        boolean not null default false
);
create index on enderecos_cliente (cliente_id);
create index on enderecos_cliente (local_id);

-- -----------------------------------------------------------------------------
-- 5.4 Campos novos em pedidos (tabela criada no esquema base)
-- -----------------------------------------------------------------------------
alter table pedidos
  add column cozinha_id               uuid references cozinhas(id),
  add column local_id                 uuid references locais_entrega(id),
  add column desconto_indicacao       int not null default 0,   -- só o servidor escreve
  add column credito_indicacao_usado  int not null default 0,   -- só o servidor escreve
  add column grupo_id                 uuid,                     -- FK adicionada em 5.8
  add column pagador_distinto         boolean;                  -- marcado pelo entregador
update pedidos set cozinha_id = cozinha_padrao() where cozinha_id is null;
alter table pedidos alter column cozinha_id set default cozinha_padrao();
alter table pedidos alter column cozinha_id set not null;
create index on pedidos (local_id);
create index on pedidos (grupo_id);
create index on pedidos (cozinha_id, criado_em);

-- -----------------------------------------------------------------------------
-- 5.5 Convida e Ganha
-- -----------------------------------------------------------------------------
create table codigos_indicacao (
  id                  uuid primary key default gen_random_uuid(),
  dispositivo_id      text,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  sincronizado_em     timestamptz,
  deletado_em         timestamptz,
  cliente_id          uuid not null unique references clientes(id),
  codigo              text not null unique,
  nivel               text not null default 'normal' check (nivel in ('normal','embaixador')),
  ultima_partilha_em  timestamptz
);

create table ligacoes_indicacao (
  id                  uuid primary key default gen_random_uuid(),
  dispositivo_id      text,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  sincronizado_em     timestamptz,
  deletado_em         timestamptz,
  indicado_id         uuid not null unique references clientes(id),
  indicador_id        uuid not null references clientes(id),
  ligado_em           timestamptz not null default now(),
  primeiro_pedido_id  uuid references pedidos(id),
  expira_em           timestamptz,     -- null até ao 1.º pedido entregue e pago
  desconto_usado      boolean not null default false,
  check (indicado_id <> indicador_id)
);
create index on ligacoes_indicacao (indicador_id);
create index on ligacoes_indicacao (expira_em);

create table ganhos_indicacao (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  pedido_id        uuid not null unique references pedidos(id),
  indicador_id     uuid not null references clientes(id),
  indicado_id      uuid not null references clientes(id),
  valor            int not null check (valor >= 0),
  estado           text not null
                   check (estado in ('em_verificacao','confirmado','pago','anulado')),
  motivo           text,   -- verificação: 'limite_semanal','limite_local','numero_pagamento_partilhado'
                           -- anulação: 'mesmo_dispositivo','pedido_estornado','rejeitado_verificacao'
  nota_revisao     text,   -- motivo escrito na anulação por verificação
  revisto_por      uuid,
  revisto_em       timestamptz,
  pagamento_id     uuid,
  confirmado_em    timestamptz
);
create index on ganhos_indicacao (indicador_id, estado);
create index on ganhos_indicacao (confirmado_em);
create index on ganhos_indicacao (indicado_id);

create table pagamentos_indicacao (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  indicador_id     uuid not null references clientes(id),
  valor            int not null check (valor > 0),
  tipo             text not null check (tipo in ('credito','levantamento')),
  metodo           text check (metodo in ('multicaixa_express','unitel_money')),
  numero_destino   text,           -- telefone da carteira; usado nos sinais anti-fraude
  pedido_id        uuid references pedidos(id),   -- quando tipo = 'credito'
  lote_id          uuid,           -- liga parcelas do mesmo levantamento
  parcela          int not null default 1,
  total_parcelas   int not null default 1,
  estado           text not null default 'pedido'
                   check (estado in ('pedido','aprovado','pago','rejeitado')),
  referencia       text,
  motivo_rejeicao  text,
  aprovado_por     uuid,
  pago_em          timestamptz
);
create index on pagamentos_indicacao (indicador_id, estado);
create index on pagamentos_indicacao (numero_destino);
create index on pagamentos_indicacao (lote_id);

alter table ganhos_indicacao add constraint ganhos_pagamento_fk
  foreign key (pagamento_id) references pagamentos_indicacao(id);

create table perfil_destaques (
  id                 uuid primary key default gen_random_uuid(),
  dispositivo_id     text,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  sincronizado_em    timestamptz,
  deletado_em        timestamptz,
  cliente_id         uuid not null unique references clientes(id),
  pseudonimo         text not null unique,
  mostrar_nome_real  boolean not null default false,
  sair_da_lista      boolean not null default false
);

-- Preferências de notificação (C14): N5 e N7 podem ser desligadas pelo cliente
create table preferencias_notificacao (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid not null unique references clientes(id),
  lembrete_almoco  boolean not null default true,   -- N5
  destaques        boolean not null default true    -- N7
);

-- -----------------------------------------------------------------------------
-- 5.6 Avaliações
-- -----------------------------------------------------------------------------
create table avaliacoes (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  pedido_id        uuid not null unique references pedidos(id),
  cliente_id       uuid not null references clientes(id),
  cozinha_id       uuid not null references cozinhas(id),
  estrelas         int not null check (estrelas between 1 and 5),
  comentario       text check (char_length(comentario) <= 200),
  oculta           boolean not null default false,
  ocultada_por     uuid,
  usar_pseudonimo  boolean not null default false
);
create index on avaliacoes (cozinha_id);

create table avaliacoes_pratos (   -- estrelas por prato dentro do pedido (opcional)
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  avaliacao_id     uuid not null references avaliacoes(id) on delete cascade,
  prato_id         uuid not null references pratos_base(id),
  estrelas         int not null check (estrelas between 1 and 5),
  unique (avaliacao_id, prato_id)
);

create table fotos_avaliacao (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  avaliacao_id     uuid not null references avaliacoes(id) on delete cascade,
  caminho          text not null,        -- Supabase Storage, bucket privado até aprovação
  estado           text not null default 'pendente'
                   check (estado in ('pendente','aprovada','rejeitada')),
  moderado_por     uuid,
  moderado_em      timestamptz
);

-- Filtro de palavras dos comentários (preenchido pelo operador; começa vazio)
create table palavras_filtradas (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  palavra          text not null unique
);

-- -----------------------------------------------------------------------------
-- 5.7 Reconhecimento de equipa (por turno de cozinha, nunca por pessoa)
-- -----------------------------------------------------------------------------
create table reconhecimentos_turno (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cozinha_id       uuid not null references cozinhas(id),
  semana           date not null check (extract(isodow from semana) = 1),  -- segunda-feira
  periodo          text not null check (periodo in ('manha','tarde','noite')),
  tipo             text not null check (tipo in ('menos_desperdicio','entregas_a_horas','caixa_certa','outro')),
  nota             text,
  criado_por       uuid not null
);
create index on reconhecimentos_turno (cozinha_id, semana);

-- -----------------------------------------------------------------------------
-- 5.8 Pedidos de grupo
-- -----------------------------------------------------------------------------
create table pedidos_grupo (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  organizador_id   uuid not null references clientes(id),
  empresa_id       uuid references clientes(id),       -- cliente Empresa, quando paga
  local_id         uuid not null references locais_entrega(id),
  cozinha_id       uuid not null default cozinha_padrao() references cozinhas(id),
  hora_entrega     timestamptz not null,
  prazo_adesao     timestamptz not null,
  modo_pagamento   text not null check (modo_pagamento in ('individual','empresa')),
  codigo_convite   text not null unique,              -- para o link de adesão
  estado           text not null default 'aberto'
                   check (estado in ('aberto','fechado','em_preparacao','entregue','cancelado')),
  check (prazo_adesao <= hora_entrega)
);
alter table pedidos add constraint pedidos_grupo_fk
  foreign key (grupo_id) references pedidos_grupo(id);

-- -----------------------------------------------------------------------------
-- 5.9 Fila de notificações e contadores por zona
-- -----------------------------------------------------------------------------
create table notificacoes_fila (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid not null references clientes(id),
  codigo           text not null check (codigo ~ '^N[0-9]+$'),   -- ver secção 11
  dados            jsonb not null default '{}',
  enviada_em       timestamptz
);
create index on notificacoes_fila (enviada_em) where enviada_em is null;
create index on notificacoes_fila (cliente_id, codigo, criado_em);

-- Cache dos contadores por zona, recalculado de hora a hora
create table contadores_zona (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  zona_id          uuid not null references zonas(id),
  data             date not null,
  total            int not null default 0,
  unique (zona_id, data)
);

-- =============================================================================
-- 6. Funções e triggers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 6.1 Utilitários
-- -----------------------------------------------------------------------------
create or replace function distancia_m(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8 language sql immutable as $$
  select 6371000 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

create or replace function mesmo_local(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select a = b or exists (
    select 1 from locais_entrega la, locais_entrega lb, parametros p
    where la.id = a and lb.id = b and p.id = 1
      and la.tipo = lb.tipo
      and distancia_m(la.lat, la.lng, lb.lat, lb.lng) <= p.raio_mesmo_local_m
  );
$$;

create or replace function funcionalidade_activa(k text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select activa from funcionalidades where chave = k), false);
$$;

create or replace function inicio_semana_luanda()
returns timestamptz language sql stable as $$
  select date_trunc('week', now() at time zone 'Africa/Luanda') at time zone 'Africa/Luanda';
$$;

create or replace function inicio_dia_luanda()
returns timestamptz language sql stable as $$
  select date_trunc('day', now() at time zone 'Africa/Luanda') at time zone 'Africa/Luanda';
$$;

create or replace function inicio_mes_luanda()
returns timestamptz language sql stable as $$
  select date_trunc('month', now() at time zone 'Africa/Luanda') at time zone 'Africa/Luanda';
$$;

create or replace function hoje_luanda()
returns date language sql stable as $$
  select (now() at time zone 'Africa/Luanda')::date;
$$;

-- Normaliza números de telefone/carteira para comparação (9 dígitos angolanos)
create or replace function normalizar_telefone(p text)
returns text language sql immutable as $$
  select nullif(right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 9), '');
$$;

-- Escrita feita directamente por um cliente/operador (PostgREST), e não por
-- uma função do servidor. SECURITY INVOKER de propósito: dentro de funções
-- security definer, current_user é o dono e isto devolve false.
create or replace function e_escrita_cliente()
returns boolean language sql stable as $$
  select current_user in ('authenticated', 'anon');
$$;

-- Utilizador autenticado -> cliente / funcionário
create or replace function cliente_actual() returns uuid
language sql stable security definer set search_path = public as $$
  select id from clientes
   where auth_user_id = auth.uid() and auth.uid() is not null and deletado_em is null
   limit 1;
$$;

create or replace function funcionario_actual() returns uuid
language sql stable security definer set search_path = public as $$
  select id from funcionarios
   where auth_user_id = auth.uid() and auth.uid() is not null and deletado_em is null
   limit 1;
$$;

create or replace function e_funcionario() returns boolean
language sql stable security definer set search_path = public as $$
  select funcionario_actual() is not null;
$$;

-- Permissões do organograma: administrador principal tem tudo;
-- permissoes_extra do funcionário tem prioridade sobre as da direcção.
create or replace function tem_permissao(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case
             when f.administrador_principal then true
             when f.permissoes_extra ? p then coalesce((f.permissoes_extra ->> p)::boolean, false)
             else coalesce((d.permissoes ->> p)::boolean, false)
           end
      from funcionarios f
      left join direcoes d on d.id = f.direcao_id and d.deletado_em is null
     where f.auth_user_id = auth.uid() and auth.uid() is not null and f.deletado_em is null
     limit 1
  ), false);
$$;

create or replace function exigir_permissao(p text) returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if not tem_permissao(p) then
    raise exception 'sem_permissao' using errcode = '42501', detail = p;
  end if;
  return funcionario_actual();
end $$;

-- -----------------------------------------------------------------------------
-- Auditoria (tabela existente; append-only e imutável)
-- -----------------------------------------------------------------------------
create or replace function registar_auditoria(
  p_acao text, p_ref_tipo text, p_ref_id uuid,
  p_detalhe jsonb default '{}', p_bloqueado boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := funcionario_actual();
  v_nome text;
begin
  if v_func is not null then
    select nome into v_nome from funcionarios where id = v_func;
  elsif cliente_actual() is not null then
    v_nome := 'cliente';
  else
    v_nome := 'sistema';
  end if;
  insert into auditoria (dispositivo_id, funcionario_id, funcionario_nome, acao, detalhe,
                         ref_id, ref_tipo, bloqueado, sincronizado_em)
  values ('servidor', v_func, v_nome, p_acao, p_detalhe::text,
          p_ref_id, p_ref_tipo, p_bloqueado, now());
end $$;

create or replace function auditoria_imutavel() returns trigger
language plpgsql as $$
begin
  -- Única excepção: o servidor marcar a receção (sincronizado_em de null para um valor)
  if tg_op = 'UPDATE' and old.sincronizado_em is null
     and (to_jsonb(new) - 'sincronizado_em') = (to_jsonb(old) - 'sincronizado_em') then
    return new;
  end if;
  raise exception 'auditoria_imutavel' using errcode = '42501';
end $$;

drop trigger if exists trg_auditoria_imutavel on auditoria;
create trigger trg_auditoria_imutavel
before update or delete on auditoria
for each row execute function auditoria_imutavel();

drop trigger if exists trg_auditoria_sem_truncate on auditoria;
create trigger trg_auditoria_sem_truncate
before truncate on auditoria
for each statement execute function auditoria_imutavel();

-- -----------------------------------------------------------------------------
-- Sincronização: o servidor marca a receção; last-write-wins onde aplicável
-- -----------------------------------------------------------------------------
create or replace function sync_receber() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.criado_em := old.criado_em;
    new.dispositivo_id := old.dispositivo_id;
    -- Last-write-wins: escrita de dispositivo mais antiga que a guardada é ignorada
    if tg_nargs > 0 and tg_argv[0] = 'lww' and e_escrita_cliente()
       and new.atualizado_em < old.atualizado_em then
      return null;
    end if;
  end if;
  if not e_escrita_cliente() and tg_op = 'UPDATE' then
    new.atualizado_em := now();
  end if;
  new.sincronizado_em := now();
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- Parâmetros e interruptores: auditoria de alterações
-- -----------------------------------------------------------------------------
create or replace function configuracao_alterada() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_diff jsonb;
begin
  new.atualizado_em := now();
  new.atualizado_por := funcionario_actual();
  select coalesce(jsonb_object_agg(n.key, jsonb_build_object('de', o.value, 'para', n.value)), '{}')
    into v_diff
    from jsonb_each(to_jsonb(new) - 'atualizado_em' - 'atualizado_por') n
    join jsonb_each(to_jsonb(old)) o using (key)
   where n.value is distinct from o.value;
  if v_diff <> '{}' then
    perform registar_auditoria(tg_table_name || '_alterados', tg_table_name, null, v_diff);
  end if;
  return new;
end $$;

create trigger trg_parametros_auditoria before update on parametros
for each row execute function configuracao_alterada();
create trigger trg_funcionalidades_auditoria before update on funcionalidades
for each row execute function configuracao_alterada();

-- -----------------------------------------------------------------------------
-- 6.2 Registo de cliente: código MB- e pseudónimo
-- -----------------------------------------------------------------------------
create or replace function gerar_codigo_indicacao() returns text
language plpgsql security definer set search_path = public as $$
declare
  v text;
  digitos int := 4;
  tentativas int := 0;
begin
  -- Passa a 5 (6, ...) dígitos quando o espaço actual estiver esgotado
  while (select count(*) from codigos_indicacao
          where codigo ~ ('^MB-[0-9]{' || digitos || '}$')) >= power(10, digitos) loop
    digitos := digitos + 1;
  end loop;
  loop
    v := 'MB-' || lpad(floor(random() * power(10, digitos))::bigint::text, digitos, '0');
    exit when not exists (select 1 from codigos_indicacao where codigo = v);
    tentativas := tentativas + 1;
    if tentativas >= 200 then digitos := digitos + 1; tentativas := 0; end if;
  end loop;
  return v;
end $$;

-- Pseudónimo sem ligação a dados pessoais: palavra angolana + cor/qualidade ou número
create or replace function gerar_pseudonimo() returns text
language plpgsql security definer set search_path = public as $$
declare
  palavras text[] := array[
    'Palanca','Imbondeiro','Mulemba','Welwitschia','Kianda','Tundavala','Kalandula',
    'Mussulo','Muxima','Kwanza','Quiçama','Cunene','Cubango','Namibe','Bengo',
    'Pensador','Múcua','Marimba','Semba','Rebita','Kizomba','Cajueiro','Mangueira',
    'Pelicano','Flamingo','Golfinho','Leopardo','Tartaruga','Gunga','Ngola'];
  qualidades text[] := array[
    'Azul','Verde','Real','Feliz','Veloz','Gentil','Solar','Lunar','Forte','Livre',
    'Doce','Alegre','Nobre','Sereno','Brilhante'];
  v text;
  tentativas int := 0;
begin
  loop
    v := palavras[1 + floor(random() * array_length(palavras, 1))::int] || ' ' ||
         case when random() < 0.5
              then qualidades[1 + floor(random() * array_length(qualidades, 1))::int]
              else (10 + floor(random() * 90)::int)::text end;
    if tentativas > 50 then
      v := v || ' ' || (100 + floor(random() * 900)::int)::text;
    end if;
    exit when not exists (select 1 from perfil_destaques where pseudonimo = v);
    tentativas := tentativas + 1;
  end loop;
  return v;
end $$;

create or replace function preparar_cliente_programa(p_cliente uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from codigos_indicacao where cliente_id = p_cliente) then
    insert into codigos_indicacao (cliente_id, codigo, dispositivo_id)
    values (p_cliente, gerar_codigo_indicacao(), 'servidor');
  end if;
  if not exists (select 1 from perfil_destaques where cliente_id = p_cliente) then
    insert into perfil_destaques (cliente_id, pseudonimo, dispositivo_id)
    values (p_cliente, gerar_pseudonimo(), 'servidor');
  end if;
  if not exists (select 1 from preferencias_notificacao where cliente_id = p_cliente) then
    insert into preferencias_notificacao (cliente_id, dispositivo_id)
    values (p_cliente, 'servidor');
  end if;
end $$;

create or replace function cliente_registado() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform preparar_cliente_programa(new.id);
  return new;
end $$;

create trigger trg_cliente_registado
after insert on clientes
for each row execute function cliente_registado();

-- Clientes já existentes recebem código e pseudónimo
select preparar_cliente_programa(id) from clientes;

-- Cliente com compra paga (pedido novo ou venda do sistema anterior)
create or replace function cliente_ja_comprou(p_cliente uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from pedidos
                  where cliente_id = p_cliente and estado = 'entregue_pago' and deletado_em is null)
      or exists (select 1 from vendas
                  where cliente_id = p_cliente and deletado_em is null);
$$;

-- -----------------------------------------------------------------------------
-- 6.3 Ligação a um indicador
-- -----------------------------------------------------------------------------
create or replace function ligar_indicacao(p_codigo text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cliente   uuid := cliente_actual();
  v_indicador uuid;
  v_ligacao   uuid;
begin
  if not funcionalidade_activa('indicacao') then return 'programa_inactivo'; end if;
  if v_cliente is null then return 'sem_sessao'; end if;

  select cliente_id into v_indicador
    from codigos_indicacao
   where codigo = upper(trim(p_codigo)) and deletado_em is null;
  if v_indicador is null then return 'codigo_inexistente'; end if;
  if v_indicador = v_cliente then return 'proprio_codigo'; end if;
  if exists (select 1 from ligacoes_indicacao where indicado_id = v_cliente) then
    return 'ja_ligado';
  end if;
  if cliente_ja_comprou(v_cliente) then return 'cliente_nao_novo'; end if;

  insert into ligacoes_indicacao (indicado_id, indicador_id, dispositivo_id)
  values (v_cliente, v_indicador, 'servidor')
  returning id into v_ligacao;

  insert into notificacoes_fila (cliente_id, codigo, dados)
  select v_indicador, 'N2', jsonb_build_object('indicado_nome', split_part(trim(nome), ' ', 1))
    from clientes where id = v_cliente;

  perform registar_auditoria('indicacao_ligada', 'ligacoes_indicacao', v_ligacao,
                             jsonb_build_object('indicador_id', v_indicador, 'indicado_id', v_cliente));
  return 'ok';
end $$;

-- Marca que o cliente partilhou o código (condição para N5)
create or replace function registar_partilha() returns void
language sql security definer set search_path = public as $$
  update codigos_indicacao set ultima_partilha_em = now() where cliente_id = cliente_actual();
$$;

-- -----------------------------------------------------------------------------
-- 6.4 Desconto do indicado
-- -----------------------------------------------------------------------------
-- Avalia o desconto de primeiro pedido. Devolve o valor e o motivo
-- ('ok','programa_inactivo','sem_ligacao','desconto_usado','cliente_nao_novo',
--  'desconto_em_curso','limite_local').
create or replace function avaliar_desconto_indicacao(p_cliente uuid, p_local uuid)
returns table (valor int, motivo text)
language plpgsql stable security definer set search_path = public as $$
declare
  p      parametros;
  lig    ligacoes_indicacao;
  v_tipo text;
  usados int;
begin
  if not funcionalidade_activa('indicacao') then
    return query select 0, 'programa_inactivo'; return;
  end if;
  select * into p from parametros where id = 1;
  select * into lig from ligacoes_indicacao where indicado_id = p_cliente and deletado_em is null;
  if not found then return query select 0, 'sem_ligacao'; return; end if;
  if lig.desconto_usado then return query select 0, 'desconto_usado'; return; end if;
  if cliente_ja_comprou(p_cliente) then return query select 0, 'cliente_nao_novo'; return; end if;

  -- Já há um pedido em curso com o desconto (evita o desconto em dois pedidos)
  if exists (select 1 from pedidos
              where cliente_id = p_cliente and desconto_indicacao > 0 and deletado_em is null
                and estado not in ('cancelado','estornado')) then
    return query select 0, 'desconto_em_curso'; return;
  end if;

  select tipo into v_tipo from locais_entrega where id = p_local;
  if v_tipo = 'residencial' then
    select count(*) into usados
      from pedidos x
     where x.desconto_indicacao > 0 and x.estado = 'entregue_pago' and x.deletado_em is null
       and x.local_id is not null
       and mesmo_local(x.local_id, p_local);
    if usados >= p.max_descontos_por_local then
      return query select 0, 'limite_local'; return;
    end if;
  end if;

  return query select p.desconto_indicado, 'ok';
end $$;

-- Para o ecrã C2: confirmação do servidor antes de mostrar "−500 Kz"
create or replace function meu_desconto_indicacao(p_local uuid)
returns table (valor int, motivo text)
language sql stable security definer set search_path = public as $$
  select * from avaliar_desconto_indicacao(cliente_actual(), p_local);
$$;

-- Grupo aberto para adesão (usado ao criar um pedido dentro de um grupo)
create or replace function grupo_para_adesao(p_grupo uuid)
returns pedidos_grupo
language plpgsql stable security definer set search_path = public as $$
declare
  g pedidos_grupo;
begin
  if not funcionalidade_activa('pedidos_grupo') then
    raise exception 'funcionalidade_inactiva' using errcode = 'P0001';
  end if;
  select * into g from pedidos_grupo where id = p_grupo and deletado_em is null;
  if not found or g.estado <> 'aberto' or now() > g.prazo_adesao then
    raise exception 'grupo_fechado' using errcode = 'P0001';
  end if;
  return g;
end $$;

-- before insert on pedidos, passo 1 (SECURITY INVOKER: precisa de saber quem escreve)
create or replace function pedidos_proteger_insercao() returns trigger
language plpgsql as $$
begin
  if e_escrita_cliente() then
    -- O cliente só cria pedidos no estado inicial; campos do servidor começam vazios
    new.estado := 'pendente';
    new.entregue_em := null;
    new.credito_indicacao_usado := 0;
    new.pagador_distinto := null;
    if not funcionalidade_activa('multi_cozinha') then
      new.cozinha_id := cozinha_padrao();
    end if;
  end if;
  return new;
end $$;

create trigger trg_pedidos_1_proteger
before insert on pedidos
for each row execute function pedidos_proteger_insercao();

-- before insert on pedidos, passo 2: grupo, cozinha e desconto (6.4)
create or replace function calcular_desconto_indicacao() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g pedidos_grupo;
begin
  if new.grupo_id is not null then
    g := grupo_para_adesao(new.grupo_id);
    new.local_id := g.local_id;
    new.cozinha_id := g.cozinha_id;
  end if;

  if new.cozinha_id is null then
    new.cozinha_id := cozinha_padrao();
  end if;

  -- O servidor ignora qualquer valor enviado pela app e recalcula
  select d.valor into new.desconto_indicacao
    from avaliar_desconto_indicacao(new.cliente_id, new.local_id) d;
  return new;
end $$;

create trigger trg_pedidos_2_desconto_indicacao
before insert on pedidos
for each row execute function calcular_desconto_indicacao();

-- N10: alguém entra num grupo
create or replace function pedidos_depois_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
begin
  if new.grupo_id is not null then
    select organizador_id into v_org from pedidos_grupo where id = new.grupo_id;
    if v_org is not null and v_org <> new.cliente_id then
      insert into notificacoes_fila (cliente_id, codigo, dados)
      select v_org, 'N10', jsonb_build_object(
               'grupo_id', new.grupo_id,
               'participante_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = new.cliente_id),
               'participantes', (select count(distinct cliente_id) from pedidos
                                  where grupo_id = new.grupo_id and deletado_em is null
                                    and estado <> 'cancelado'));
    end if;
  end if;
  return new;
end $$;

create trigger trg_pedidos_depois_inserir
after insert on pedidos
for each row execute function pedidos_depois_inserir();

-- Ciclo de estados do pedido
create or replace function transicao_estado_valida(de text, para text) returns boolean
language sql immutable as $$
  select de = para
      or (de in ('pendente','confirmado','em_preparacao','em_entrega')
          and (para = 'cancelado'
               or array_position(array['pendente','confirmado','em_preparacao','em_entrega','entregue_pago'], para)
                > array_position(array['pendente','confirmado','em_preparacao','em_entrega','entregue_pago'], de)))
      or (de = 'entregue_pago' and para = 'estornado');
$$;

-- before update on pedidos (SECURITY INVOKER)
create or replace function pedidos_antes_actualizar() returns trigger
language plpgsql as $$
begin
  if e_escrita_cliente() then
    -- Campos que só o servidor escreve
    new.desconto_indicacao := old.desconto_indicacao;
    new.credito_indicacao_usado := old.credito_indicacao_usado;
    new.entregue_em := old.entregue_em;
    new.cliente_id := old.cliente_id;
    new.cozinha_id := old.cozinha_id;
    new.grupo_id := old.grupo_id;
    if new.pagador_distinto is distinct from old.pagador_distinto
       and not tem_permissao('entregas.registar') then
      raise exception 'sem_permissao' using errcode = '42501', detail = 'entregas.registar';
    end if;
  end if;

  if new.estado is distinct from old.estado then
    if not transicao_estado_valida(old.estado, new.estado) then
      raise exception 'transicao_invalida' using errcode = 'P0001',
        detail = old.estado || ' -> ' || new.estado;
    end if;
    if new.estado = 'entregue_pago' then
      new.entregue_em := coalesce(new.entregue_em, now());
    end if;
  end if;
  return new;
end $$;

create trigger trg_pedidos_antes_actualizar
before update on pedidos
for each row execute function pedidos_antes_actualizar();

-- -----------------------------------------------------------------------------
-- 6.5 Ganho do indicador
-- -----------------------------------------------------------------------------
create or replace function processar_ganho_indicacao()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  p               parametros;
  lig             ligacoes_indicacao;
  v_tipo_local    text;
  nivel_ind       text;
  total_sem       int;
  indicados_local int;
  v_estado        text := 'confirmado';
  v_motivo        text := null;
  v_ganho         uuid;
  g               record;
begin
  -- Estorno de um pedido já pago: ganhos ainda não pagos são anulados
  if old.estado = 'entregue_pago' and new.estado <> 'entregue_pago' then
    for g in update ganhos_indicacao
                set estado = 'anulado', motivo = 'pedido_estornado'
              where pedido_id = new.id and estado in ('em_verificacao','confirmado')
             returning id loop
      perform registar_auditoria('ganho_indicacao_anulado', 'ganhos_indicacao', g.id,
                                 jsonb_build_object('motivo', 'pedido_estornado', 'pedido_id', new.id));
    end loop;
    return new;
  end if;

  if new.estado <> 'entregue_pago' or old.estado = 'entregue_pago' then
    return new;
  end if;
  if not funcionalidade_activa('indicacao') then return new; end if;

  select * into p from parametros where id = 1;
  select * into lig from ligacoes_indicacao
   where indicado_id = new.cliente_id and deletado_em is null
   for update;
  if not found then return new; end if;

  -- 1.º pedido pago: arranca o período
  if lig.expira_em is null then
    update ligacoes_indicacao
       set primeiro_pedido_id = new.id,
           expira_em = coalesce(new.entregue_em, now()) + make_interval(days => p.duracao_dias),
           desconto_usado = (new.desconto_indicacao > 0)
     where id = lig.id
    returning * into lig;
  end if;

  if now() > lig.expira_em then return new; end if;
  if exists (select 1 from ganhos_indicacao where pedido_id = new.id) then
    return new;
  end if;

  -- Sinal forte: mesmo dispositivo
  if exists (
    select 1 from pedidos a
     where a.cliente_id = lig.indicador_id and a.dispositivo_id is not null
       and a.dispositivo_id in (select b.dispositivo_id from pedidos b
                                 where b.cliente_id = new.cliente_id
                                   and b.dispositivo_id is not null)) then
    v_estado := 'anulado'; v_motivo := 'mesmo_dispositivo';
  end if;

  -- Sinal médio: mesmo número de levantamento
  if v_estado = 'confirmado' and exists (
    select 1 from pagamentos_indicacao a
     where a.indicador_id = lig.indicador_id and a.numero_destino is not null
       and a.numero_destino in (select b.numero_destino from pagamentos_indicacao b
                                 where b.indicador_id = new.cliente_id
                                   and b.numero_destino is not null)) then
    v_estado := 'em_verificacao'; v_motivo := 'numero_pagamento_partilhado';
  end if;

  -- Limite por local residencial
  select tipo into v_tipo_local from locais_entrega where id = new.local_id;
  if v_estado = 'confirmado' and v_tipo_local = 'residencial' then
    select count(distinct g2.indicado_id) into indicados_local
      from ganhos_indicacao g2 join pedidos x on x.id = g2.pedido_id
     where g2.estado <> 'anulado'
       and g2.indicado_id <> new.cliente_id
       and x.local_id is not null
       and mesmo_local(x.local_id, new.local_id);
    if indicados_local >= p.max_indicados_por_local then
      v_estado := 'em_verificacao'; v_motivo := 'limite_local';
    end if;
  end if;

  -- Limite semanal (não se aplica a Embaixadores)
  if v_estado = 'confirmado' then
    select nivel into nivel_ind from codigos_indicacao where cliente_id = lig.indicador_id;
    if nivel_ind is distinct from 'embaixador' then
      select coalesce(sum(valor), 0) into total_sem
        from ganhos_indicacao
       where indicador_id = lig.indicador_id
         and estado in ('confirmado','pago')
         and confirmado_em >= inicio_semana_luanda();
      if total_sem >= p.limite_verificacao_semanal then
        v_estado := 'em_verificacao'; v_motivo := 'limite_semanal';
      end if;
    end if;
  end if;

  insert into ganhos_indicacao
    (pedido_id, indicador_id, indicado_id, valor, estado, motivo, confirmado_em, dispositivo_id)
  values
    (new.id, lig.indicador_id, new.cliente_id, p.ganho_por_pedido, v_estado, v_motivo,
     case when v_estado = 'confirmado' then now() end, 'servidor')
  returning id into v_ganho;

  perform registar_auditoria('ganho_indicacao_criado', 'ganhos_indicacao', v_ganho,
    jsonb_build_object('estado', v_estado, 'motivo', v_motivo, 'pedido_id', new.id));

  if v_estado = 'confirmado' then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N3', jsonb_build_object(
      'pedido_id', new.id,
      'valor', p.ganho_por_pedido,
      'indicado_nome', (select split_part(trim(nome), ' ', 1) from clientes where id = new.cliente_id),
      'saldo_semana', (select coalesce(sum(valor), 0) from ganhos_indicacao
                        where indicador_id = lig.indicador_id and estado in ('confirmado','pago')
                          and confirmado_em >= inicio_semana_luanda())));
  elsif v_estado = 'em_verificacao' and v_motivo = 'limite_semanal'
        and not exists (select 1 from ganhos_indicacao
                         where indicador_id = lig.indicador_id
                           and motivo = 'limite_semanal'
                           and criado_em >= inicio_semana_luanda()
                           and pedido_id <> new.id) then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N4', jsonb_build_object('limite', p.limite_verificacao_semanal));
  end if;

  return new;
end $$;

create trigger trg_ganho_indicacao
after update of estado on pedidos
for each row execute function processar_ganho_indicacao();

-- -----------------------------------------------------------------------------
-- 6.6 Revisão de ganhos
-- -----------------------------------------------------------------------------
create or replace function rever_ganho(p_ganho uuid, p_decisao text, p_motivo text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('indicacoes.verificar');
  g      ganhos_indicacao;
begin
  select * into g from ganhos_indicacao where id = p_ganho for update;
  if not found then raise exception 'ganho_inexistente' using errcode = 'P0001'; end if;
  if g.estado <> 'em_verificacao' then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;

  if p_decisao = 'confirmar' then
    update ganhos_indicacao
       set estado = 'confirmado', confirmado_em = now(), revisto_por = v_func, revisto_em = now()
     where id = p_ganho;
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (g.indicador_id, 'N3', jsonb_build_object('pedido_id', g.pedido_id, 'valor', g.valor));
    perform registar_auditoria('ganho_indicacao_confirmado', 'ganhos_indicacao', p_ganho,
                               jsonb_build_object('motivo_verificacao', g.motivo));
  elsif p_decisao = 'anular' then
    if coalesce(trim(p_motivo), '') = '' then
      raise exception 'motivo_obrigatorio' using errcode = 'P0001';
    end if;
    update ganhos_indicacao
       set estado = 'anulado', motivo = 'rejeitado_verificacao', nota_revisao = trim(p_motivo),
           revisto_por = v_func, revisto_em = now()
     where id = p_ganho;
    perform registar_auditoria('ganho_indicacao_anulado', 'ganhos_indicacao', p_ganho,
      jsonb_build_object('motivo', 'rejeitado_verificacao', 'nota', trim(p_motivo),
                         'motivo_verificacao', g.motivo));
  else
    raise exception 'decisao_invalida' using errcode = 'P0001';
  end if;
  return 'ok';
end $$;

-- Nível Embaixador (atribuído manualmente)
create or replace function definir_nivel_indicador(p_cliente uuid, p_nivel text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('plataforma.parametros');
  if p_nivel not in ('normal','embaixador') then
    raise exception 'nivel_invalido' using errcode = 'P0001';
  end if;
  update codigos_indicacao set nivel = p_nivel where cliente_id = p_cliente;
  if not found then raise exception 'cliente_sem_codigo' using errcode = 'P0001'; end if;
  perform registar_auditoria('nivel_indicador_alterado', 'codigos_indicacao', p_cliente,
                             jsonb_build_object('nivel', p_nivel));
end $$;

-- -----------------------------------------------------------------------------
-- 6.7 Pagamentos
-- -----------------------------------------------------------------------------
-- Saldo exacto: ganhos confirmado+pago − pagamentos pedido/aprovado/pago.
-- (Equivale a "confirmado − pagamentos em curso" da especificação, mas não
--  depende de os valores dos pagamentos coincidirem com ganhos inteiros.)
create or replace function saldo_disponivel_de(p_indicador uuid) returns int
language sql stable security definer set search_path = public as $$
  select ((select coalesce(sum(valor), 0) from ganhos_indicacao
            where indicador_id = p_indicador and estado in ('confirmado','pago')
              and deletado_em is null)
        - (select coalesce(sum(valor), 0) from pagamentos_indicacao
            where indicador_id = p_indicador and estado in ('pedido','aprovado','pago')
              and deletado_em is null))::int;
$$;

-- Passa a "pago" os ganhos confirmados mais antigos cobertos pelo total pago
create or replace function aplicar_pagamentos_a_ganhos(p_indicador uuid, p_pagamento uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  total_pago int;
  ja_pago    int;
  g          record;
begin
  select coalesce(sum(valor), 0) into total_pago from pagamentos_indicacao
   where indicador_id = p_indicador and estado = 'pago' and deletado_em is null;
  select coalesce(sum(valor), 0) into ja_pago from ganhos_indicacao
   where indicador_id = p_indicador and estado = 'pago';
  for g in select id, valor from ganhos_indicacao
            where indicador_id = p_indicador and estado = 'confirmado'
            order by confirmado_em, criado_em, id
            for update loop
    exit when ja_pago + g.valor > total_pago;
    update ganhos_indicacao set estado = 'pago', pagamento_id = p_pagamento where id = g.id;
    ja_pago := ja_pago + g.valor;
  end loop;
end $$;

create or replace function pedir_levantamento(p_valor int, p_metodo text, p_numero text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  p         parametros;
  v_numero  text := normalizar_telefone(p_numero);
  v_lote    uuid := gen_random_uuid();
  v_p1      int;
begin
  if not funcionalidade_activa('indicacao') then
    raise exception 'programa_inactivo' using errcode = 'P0001';
  end if;
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  if p_metodo is null or p_metodo not in ('multicaixa_express','unitel_money') then
    raise exception 'metodo_invalido' using errcode = 'P0001';
  end if;
  if v_numero is null or length(v_numero) <> 9 then
    raise exception 'numero_invalido' using errcode = 'P0001';
  end if;

  select * into p from parametros where id = 1;
  -- Um pedido de cada vez por cliente (evita gastar o mesmo saldo duas vezes)
  perform pg_advisory_xact_lock(hashtext('saldo_indicacao:' || v_cliente::text));

  if p_valor is null or p_valor < p.levantamento_minimo then
    raise exception 'abaixo_minimo' using errcode = 'P0001';
  end if;
  if p_valor > saldo_disponivel_de(v_cliente) then
    raise exception 'saldo_insuficiente' using errcode = 'P0001';
  end if;

  if p_valor > p.limite_parcelamento then
    v_p1 := ceil(p_valor / 2.0);
    insert into pagamentos_indicacao
      (indicador_id, valor, tipo, metodo, numero_destino, lote_id, parcela, total_parcelas, dispositivo_id)
    values
      (v_cliente, v_p1,           'levantamento', p_metodo, v_numero, v_lote, 1, 2, 'servidor'),
      (v_cliente, p_valor - v_p1, 'levantamento', p_metodo, v_numero, v_lote, 2, 2, 'servidor');
  else
    insert into pagamentos_indicacao
      (indicador_id, valor, tipo, metodo, numero_destino, lote_id, dispositivo_id)
    values (v_cliente, p_valor, 'levantamento', p_metodo, v_numero, v_lote, 'servidor');
  end if;

  perform registar_auditoria('levantamento_pedido', 'pagamentos_indicacao', v_lote,
    jsonb_build_object('valor', p_valor, 'metodo', p_metodo));
  return v_lote;
end $$;

create or replace function usar_credito(p_pedido uuid, p_valor int)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_cliente uuid := cliente_actual();
  ped       pedidos;
  v_pag     uuid;
begin
  if not funcionalidade_activa('indicacao') then
    raise exception 'programa_inactivo' using errcode = 'P0001';
  end if;
  if v_cliente is null then raise exception 'sem_sessao' using errcode = '42501'; end if;

  select * into ped from pedidos where id = p_pedido and deletado_em is null for update;
  if not found or ped.cliente_id <> v_cliente then
    raise exception 'pedido_inexistente' using errcode = 'P0001';
  end if;
  if ped.estado not in ('pendente','confirmado') then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('saldo_indicacao:' || v_cliente::text));

  if p_valor is null or p_valor <= 0 then
    raise exception 'valor_invalido' using errcode = 'P0001';
  end if;
  if p_valor > saldo_disponivel_de(v_cliente) then
    raise exception 'saldo_insuficiente' using errcode = 'P0001';
  end if;
  if ped.credito_indicacao_usado + p_valor
     > ped.subtotal + ped.taxa_entrega - ped.desconto_indicacao then
    raise exception 'acima_do_valor_do_pedido' using errcode = 'P0001';
  end if;

  insert into pagamentos_indicacao (indicador_id, valor, tipo, pedido_id, estado, pago_em, dispositivo_id)
  values (v_cliente, p_valor, 'credito', p_pedido, 'pago', now(), 'servidor')
  returning id into v_pag;

  update pedidos set credito_indicacao_usado = credito_indicacao_usado + p_valor
   where id = p_pedido;

  perform aplicar_pagamentos_a_ganhos(v_cliente, v_pag);
  perform registar_auditoria('credito_indicacao_usado', 'pagamentos_indicacao', v_pag,
    jsonb_build_object('valor', p_valor, 'pedido_id', p_pedido));
  return ped.credito_indicacao_usado + p_valor;
end $$;

-- Pedido cancelado/estornado: o crédito usado volta ao saldo
create or replace function reverter_credito_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  pg record;
begin
  if new.estado in ('cancelado','estornado') and old.estado is distinct from new.estado then
    for pg in update pagamentos_indicacao
                 set estado = 'rejeitado', motivo_rejeicao = 'pedido_' || new.estado
               where pedido_id = new.id and tipo = 'credito' and estado = 'pago'
              returning id, indicador_id loop
      update ganhos_indicacao set estado = 'confirmado', pagamento_id = null
       where pagamento_id = pg.id and estado = 'pago';
      perform aplicar_pagamentos_a_ganhos(pg.indicador_id, null);
      perform registar_auditoria('credito_indicacao_revertido', 'pagamentos_indicacao', pg.id,
                                 jsonb_build_object('pedido_id', new.id, 'estado', new.estado));
    end loop;
  end if;
  return new;
end $$;

create trigger trg_reverter_credito_pedido
after update of estado on pedidos
for each row execute function reverter_credito_pedido();

create or replace function aprovar_levantamento(p_pagamento uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('indicacoes.aprovar_pagamentos');
begin
  update pagamentos_indicacao set estado = 'aprovado', aprovado_por = v_func
   where id = p_pagamento and tipo = 'levantamento' and estado = 'pedido';
  if not found then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
  perform registar_auditoria('levantamento_aprovado', 'pagamentos_indicacao', p_pagamento);
end $$;

create or replace function rejeitar_levantamento(p_pagamento uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform exigir_permissao('indicacoes.aprovar_pagamentos');
  if coalesce(trim(p_motivo), '') = '' then
    raise exception 'motivo_obrigatorio' using errcode = 'P0001';
  end if;
  update pagamentos_indicacao set estado = 'rejeitado', motivo_rejeicao = trim(p_motivo)
   where id = p_pagamento and tipo = 'levantamento' and estado in ('pedido','aprovado');
  if not found then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
  perform registar_auditoria('levantamento_rejeitado', 'pagamentos_indicacao', p_pagamento,
                             jsonb_build_object('motivo', trim(p_motivo)));
end $$;

create or replace function marcar_pago(p_pagamento uuid, p_referencia text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('indicacoes.aprovar_pagamentos');
  pg     pagamentos_indicacao;
begin
  if coalesce(trim(p_referencia), '') = '' then
    raise exception 'referencia_obrigatoria' using errcode = 'P0001';
  end if;
  select * into pg from pagamentos_indicacao where id = p_pagamento for update;
  if not found or pg.tipo <> 'levantamento' or pg.estado not in ('pedido','aprovado') then
    raise exception 'estado_invalido' using errcode = 'P0001';
  end if;

  update pagamentos_indicacao
     set estado = 'pago', referencia = trim(p_referencia), pago_em = now(),
         aprovado_por = coalesce(aprovado_por, v_func)
   where id = p_pagamento;

  perform aplicar_pagamentos_a_ganhos(pg.indicador_id, p_pagamento);

  insert into notificacoes_fila (cliente_id, codigo, dados)
  values (pg.indicador_id, 'N8', jsonb_build_object(
    'valor', pg.valor, 'metodo', pg.metodo, 'referencia', trim(p_referencia)));

  perform registar_auditoria('levantamento_pago', 'pagamentos_indicacao', p_pagamento,
    jsonb_build_object('valor', pg.valor, 'referencia', trim(p_referencia)));
end $$;

-- Cancelamento pelo próprio cliente (só enquanto pendente)
create or replace function cancelar_pedido(p_pedido uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  update pedidos set estado = 'cancelado', motivo_cancelamento = p_motivo
   where id = p_pedido and cliente_id = cliente_actual() and estado = 'pendente';
  if not found then raise exception 'estado_invalido' using errcode = 'P0001'; end if;
end $$;

-- -----------------------------------------------------------------------------
-- Locais, endereços, avaliações, grupos (regras de apoio)
-- -----------------------------------------------------------------------------
-- Sugestão de local existente dentro do raio (C11). Não expõe dados de clientes;
-- a referência escrita só é devolvida para locais do tipo empresa.
create or replace function locais_proximos(p_lat float8, p_lng float8, p_tipo text)
returns table (local_id uuid, tipo text, referencia text, distancia_m float8)
language sql stable security definer set search_path = public as $$
  select l.id, l.tipo,
         case when l.tipo = 'empresa' then l.referencia end,
         round(distancia_m(l.lat, l.lng, p_lat, p_lng)::numeric, 1)::float8
    from locais_entrega l, parametros p
   where p.id = 1 and l.deletado_em is null and l.tipo = p_tipo
     and cliente_actual() is not null
     and abs(l.lat - p_lat) < 0.01 and abs(l.lng - p_lng) < 0.01
     and distancia_m(l.lat, l.lng, p_lat, p_lng) <= p.raio_mesmo_local_m
   order by 4
   limit 5;
$$;

-- Clientes Empresa só usam locais do tipo empresa
create or replace function validar_endereco_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select tipo from clientes where id = new.cliente_id) = 'Empresa'
     and (select tipo from locais_entrega where id = new.local_id) <> 'empresa' then
    raise exception 'empresa_requer_local_empresa' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger trg_validar_endereco_cliente
before insert or update of local_id, cliente_id on enderecos_cliente
for each row execute function validar_endereco_cliente();

create or replace function locais_antes_inserir() returns trigger
language plpgsql as $$
begin
  if e_escrita_cliente() then
    new.criado_por_cliente := cliente_actual();
  end if;
  return new;
end $$;

create trigger trg_locais_antes_inserir
before insert on locais_entrega
for each row execute function locais_antes_inserir();

-- Avaliação permitida: pedido próprio, entregue e pago, dentro do prazo
create or replace function avaliacao_permitida(p_pedido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select funcionalidade_activa('avaliacoes') and exists (
    select 1 from pedidos x, parametros p
     where p.id = 1 and x.id = p_pedido and x.cliente_id = cliente_actual()
       and x.estado = 'entregue_pago' and x.deletado_em is null
       and x.entregue_em >= now() - make_interval(days => p.prazo_avaliacao_dias));
$$;

create or replace function avaliacoes_antes_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select cozinha_id into new.cozinha_id from pedidos where id = new.pedido_id;
  -- Filtro de palavras: comentário com palavra filtrada fica oculto
  if new.comentario is not null and exists (
       select 1 from palavras_filtradas w
        where w.deletado_em is null
          and lower(new.comentario) ~ ('(^|\W)' || regexp_replace(lower(w.palavra), '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '($|\W)')) then
    new.oculta := true;
  end if;
  return new;
end $$;

create trigger trg_avaliacoes_antes_inserir
before insert on avaliacoes
for each row execute function avaliacoes_antes_inserir();

create or replace function ocultar_avaliacao(p_avaliacao uuid, p_oculta boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('avaliacoes.moderar');
begin
  update avaliacoes set oculta = p_oculta, ocultada_por = case when p_oculta then v_func end
   where id = p_avaliacao;
  if not found then raise exception 'avaliacao_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('avaliacao_moderada', 'avaliacoes', p_avaliacao,
                             jsonb_build_object('oculta', p_oculta));
end $$;

-- Até 2 fotos por avaliação
create or replace function fotos_antes_inserir() returns trigger
language plpgsql as $$
begin
  if (select count(*) from fotos_avaliacao
       where avaliacao_id = new.avaliacao_id and deletado_em is null) >= 2 then
    raise exception 'limite_fotos' using errcode = 'P0001';
  end if;
  if e_escrita_cliente() then
    new.estado := 'pendente'; new.moderado_por := null; new.moderado_em := null;
  end if;
  return new;
end $$;

create trigger trg_fotos_antes_inserir
before insert on fotos_avaliacao
for each row execute function fotos_antes_inserir();

create or replace function moderar_foto(p_foto uuid, p_decisao text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_func uuid := exigir_permissao('avaliacoes.moderar');
begin
  if p_decisao not in ('aprovada','rejeitada') then
    raise exception 'decisao_invalida' using errcode = 'P0001';
  end if;
  update fotos_avaliacao set estado = p_decisao, moderado_por = v_func, moderado_em = now()
   where id = p_foto;
  if not found then raise exception 'foto_inexistente' using errcode = 'P0001'; end if;
  perform registar_auditoria('foto_moderada', 'fotos_avaliacao', p_foto,
                             jsonb_build_object('decisao', p_decisao));
end $$;

-- Código de convite do grupo
create or replace function gerar_codigo_grupo() returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v text;
begin
  loop
    v := 'G-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from pedidos_grupo where codigo_convite = v);
  end loop;
  return v;
end $$;

create or replace function pedidos_grupo_antes_inserir() returns trigger
language plpgsql as $$
begin
  if e_escrita_cliente() then
    new.organizador_id := cliente_actual();
    new.estado := 'aberto';
  end if;
  new.codigo_convite := gerar_codigo_grupo();
  return new;
end $$;

create trigger trg_pedidos_grupo_antes_inserir
before insert on pedidos_grupo
for each row execute function pedidos_grupo_antes_inserir();

-- Leitura de um grupo pelo código do link (sem expor dados pessoais)
create or replace function grupo_por_codigo(p_codigo text)
returns table (grupo_id uuid, hora_entrega timestamptz, prazo_adesao timestamptz,
               modo_pagamento text, estado text, participantes int)
language sql stable security definer set search_path = public as $$
  select g.id, g.hora_entrega, g.prazo_adesao, g.modo_pagamento, g.estado,
         (select count(distinct x.cliente_id)::int from pedidos x
           where x.grupo_id = g.id and x.deletado_em is null and x.estado <> 'cancelado')
    from pedidos_grupo g
   where g.codigo_convite = upper(trim(p_codigo)) and g.deletado_em is null
     and cliente_actual() is not null and funcionalidade_activa('pedidos_grupo');
$$;

-- Reconhecimentos: autor definido pelo servidor
create or replace function reconhecimentos_antes_inserir() returns trigger
language plpgsql as $$
begin
  if e_escrita_cliente() then
    new.criado_por := funcionario_actual();
  end if;
  return new;
end $$;

create trigger trg_reconhecimentos_antes_inserir
before insert on reconhecimentos_turno
for each row execute function reconhecimentos_antes_inserir();

create or replace function reconhecimentos_depois_inserir() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform registar_auditoria('reconhecimento_turno', 'reconhecimentos_turno', new.id,
    jsonb_build_object('cozinha_id', new.cozinha_id, 'semana', new.semana,
                       'periodo', new.periodo, 'tipo', new.tipo));
  return new;
end $$;

create trigger trg_reconhecimentos_depois_inserir
after insert on reconhecimentos_turno
for each row execute function reconhecimentos_depois_inserir();

-- -----------------------------------------------------------------------------
-- Notificações: interruptor de cada código
-- -----------------------------------------------------------------------------
create or replace function funcionalidade_da_notificacao(p_codigo text) returns text
language sql immutable as $$
  select case
    when p_codigo in ('N1','N2','N3','N4','N5','N6','N8') then 'indicacao'
    when p_codigo = 'N7'  then 'destaques'
    when p_codigo = 'N9'  then 'avaliacoes'
    when p_codigo in ('N10','N11') then 'pedidos_grupo'
    when p_codigo = 'N12' then 'reconhecimento_equipa'
  end;
$$;

-- =============================================================================
-- 7. Vistas e funções de leitura
-- =============================================================================

-- Saldo por indicador (respeita RLS de quem consulta)
create view saldo_indicacao with (security_invoker = true) as
select c.cliente_id as indicador_id,
       ((select coalesce(sum(g.valor), 0) from ganhos_indicacao g
          where g.indicador_id = c.cliente_id and g.estado in ('confirmado','pago') and g.deletado_em is null)
      - (select coalesce(sum(pg.valor), 0) from pagamentos_indicacao pg
          where pg.indicador_id = c.cliente_id and pg.estado in ('pedido','aprovado','pago') and pg.deletado_em is null)
       )::int as saldo_disponivel,
       (select coalesce(sum(g.valor), 0) from ganhos_indicacao g
         where g.indicador_id = c.cliente_id and g.estado = 'em_verificacao' and g.deletado_em is null)::int
       as em_verificacao,
       (select coalesce(sum(g.valor), 0) from ganhos_indicacao g
         where g.indicador_id = c.cliente_id and g.estado in ('confirmado','pago')
           and g.confirmado_em >= inicio_dia_luanda())::int
       as ganho_hoje,
       (select coalesce(sum(g.valor), 0) from ganhos_indicacao g
         where g.indicador_id = c.cliente_id and g.estado in ('confirmado','pago')
           and g.confirmado_em >= inicio_semana_luanda())::int
       as ganho_semana,
       (select coalesce(sum(pg.valor), 0) from pagamentos_indicacao pg
         where pg.indicador_id = c.cliente_id and pg.estado = 'pago')::int
       as total_recebido
  from codigos_indicacao c
 where c.deletado_em is null;

-- Ranking interno do mês (tem ids: nunca exposto directamente ao cliente)
create or replace function ranking_mes()
returns table (cliente_id uuid, nome_exibido text, amigos int, valor int, posicao int)
language sql stable security definer set search_path = public as $$
  with base as (
    select g.indicador_id, count(distinct g.indicado_id)::int as amigos, sum(g.valor)::int as valor
      from ganhos_indicacao g
     where g.estado in ('confirmado','pago') and g.deletado_em is null
       and g.confirmado_em >= inicio_mes_luanda()
     group by g.indicador_id)
  select b.indicador_id,
         case when pd.mostrar_nome_real then split_part(trim(c.nome), ' ', 1) else pd.pseudonimo end,
         b.amigos, b.valor,
         (row_number() over (order by b.amigos desc, b.valor desc, pd.pseudonimo))::int
    from base b
    join perfil_destaques pd on pd.cliente_id = b.indicador_id
    join clientes c on c.id = b.indicador_id
   where not pd.sair_da_lista and pd.deletado_em is null;
$$;

-- Lista pública: nunca devolve ids nem telefones
create or replace function destaques_mes()
returns table (posicao int, nome_exibido text, amigos int, valor int,
               valor_min int, valor_max int, sou_eu boolean)
language sql stable security definer set search_path = public as $$
  with r as materialized (select * from ranking_mes()),
       n as (select count(*) as total from r)
  select r.posicao, r.nome_exibido, r.amigos,
         case when n.total >= p.limiar_intervalos then r.valor end,
         case when n.total <  p.limiar_intervalos then (r.valor / p.tamanho_intervalo) * p.tamanho_intervalo end,
         case when n.total <  p.limiar_intervalos then (r.valor / p.tamanho_intervalo + 1) * p.tamanho_intervalo end,
         r.cliente_id = cliente_actual()
    from r, n, parametros p
   where p.id = 1 and funcionalidade_activa('destaques')
     and r.posicao <= p.tamanho_top
   order by r.posicao;
$$;

create or replace function minha_posicao()
returns table (posicao int, nome_exibido text, amigos int, valor int,
               amigos_em_falta int, no_top boolean)
language sql stable security definer set search_path = public as $$
  with r as materialized (select * from ranking_mes()),
       eu as (select * from r where r.cliente_id = cliente_actual()),
       p as (select * from parametros where id = 1),
       ultimo as (select r.amigos from r, p where r.posicao = p.tamanho_top)
  select eu.posicao,
         coalesce(eu.nome_exibido, (select pseudonimo from perfil_destaques where cliente_id = cliente_actual())),
         coalesce(eu.amigos, 0), coalesce(eu.valor, 0),
         case when eu.posicao <= p.tamanho_top then 0
              else greatest(1, coalesce((select amigos from ultimo), 0) - coalesce(eu.amigos, 0) + 1) end,
         coalesce(eu.posicao <= p.tamanho_top, false)
    from p left join eu on true
   where cliente_actual() is not null and funcionalidade_activa('destaques');
$$;

create or replace function pessoas_como_tu()
returns table (nome_exibido text, amigos int, valor int)
language sql volatile security definer set search_path = public as $$
  with p as (select * from parametros where id = 1),
       cand as materialized (
         select r.nome_exibido, r.amigos, r.valor
           from ranking_mes() r, p
          where r.cliente_id is distinct from cliente_actual()
            and r.amigos between p.pessoas_como_tu_min and p.pessoas_como_tu_max
          order by random()
          limit 3)
  select * from cand
   where (select count(*) from cand) >= 2 and funcionalidade_activa('pessoas_como_tu');
$$;

create or replace function total_pago_mes() returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(valor), 0)::int from pagamentos_indicacao
   where estado = 'pago' and pago_em >= inicio_mes_luanda() and deletado_em is null;
$$;

-- Contador por zona (lido da cache; null abaixo do mínimo)
create or replace function contador_zona(p_zona uuid) returns int
language sql stable security definer set search_path = public as $$
  select case when funcionalidade_activa('contadores_zona') and cz.total >= p.contador_minimo
              then cz.total end
    from parametros p
    left join contadores_zona cz on cz.zona_id = p_zona and cz.data = hoje_luanda()
   where p.id = 1;
$$;

-- Médias de avaliação (só com o mínimo de avaliações, excluindo ocultas)
create view media_avaliacoes_cozinha with (security_invoker = true) as
select a.cozinha_id, round(avg(a.estrelas)::numeric, 1) as media, count(*)::int as total
  from avaliacoes a
 where not a.oculta and a.deletado_em is null
 group by a.cozinha_id
having count(*) >= (select avaliacoes_minimo from parametros where id = 1);

create view media_avaliacoes_prato with (security_invoker = true) as
select ap.prato_id, round(avg(ap.estrelas)::numeric, 1) as media, count(*)::int as total
  from avaliacoes_pratos ap
  join avaliacoes a on a.id = ap.avaliacao_id
 where not a.oculta and a.deletado_em is null and ap.deletado_em is null
 group by ap.prato_id
having count(*) >= (select avaliacoes_minimo from parametros where id = 1);

-- Métricas por turno de cozinha e semana.
-- Janela do turno: das horas de início às de fim dos turnos daquele período no dia.
--   desperdicio: distribuições com quebra registadas na janela (n.º e quantidade)
--   entregas a horas: entregue_em <= hora_prometida + tolerancia_entrega_min
--   diferenca_caixa: soma de |fechamento.diferenca| das caixas de funcionários do turno
create or replace function metricas_turno(p_cozinha uuid, p_semana date)
returns table (periodo text, quebras int, quantidade_quebra numeric,
               entregas int, entregas_a_horas int, pct_a_horas numeric,
               diferenca_caixa numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (tem_permissao('equipa.reconhecer')
          or exists (select 1 from turnos t
                      where t.cozinha_id = p_cozinha and t.funcionario_id = funcionario_actual())) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
  with janelas as (
    select t.data, t.periodo,
           (t.data + min(t.hora_inicio)) at time zone 'Africa/Luanda' as ini,
           (t.data + max(t.hora_fim))    at time zone 'Africa/Luanda' as fim,
           array_agg(t.funcionario_id) as membros
      from turnos t
     where t.cozinha_id = p_cozinha and t.deletado_em is null and t.periodo is not null
       and t.data between p_semana and p_semana + 6
     group by t.data, t.periodo),
  q as (
    select j.periodo, count(d.id)::int as n, coalesce(sum(d.quantidade_quebra), 0) as qtd
      from janelas j
      left join distribuicoes d on d.cozinha_id = p_cozinha and d.deletado_em is null
       and d.quantidade_quebra > 0 and d.criado_em between j.ini and j.fim
     group by j.periodo),
  e as (
    select j.periodo, count(x.id)::int as n,
           count(x.id) filter (where x.entregue_em <= x.hora_prometida
                                 + make_interval(mins => (select tolerancia_entrega_min from parametros where id = 1)))::int as a_horas
      from janelas j
      left join pedidos x on x.cozinha_id = p_cozinha and x.deletado_em is null
       and x.estado = 'entregue_pago' and x.hora_prometida is not null
       and x.entregue_em between j.ini and j.fim
     group by j.periodo),
  c as (
    select j.periodo, coalesce(sum(abs((cx.fechamento ->> 'diferenca')::numeric)), 0) as dif
      from janelas j
      left join caixa cx on cx.cozinha_id = p_cozinha and cx.deletado_em is null
       and cx.data = j.data and cx.funcionario_id = any (j.membros)
       and cx.fechamento ? 'diferenca'
     group by j.periodo)
  select q.periodo, q.n, q.qtd, e.n, e.a_horas,
         case when e.n > 0 then round(100.0 * e.a_horas / e.n, 1) end,
         c.dif
    from q join e using (periodo) join c using (periodo)
   order by array_position(array['manha','tarde','noite'], q.periodo);
end $$;

-- Relatório de cozinha (para O9 e para recrutamento de cozinhas parceiras)
create or replace function relatorio_cozinha(p_cozinha uuid, p_inicio date, p_fim date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz := p_inicio::timestamp at time zone 'Africa/Luanda';
  v_fim timestamptz := (p_fim + 1)::timestamp at time zone 'Africa/Luanda';
  r     jsonb;
begin
  perform exigir_permissao('relatorios.exportar');
  with pagos as (
    select * from pedidos
     where cozinha_id = p_cozinha and estado = 'entregue_pago' and deletado_em is null),
  primeiro as (
    select cliente_id, min(entregue_em) as primeiro_em from pagos group by cliente_id),
  novos as (
    select * from primeiro where primeiro_em >= v_ini and primeiro_em < v_fim),
  retencao as (
    select d.dias,
           count(*) filter (where n.primeiro_em + make_interval(days => d.dias) <= now()) as elegiveis,
           count(*) filter (where n.primeiro_em + make_interval(days => d.dias) <= now()
                              and exists (select 1 from pagos x
                                           where x.cliente_id = n.cliente_id
                                             and x.entregue_em >= n.primeiro_em + make_interval(days => d.dias))) as retidos
      from novos n cross join (values (30), (60), (90)) d(dias)
     group by d.dias)
  select jsonb_build_object(
    'pedidos_por_dia', coalesce((
       select jsonb_agg(jsonb_build_object('dia', dia, 'pedidos', n) order by dia)
         from (select (entregue_em at time zone 'Africa/Luanda')::date as dia, count(*) as n
                 from pagos where entregue_em >= v_ini and entregue_em < v_fim
                group by 1) s), '[]'),
    'clientes_novos', (select count(*) from novos),
    'clientes_indicacao', (select count(*) from novos n
                            where exists (select 1 from ligacoes_indicacao l where l.indicado_id = n.cliente_id)),
    'retencao', coalesce((
       select jsonb_object_agg(dias::text, case when elegiveis > 0
                                                 then round(100.0 * retidos / elegiveis, 1) end)
         from retencao), '{}'),
    'media_avaliacao', (select round(avg(estrelas)::numeric, 1) from avaliacoes
                         where cozinha_id = p_cozinha and not oculta and deletado_em is null
                           and criado_em >= v_ini and criado_em < v_fim),
    'prato_mais_pedido', (
       select jsonb_build_object('prato_base_id', i ->> 'prato_base_id',
                                 'nome', max(i ->> 'nome'),
                                 'quantidade', sum(coalesce((i ->> 'qtd')::numeric, 1)))
         from pagos x, jsonb_array_elements(x.itens) i
        where x.entregue_em >= v_ini and x.entregue_em < v_fim
        group by i ->> 'prato_base_id'
        order by sum(coalesce((i ->> 'qtd')::numeric, 1)) desc
        limit 1))
  into r;
  return r;
end $$;

-- =============================================================================
-- 6.8 Jobs agendados
-- =============================================================================
create or replace function job_contadores_zona() returns void
language sql security definer set search_path = public as $$
  insert into contadores_zona (zona_id, data, total, dispositivo_id)
  select l.zona_id, hoje_luanda(), count(*)::int, 'servidor'
    from pedidos x join locais_entrega l on l.id = x.local_id
   where x.estado = 'entregue_pago' and x.deletado_em is null
     and x.entregue_em >= inicio_dia_luanda() and l.zona_id is not null
   group by l.zona_id
  on conflict (zona_id, data) do update set total = excluded.total;
$$;

-- N6: 5 dias antes de um indicado expirar
create or replace function job_n6_expiracao() returns void
language sql security definer set search_path = public as $$
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select l.indicador_id, 'N6',
         jsonb_build_object('ligacao_id', l.id,
                            'indicado_nome', split_part(trim(c.nome), ' ', 1),
                            'expira_em', l.expira_em)
    from ligacoes_indicacao l join clientes c on c.id = l.indicado_id
   where funcionalidade_activa('indicacao') and l.deletado_em is null
     and (l.expira_em at time zone 'Africa/Luanda')::date = hoje_luanda() + 5
     and not exists (select 1 from notificacoes_fila n
                      where n.codigo = 'N6' and n.dados ->> 'ligacao_id' = l.id::text);
$$;

-- N5: lembrete do almoço, dias úteis, máx. 2 por semana, só quem já partilhou
create or replace function job_n5_lembrete() returns void
language sql security definer set search_path = public as $$
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select ci.cliente_id, 'N5', '{}'::jsonb
    from codigos_indicacao ci
    join preferencias_notificacao pn on pn.cliente_id = ci.cliente_id
   where funcionalidade_activa('indicacao')
     and extract(isodow from hoje_luanda()) between 1 and 5
     and ci.ultima_partilha_em is not null and ci.deletado_em is null
     and pn.lembrete_almoco
     and (select count(*) from notificacoes_fila n
           where n.cliente_id = ci.cliente_id and n.codigo = 'N5'
             and n.criado_em >= inicio_semana_luanda()) < 2;
$$;

-- N7: semanal, para quem está a até 3 amigos do top
create or replace function job_n7_destaques() returns void
language sql security definer set search_path = public as $$
  with r as materialized (select * from ranking_mes()),
       p as (select * from parametros where id = 1),
       ultimo as (select coalesce((select r.amigos from r, p where r.posicao = p.tamanho_top), 0) as amigos)
  insert into notificacoes_fila (cliente_id, codigo, dados)
  select r.cliente_id, 'N7',
         jsonb_build_object('nome_exibido', r.nome_exibido, 'posicao', r.posicao,
                            'amigos_em_falta', greatest(1, u.amigos - r.amigos + 1),
                            'tamanho_top', p.tamanho_top)
    from r, p, ultimo u, preferencias_notificacao pn
   where funcionalidade_activa('destaques')
     and pn.cliente_id = r.cliente_id and pn.destaques
     and r.posicao > p.tamanho_top
     and u.amigos - r.amigos + 1 <= 3;
$$;

-- Agenda os jobs com pg_cron, se a extensão estiver instalada (horas em UTC;
-- Luanda = UTC+1). Pode ser chamada de novo depois de activar o pg_cron.
create or replace function agendar_jobs() returns text
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron_ausente';
  end if;
  execute $c$select cron.schedule('mb_contadores_zona', '0 * * * *',    'select public.job_contadores_zona()')$c$;
  execute $c$select cron.schedule('mb_n6_expiracao',    '0 7 * * *',    'select public.job_n6_expiracao()')$c$;
  execute $c$select cron.schedule('mb_n5_lembrete',     '0 10 * * 1-5', 'select public.job_n5_lembrete()')$c$;
  execute $c$select cron.schedule('mb_n7_destaques',    '0 7 * * 1',    'select public.job_n7_destaques()')$c$;
  return 'agendado';
end $$;

select agendar_jobs();

-- =============================================================================
-- Sincronização: triggers nas tabelas novas
-- =============================================================================
do $$
declare
  t text;
begin
  -- Last-write-wins (dados escritos pelo cliente)
  foreach t in array array['locais_entrega','enderecos_cliente','perfil_destaques',
                           'preferencias_notificacao','cozinhas','palavras_filtradas'] loop
    execute format('create trigger trg_sync_receber before insert or update on %I
                    for each row execute function sync_receber(''lww'')', t);
  end loop;
  -- Estado validado pelo servidor / append-only
  foreach t in array array['pedidos','codigos_indicacao','ligacoes_indicacao','ganhos_indicacao',
                           'pagamentos_indicacao','avaliacoes','avaliacoes_pratos','fotos_avaliacao',
                           'reconhecimentos_turno','pedidos_grupo','notificacoes_fila','contadores_zona'] loop
    execute format('create trigger trg_sync_receber before insert or update on %I
                    for each row execute function sync_receber()', t);
  end loop;
end $$;

-- =============================================================================
-- 8. Segurança (RLS) e permissões
-- =============================================================================
do $$
declare
  t text;
begin
  foreach t in array array['parametros','funcionalidades','cozinhas','locais_entrega','enderecos_cliente',
                           'pedidos','codigos_indicacao','ligacoes_indicacao','ganhos_indicacao',
                           'pagamentos_indicacao','perfil_destaques','preferencias_notificacao',
                           'avaliacoes','avaliacoes_pratos','fotos_avaliacao','palavras_filtradas',
                           'reconhecimentos_turno','pedidos_grupo','notificacoes_fila','contadores_zona'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;

-- parametros, funcionalidades
create policy ler on parametros for select to authenticated using (true);
create policy escrever on parametros for update to authenticated
  using (tem_permissao('plataforma.parametros')) with check (tem_permissao('plataforma.parametros'));
create policy ler on funcionalidades for select to authenticated using (true);
create policy escrever on funcionalidades for update to authenticated
  using (tem_permissao('plataforma.parametros')) with check (tem_permissao('plataforma.parametros'));
revoke insert, delete, truncate on parametros, funcionalidades from authenticated;

-- cozinhas
create policy ler_publicas on cozinhas for select to authenticated
  using ((estado = 'activa' and consentimento_publico and deletado_em is null) or e_funcionario());
create policy criar on cozinhas for insert to authenticated with check (tem_permissao('cozinhas.gerir'));
create policy editar on cozinhas for update to authenticated
  using (tem_permissao('cozinhas.gerir')) with check (tem_permissao('cozinhas.gerir'));

-- locais_entrega
create policy ler on locais_entrega for select to authenticated
  using (criado_por_cliente = cliente_actual()
         or exists (select 1 from enderecos_cliente e
                     where e.local_id = locais_entrega.id and e.cliente_id = cliente_actual())
         or e_funcionario());
create policy criar on locais_entrega for insert to authenticated
  with check (cliente_actual() is not null);
create policy editar on locais_entrega for update to authenticated
  using (criado_por_cliente = cliente_actual()) with check (criado_por_cliente = cliente_actual());

-- enderecos_cliente
create policy ler on enderecos_cliente for select to authenticated
  using (cliente_id = cliente_actual() or e_funcionario());
create policy criar on enderecos_cliente for insert to authenticated
  with check (cliente_id = cliente_actual());
create policy editar on enderecos_cliente for update to authenticated
  using (cliente_id = cliente_actual()) with check (cliente_id = cliente_actual());

-- pedidos
create policy ler on pedidos for select to authenticated
  using (cliente_id = cliente_actual() or e_funcionario());
create policy criar on pedidos for insert to authenticated
  with check (cliente_id = cliente_actual() or tem_permissao('pedidos.gerir'));
create policy gerir on pedidos for update to authenticated
  using (tem_permissao('pedidos.gerir') or tem_permissao('entregas.registar'))
  with check (tem_permissao('pedidos.gerir') or tem_permissao('entregas.registar'));
-- Campos só do servidor: sem privilégio de escrita directa
revoke insert, update, delete, truncate on pedidos from authenticated;
grant insert (id, dispositivo_id, criado_em, atualizado_em, cliente_id, cozinha_id, local_id,
              estado, itens, subtotal, taxa_entrega, desconto_indicacao, parcelas, observacoes,
              grupo_id, hora_prometida)
  on pedidos to authenticated;
grant update (atualizado_em, estado, hora_prometida, pagador_distinto, observacoes,
              motivo_cancelamento, deletado_em)
  on pedidos to authenticated;

-- codigos_indicacao
create policy ler on codigos_indicacao for select to authenticated
  using (cliente_id = cliente_actual() or tem_permissao('indicacoes.ver'));
revoke insert, update, delete, truncate on codigos_indicacao from authenticated;

-- ligacoes_indicacao (criar só via ligar_indicacao)
create policy ler on ligacoes_indicacao for select to authenticated
  using (indicador_id = cliente_actual() or indicado_id = cliente_actual() or tem_permissao('indicacoes.ver'));
revoke insert, update, delete, truncate on ligacoes_indicacao from authenticated;

-- ganhos_indicacao (rever só via rever_ganho)
create policy ler on ganhos_indicacao for select to authenticated
  using (indicador_id = cliente_actual() or tem_permissao('indicacoes.ver')
         or tem_permissao('indicacoes.verificar'));
revoke insert, update, delete, truncate on ganhos_indicacao from authenticated;

-- pagamentos_indicacao (criar/aprovar só via funções)
create policy ler on pagamentos_indicacao for select to authenticated
  using (indicador_id = cliente_actual() or tem_permissao('indicacoes.ver')
         or tem_permissao('indicacoes.aprovar_pagamentos'));
revoke insert, update, delete, truncate on pagamentos_indicacao from authenticated;

-- perfil_destaques (só mostrar_nome_real e sair_da_lista)
create policy ler on perfil_destaques for select to authenticated
  using (cliente_id = cliente_actual() or e_funcionario());
create policy editar on perfil_destaques for update to authenticated
  using (cliente_id = cliente_actual()) with check (cliente_id = cliente_actual());
revoke insert, update, delete, truncate on perfil_destaques from authenticated;
grant update (mostrar_nome_real, sair_da_lista, atualizado_em) on perfil_destaques to authenticated;

-- preferencias_notificacao
create policy ler on preferencias_notificacao for select to authenticated
  using (cliente_id = cliente_actual());
create policy editar on preferencias_notificacao for update to authenticated
  using (cliente_id = cliente_actual()) with check (cliente_id = cliente_actual());
revoke insert, update, delete, truncate on preferencias_notificacao from authenticated;
grant update (lembrete_almoco, destaques, atualizado_em) on preferencias_notificacao to authenticated;

-- avaliacoes
create policy ler on avaliacoes for select to authenticated
  using ((not oculta and deletado_em is null) or cliente_id = cliente_actual() or e_funcionario());
create policy criar on avaliacoes for insert to authenticated
  with check (cliente_id = cliente_actual() and avaliacao_permitida(pedido_id));
revoke update, delete, truncate on avaliacoes from authenticated;
revoke insert on avaliacoes from authenticated;
grant insert (id, dispositivo_id, criado_em, atualizado_em, pedido_id, cliente_id,
              estrelas, comentario, usar_pseudonimo)
  on avaliacoes to authenticated;

-- avaliacoes_pratos
create policy ler on avaliacoes_pratos for select to authenticated
  using (exists (select 1 from avaliacoes a where a.id = avaliacao_id));
create policy criar on avaliacoes_pratos for insert to authenticated
  with check (exists (select 1 from avaliacoes a
                       where a.id = avaliacao_id and a.cliente_id = cliente_actual()));
revoke update, delete, truncate on avaliacoes_pratos from authenticated;

-- fotos_avaliacao (moderar só via moderar_foto)
create policy ler on fotos_avaliacao for select to authenticated
  using (estado = 'aprovada'
         or exists (select 1 from avaliacoes a
                     where a.id = avaliacao_id and a.cliente_id = cliente_actual())
         or tem_permissao('avaliacoes.moderar'));
create policy criar on fotos_avaliacao for insert to authenticated
  with check (funcionalidade_activa('avaliacoes_fotos')
              and exists (select 1 from avaliacoes a
                           where a.id = avaliacao_id and a.cliente_id = cliente_actual()));
revoke update, delete, truncate on fotos_avaliacao from authenticated;

-- palavras_filtradas
create policy moderar on palavras_filtradas for all to authenticated
  using (tem_permissao('avaliacoes.moderar')) with check (tem_permissao('avaliacoes.moderar'));

-- reconhecimentos_turno
create policy ler on reconhecimentos_turno for select to authenticated
  using (tem_permissao('equipa.reconhecer')
         or exists (select 1 from turnos t
                     where t.cozinha_id = reconhecimentos_turno.cozinha_id
                       and t.funcionario_id = funcionario_actual()));
create policy criar on reconhecimentos_turno for insert to authenticated
  with check (tem_permissao('equipa.reconhecer'));
revoke update, delete, truncate on reconhecimentos_turno from authenticated;

-- pedidos_grupo
create policy ler on pedidos_grupo for select to authenticated
  using (organizador_id = cliente_actual()
         or exists (select 1 from pedidos x where x.grupo_id = pedidos_grupo.id
                                              and x.cliente_id = cliente_actual())
         or e_funcionario());
create policy criar on pedidos_grupo for insert to authenticated
  with check (funcionalidade_activa('pedidos_grupo') and cliente_actual() is not null);
create policy editar on pedidos_grupo for update to authenticated
  using (organizador_id = cliente_actual() or tem_permissao('pedidos.gerir'))
  with check (organizador_id = cliente_actual() or tem_permissao('pedidos.gerir'));
revoke delete, truncate on pedidos_grupo from authenticated;

-- notificacoes_fila e contadores_zona: só serviço (RLS activo, sem políticas)
revoke all on notificacoes_fila, contadores_zona from authenticated;

-- Vistas
revoke all on saldo_indicacao, media_avaliacoes_cozinha, media_avaliacoes_prato from anon;
grant select on saldo_indicacao, media_avaliacoes_cozinha, media_avaliacoes_prato to authenticated;

-- -----------------------------------------------------------------------------
-- Execução de funções
-- -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  -- Internas: só o servidor (jobs, triggers, outras funções)
  foreach f in array array[
    'registar_auditoria(text,text,uuid,jsonb,boolean)',
    'gerar_codigo_indicacao()', 'gerar_pseudonimo()', 'preparar_cliente_programa(uuid)',
    'avaliar_desconto_indicacao(uuid,uuid)', 'saldo_disponivel_de(uuid)',
    'aplicar_pagamentos_a_ganhos(uuid,uuid)', 'ranking_mes()', 'grupo_para_adesao(uuid)',
    'cliente_ja_comprou(uuid)', 'job_contadores_zona()', 'job_n6_expiracao()',
    'job_n5_lembrete()', 'job_n7_destaques()', 'agendar_jobs()'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;

  -- Chamáveis pelas apps (utilizador autenticado)
  foreach f in array array[
    'cozinha_padrao()', 'distancia_m(float8,float8,float8,float8)', 'mesmo_local(uuid,uuid)',
    'funcionalidade_activa(text)', 'inicio_semana_luanda()', 'inicio_dia_luanda()',
    'inicio_mes_luanda()', 'hoje_luanda()', 'normalizar_telefone(text)', 'e_escrita_cliente()',
    'cliente_actual()', 'funcionario_actual()', 'e_funcionario()', 'tem_permissao(text)',
    'exigir_permissao(text)', 'transicao_estado_valida(text,text)',
    'funcionalidade_da_notificacao(text)', 'gerar_codigo_grupo()',
    'ligar_indicacao(text)', 'registar_partilha()', 'meu_desconto_indicacao(uuid)',
    'rever_ganho(uuid,text,text)', 'definir_nivel_indicador(uuid,text)',
    'pedir_levantamento(integer,text,text)', 'usar_credito(uuid,integer)',
    'aprovar_levantamento(uuid)', 'rejeitar_levantamento(uuid,text)', 'marcar_pago(uuid,text)',
    'cancelar_pedido(uuid,text)', 'locais_proximos(float8,float8,text)',
    'avaliacao_permitida(uuid)', 'ocultar_avaliacao(uuid,boolean)', 'moderar_foto(uuid,text)',
    'grupo_por_codigo(text)', 'destaques_mes()', 'minha_posicao()', 'pessoas_como_tu()',
    'total_pago_mes()', 'contador_zona(uuid)', 'metricas_turno(uuid,date)',
    'relatorio_cozinha(uuid,date,date)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- Garantia final: todos os interruptores desligados no fim de I1
update funcionalidades set activa = false where activa;
