-- =============================================================================
-- Manda Bué — Delivery Angola
-- Modelo base (tabelas já existentes, conforme MODELO_DE_DADOS.md)
--
-- Idempotente: usa "if not exists" em tudo. Se as tabelas já existem no
-- projecto Supabase, esta migração não altera nada.
--
-- Não cria o programa de indicação antigo (indicacoes, recompensas_indicacao,
-- config_indicacao): foi substituído pelo Programa de Crescimento e a base de
-- dados de desenvolvimento não tem dados a arquivar.
--
-- Inclui a tabela pedidos (pedidos da app do cliente). O estado do pedido só é
-- alterado no servidor; ao chegar a entregue_pago gera a venda correspondente
-- (ver migração de ajustes I1). vendas continua append-only.
--
-- Campos de sincronização comuns (todas as tabelas):
--   id (UUID gerado no dispositivo), dispositivo_id, criado_em, atualizado_em,
--   sincronizado_em, deletado_em (soft-delete).
-- =============================================================================

create table if not exists direcoes (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  nome             text not null,
  permissoes       jsonb not null default '{}'      -- { "permissao": true/false }
);

create table if not exists funcionarios (
  id                        uuid primary key default gen_random_uuid(),
  dispositivo_id            text,
  criado_em                 timestamptz not null default now(),
  atualizado_em             timestamptz not null default now(),
  sincronizado_em           timestamptz,
  deletado_em               timestamptz,
  nome                      text not null,
  cargo                     text,
  direcao_id                uuid references direcoes(id),
  administrador_principal   boolean not null default false,
  permissoes_extra          jsonb not null default '{}'
);

create table if not exists clientes (
  id                uuid primary key default gen_random_uuid(),
  dispositivo_id    text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  sincronizado_em   timestamptz,
  deletado_em       timestamptz,
  tipo              text not null default 'Particular' check (tipo in ('Particular','Empresa')),
  nome              text not null,
  telefone          text,
  nif               text,
  pessoa_contacto   text,
  limite_credito    numeric(14,2) not null default 0,
  desconto          numeric(14,2) not null default 0
);

create table if not exists produtos (
  id                uuid primary key default gen_random_uuid(),
  dispositivo_id    text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  sincronizado_em   timestamptz,
  deletado_em       timestamptz,
  nome              text not null,
  categoria         text,
  tipo_estoque      text check (tipo_estoque in ('Diário','Longo Prazo')),
  categoria_medida  text check (categoria_medida in ('Peso','Volume','Unidade')),
  unidade_compra    text,
  custo             numeric(14,2),
  margem            numeric(8,2),
  iva_aplicavel     boolean not null default false,
  iva               numeric(5,2)
);

create table if not exists pratos_base (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  nome             text not null,
  componentes      jsonb not null default '[]'      -- [{produto_id, quantidade, unidade}]
);

create table if not exists zonas (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  nome             text not null,
  taxa             numeric(14,2),
  tipo             text check (tipo in ('Própria','Terceirizada')),
  modo_calculo     text check (modo_calculo in ('Fixo','Distância')),
  tarifa_por_km    numeric(14,2)
);

-- Pontos de venda / postos (não confundir com pontos_entrega do Programa de Crescimento)
create table if not exists locais (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  nome             text not null
);

create table if not exists vendas (
  id                     uuid primary key default gen_random_uuid(),
  dispositivo_id         text,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now(),
  sincronizado_em        timestamptz,
  deletado_em            timestamptz,
  data                   timestamptz not null default now(),
  produto                text,
  qtd                    numeric(14,3),
  valor_total            numeric(14,2),
  valor_antes_desconto   numeric(14,2),
  desconto_aplicado      numeric(14,2),
  local                  text,
  parcelas               jsonb not null default '[]',   -- [{metodo, valor, cliente_id, titular}]
  credito                boolean not null default false,
  cliente_id             uuid references clientes(id),
  entrega                boolean not null default false,
  zona_nome              text,
  tipo_entrega           text,
  taxa_entrega           numeric(14,2),
  prato_base_id          uuid references pratos_base(id),
  componentes_excluidos  jsonb,
  componentes_ajustados  jsonb,
  registado_por          uuid,
  aprovado_por           uuid,
  entregue_por           uuid,
  origem                 text   -- Venda direta / Pré-encomenda / Pedido especial
);

create table if not exists estoque_diario (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  produto          text,
  qtd_comprada     numeric(14,3),
  custo_total      numeric(14,2),
  data             date not null default current_date
);

create table if not exists estoque_longo_prazo (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  data             timestamptz not null default now(),
  produto_id       uuid references produtos(id),
  tipo             text check (tipo in ('Entrada','Consumo')),
  quantidade       numeric(14,3),        -- sempre em unidade base
  custo_total      numeric(14,2),
  fornecedor       text,
  validade         date
);

create table if not exists custos (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  categoria        text,
  descricao        text,
  valor            numeric(14,2),
  data             date not null default current_date
);

create table if not exists caixa (
  id                uuid primary key default gen_random_uuid(),
  dispositivo_id    text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  sincronizado_em   timestamptz,
  deletado_em       timestamptz,
  posto             text not null,
  data              date not null default current_date,
  troco_inicial     numeric(14,2),
  fechamento        jsonb,                -- inclui "diferenca" quando fechado
  sangrias          jsonb not null default '[]',
  funcionario_id    uuid,
  funcionario_nome  text
);

create table if not exists pagamentos_credito (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid references clientes(id),
  valor            numeric(14,2),
  origem           text
);

create table if not exists pre_encomendas (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid references clientes(id),
  produto          text,
  qtd              numeric(14,3),
  valor            numeric(14,2),
  hora_prevista    timestamptz,
  forma_pagamento  text,
  status           text,
  motivo           text,
  registado_por    uuid,
  entregue_por     uuid,
  cancelado_por    uuid
);

create table if not exists pedidos_especiais (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  cliente_id       uuid references clientes(id),
  cliente_nome     text,
  descricao        text,
  valor            numeric(14,2),
  forma_pagamento  text,
  status           text,
  motivo           text,
  registado_por    uuid,
  aprovado_por     uuid,
  recusado_por     uuid,
  cancelado_por    uuid,
  entregue_por     uuid
);

create table if not exists refeicoes_funcionarios (
  id               uuid primary key default gen_random_uuid(),
  dispositivo_id   text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  sincronizado_em  timestamptz,
  deletado_em      timestamptz,
  funcionario_id   uuid references funcionarios(id),
  prato            text,
  valor_custo      numeric(14,2),
  valor_desconto   numeric(14,2)
);

create table if not exists turnos (
  id                uuid primary key default gen_random_uuid(),
  dispositivo_id    text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  sincronizado_em   timestamptz,
  deletado_em       timestamptz,
  funcionario_id    uuid references funcionarios(id),
  funcionario_nome  text,
  cargo             text,
  data              date not null,
  hora_inicio       time,
  hora_fim          time
);

create table if not exists distribuicoes (
  id                     uuid primary key default gen_random_uuid(),
  dispositivo_id         text,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now(),
  sincronizado_em        timestamptz,
  deletado_em            timestamptz,
  produto_id             uuid references produtos(id),
  quantidade             numeric(14,3),
  unidade                text,
  descricao              text,
  origem                 text,
  destino                text,
  entregue_por           uuid,
  status                 text,
  recebido_por           uuid,
  hora_recebimento       timestamptz,
  quantidade_devolvida   numeric(14,3) not null default 0,
  historico_devolucoes   jsonb not null default '[]',
  quantidade_quebra      numeric(14,3) not null default 0,
  historico_quebras      jsonb not null default '[]'
);

-- Pedidos da app do cliente (cardapio-cliente). Campos do Programa de
-- Crescimento (cozinha, ponto de entrega, desconto, crédito, grupo) são
-- acrescentados na migração I1.
create table if not exists pedidos (
  id                   uuid primary key default gen_random_uuid(),
  dispositivo_id       text,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),
  sincronizado_em      timestamptz,
  deletado_em          timestamptz,
  cliente_id           uuid not null references clientes(id),
  zona_id              uuid references zonas(id),
  estado               text not null default 'pendente'
                       check (estado in ('pendente','confirmado','em_preparacao','em_entrega',
                                         'entregue_pago','cancelado','estornado')),
  itens                jsonb not null default '[]',   -- [{prato_base_id, nome, qtd, preco_unitario}]
  subtotal             int not null default 0 check (subtotal >= 0),
  taxa_entrega         int not null default 0 check (taxa_entrega >= 0),
  parcelas             jsonb not null default '[]',   -- [{metodo, valor, cliente_id, titular}]
  observacoes          text,
  motivo_cancelamento  text,
  hora_prometida       timestamptz,
  entregue_em          timestamptz
);

alter table vendas add column if not exists pedido_id uuid references pedidos(id);

create table if not exists auditoria (
  id                uuid primary key default gen_random_uuid(),
  dispositivo_id    text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  sincronizado_em   timestamptz,
  deletado_em       timestamptz,
  data              timestamptz not null default now(),
  funcionario_id    uuid,
  funcionario_nome  text,
  acao              text not null,
  detalhe           text,
  ref_id            uuid,
  ref_tipo          text,
  bloqueado         boolean not null default false
);

-- Índices recomendados
create index if not exists vendas_data_idx              on vendas (data);
create index if not exists vendas_cliente_idx           on vendas (cliente_id);
create index if not exists vendas_local_idx             on vendas (local);
create index if not exists estoque_lp_produto_tipo_idx  on estoque_longo_prazo (produto_id, tipo, data);
create index if not exists auditoria_data_idx           on auditoria (data);
create index if not exists auditoria_ref_idx            on auditoria (ref_id);
create index if not exists caixa_posto_data_idx         on caixa (posto, data);
create index if not exists vendas_pedido_idx            on vendas (pedido_id);
create index if not exists pedidos_cliente_estado_idx   on pedidos (cliente_id, estado);
create index if not exists pedidos_estado_entregue_idx  on pedidos (estado, entregue_em);
create index if not exists pedidos_dispositivo_idx      on pedidos (dispositivo_id);

-- Segurança por defeito: RLS activo em todas as tabelas base e sem acesso
-- anónimo. Sem políticas, só o servidor (funções security definer e
-- service_role) lê e escreve. As políticas de cada app são acrescentadas
-- nas migrações seguintes (as de pedidos na migração I1).
do $$
declare
  t text;
begin
  foreach t in array array['direcoes','funcionarios','clientes','produtos','pratos_base','zonas','locais',
                           'vendas','estoque_diario','estoque_longo_prazo','custos','caixa',
                           'pagamentos_credito','pre_encomendas','pedidos_especiais',
                           'refeicoes_funcionarios','turnos','distribuicoes','pedidos','auditoria'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;

-- Catálogo legível por utilizadores autenticados
drop policy if exists ler on zonas;
create policy ler on zonas for select to authenticated using (deletado_em is null);
drop policy if exists ler on pratos_base;
create policy ler on pratos_base for select to authenticated using (deletado_em is null);
