# Projecto Completo: Programa de Crescimento
## Manda Bué — Delivery Angola

Versão 1.0 · Setembro de 2026

Este documento **substitui** as adendas anteriores (`REGRAS_DE_NEGOCIO_ADENDA.md`, `MODELO_DE_DADOS_ADENDA.md`, `TELAS_ADENDA.md`, `PLANO_DE_FASES_ADENDA.md`). É a especificação única para o Claude Code implementar, na versão Expo/React Native + Supabase, tudo o que diz respeito a:

- programa de indicação **Convida e Ganha**;
- prova social e reforço vicário (lista de destaques, "pessoas como tu", contadores por zona, avaliações);
- **pedidos de grupo**;
- **reconhecimento de equipa** por turno;
- preparação para a **rede de várias cozinhas**, começando pela Cozinha da Alexandra.

O modelo de dados é desenhado **completo desde o início**. As funcionalidades são construídas por fases e activadas por **interruptores** no painel do operador.

---

## Índice

1. Princípios
2. Glossário
3. Arquitectura
4. Regras de negócio
5. Modelo de dados
6. Funções e triggers
7. Vistas
8. Segurança (RLS) e permissões
9. Ecrãs da app do cliente
10. Ecrãs da app do operador e da entrega
11. Notificações
12. Plano de fases
13. Testes de aceitação
14. Métricas
15. Instrução para o Claude Code
16. Decisões em aberto

---

## 1. Princípios

1. **O servidor calcula, a app mostra.** Ganhos, saldos, descontos, destaques, contadores e métricas são calculados no Supabase. O telemóvel nunca decide um valor.
2. **Nada fixo no código.** Todos os valores monetários, prazos e limites vêm de `parametros`.
3. **Tudo desenhado, nada ligado antes do tempo.** Cada funcionalidade tem um interruptor em `funcionalidades`.
4. **Só dados reais.** É proibido mostrar participantes, contadores, avaliações ou ganhos fictícios. Quando não há dados suficientes, o bloco não aparece.
5. **Privacidade por defeito.** Clientes aparecem com pseudónimo; ninguém é exposto sem escolher; a equipa é reconhecida por turno, nunca comparada individualmente em público.
6. **Pronto para várias cozinhas.** Tudo o que é operacional tem `cozinha_id`. O programa de indicação pertence à plataforma, não a uma cozinha.
7. **Ganhos legítimos nunca são cortados.** Casos duvidosos vão para verificação humana, não para anulação automática.
8. **Tudo auditado.** Criações, alterações de estado, aprovações e mudanças de parâmetros ficam no sistema de auditoria existente.

---

## 2. Glossário

| Termo | Significado |
|---|---|
| Plataforma | Manda Bué — Delivery Angola: app, entregas, programa de indicação, rede de cozinhas |
| Cozinha | Unidade que prepara os pratos. A primeira é a **Cozinha da Alexandra** |
| Indicador | Cliente que partilha o seu código |
| Indicado | Cliente novo que usa o código de um indicador |
| Embaixador | Indicador de alto volume com acordo próprio |
| Ligação | Relação permanente indicado → indicador |
| Ganho | 100 Kz por pedido pago do indicado, durante o período |
| Local | Ponto físico de entrega (coordenadas + referência), partilhável por vários clientes |
| Interruptor | Registo em `funcionalidades` que liga ou desliga uma funcionalidade |

---

## 3. Arquitectura

- **Cliente:** Expo/React Native. Duas apps: operador e cliente (cardapio-cliente).
- **Dados locais:** SQLite, local-first, com sincronização.
- **Servidor:** Supabase (Postgres, Auth por telefone/SMS, Storage, Edge Functions, RLS).
- **Pagamentos de pedidos:** na entrega (fase inicial).
- **Pagamentos a indicadores:** crédito interno ou levantamento manual por Multicaixa Express / Unitel Money, com registo de referência.

### Regras de sincronização
- Tabelas **escritas pelo cliente:** pedidos (estado inicial), participação em grupos, avaliações, pedidos de levantamento (estado `pedido`), definições de privacidade.
- Tabelas **só de leitura no telemóvel:** ganhos, saldos, destaques, contadores, parâmetros, interruptores, métricas.
- Pedidos criados offline sincronizam normalmente. Os efeitos do programa (ganhos, desconto confirmado) só acontecem no servidor quando o pedido chega com o estado correspondente.

### Interruptores (`funcionalidades`)

| Chave | Activa | Fase |
|---|---|---|
| `indicacao` | Programa Convida e Ganha | I2 |
| `destaques` | Lista de destaques | I4 |
| `pessoas_como_tu` | Bloco de exemplos alcançáveis | I2 |
| `contadores_zona` | "Pedidos no teu bairro hoje" | I2 |
| `perfil_cozinha` | Ecrã público da cozinha | I2 |
| `avaliacoes` | Estrelas e comentários | I5 |
| `avaliacoes_fotos` | Fotos nas avaliações (com moderação) | I7 |
| `reconhecimento_equipa` | Métricas e reconhecimento por turno | I5 |
| `pedidos_grupo` | Pedidos de grupo | I6 |
| `multi_cozinha` | Mais de uma cozinha visível ao cliente | I8 |

A app lê os interruptores ao arrancar e após cada sincronização. Uma funcionalidade desligada não mostra ecrãs, botões nem notificações.

---

## 4. Regras de negócio

Valores entre `[ ]` são parâmetros (tabela `parametros`) com o valor inicial indicado.

### 4.1 Cozinhas
- Cada cozinha tem nome, responsável, foto, história curta e estado (`activa`, `pausada`, `inactiva`).
- A primeira cozinha é a **Cozinha da Alexandra**. Enquanto `multi_cozinha` estiver desligado, o cliente vê apenas esta cozinha, mas os dados já levam `cozinha_id`.
- O perfil público de uma cozinha só aparece se `consentimento_publico = true` (autorização da responsável para mostrar nome, foto e história).
- Pratos, stock, turnos, caixas e pedidos pertencem a uma cozinha.
- O programa de indicação é da plataforma: o indicador ganha o mesmo, seja qual for a cozinha que preparou o pedido.

### 4.2 Locais e endereços
- Cada endereço de cliente aponta para um **local** (`locais`): coordenadas (pin no mapa), zona de entrega, referência escrita e **tipo** (`residencial` ou `empresa`).
- Dois endereços são o **mesmo local** se estiverem a menos de `[raio_mesmo_local_m = 25]` metros e tiverem o mesmo tipo. A app sugere um local existente quando o pin cai dentro desse raio, para evitar duplicados.
- Clientes do tipo Empresa (com NIF) usam locais do tipo `empresa`. Um cliente Particular pode marcar um endereço como "trabalho" (`empresa`).

### 4.3 Convida e Ganha

**Código**
- Formato `MB-` + 4 dígitos (passa a 5 quando esgotar). Gerado no registo, único, permanente.
- Não deriva do nome nem do telefone.

**Ligação**
- O indicado insere o código no registo ou no checkout do primeiro pedido (ou chega pelo link de convite, que o pré-preenche).
- Única e permanente. Não se troca de indicador.
- Bloqueios: próprio código; cliente que já tem um pedido `entregue_pago`; código inexistente.

**Ganho do indicado**
- `[desconto_indicado = 500 Kz]` no primeiro pedido.
- Validado no servidor. Se o primeiro pedido for cancelado, o desconto fica disponível para o seguinte.
- Limite por local residencial: no máximo `[max_descontos_por_local = 3]` descontos de primeiro pedido. A partir daí, a app informa "Este convite já foi usado o número máximo de vezes nesta morada" e o pedido segue sem desconto. Locais `empresa` não têm este limite.

**Ganho do indicador**
- `[ganho_por_pedido = 100 Kz]` por cada pedido do indicado que chegue a `entregue_pago`.
- Período: `[duracao_dias = 60]` dias **a contar do primeiro pedido entregue e pago do indicado**.
- Um ganho por pedido, no máximo.
- **Sem teto de ganhos.**

**Estados do ganho**

| Estado | Significado |
|---|---|
| `em_verificacao` | Criado, mas precisa de revisão humana (limite semanal ou sinal de fraude médio) |
| `confirmado` | Conta para o saldo |
| `pago` | Já incluído num crédito ou levantamento concluído |
| `anulado` | Não conta. Guarda `motivo_anulacao` |

O ganho só é criado quando o pedido está `entregue_pago`. Se um pedido for estornado depois disso e o ganho ainda não estiver `pago`, passa a `anulado` (`pedido_estornado`).

**Limite de verificação semanal**
- `[limite_verificacao_semanal = 10000 Kz]`, semana de segunda a domingo, fuso `Africa/Luanda`.
- Quando os ganhos `confirmado` + `pago` da semana atingem o limite, os seguintes entram como `em_verificacao`.
- Embaixadores estão isentos deste limite (não das regras anti-fraude).

**Embaixador**
- Elegível a partir de `[limiar_embaixador = 30]` indicados activos.
- Atribuído manualmente pelo operador após contacto pessoal.
- Vantagens: isenção do limite semanal, pagamento semanal garantido, contacto directo.

### 4.4 Anti-fraude: sinais combinados

O mesmo endereço **sozinho** é um sinal fraco (colegas de casa, colegas de escritório). A decisão combina sinais:

| Situação | Resultado |
|---|---|
| Indicador e indicado usaram o **mesmo dispositivo** | `anulado` (`mesmo_dispositivo`) |
| Mesmo local **empresa** | Permitido (segue as restantes regras) |
| Mesmo local **residencial**, tudo o resto diferente | Permitido |
| Mesmo local residencial **e** mesmo número de levantamento (Multicaixa Express / Unitel Money) | `em_verificacao` (`numero_pagamento_partilhado`) |
| Mesmo local residencial e o local já tem `[max_indicados_por_local = 3]` indicados com ganhos | `em_verificacao` (`limite_local`) |
| Indicado usou o **mesmo número de levantamento** que o indicador (qualquer local) | `em_verificacao` (`numero_pagamento_partilhado`) |

Informação de apoio para o operador (não decide sozinha):
- Marcação do entregador **"pago por outra pessoa"** quando entrega a contas diferentes no mesmo local.
- Histórico de pedidos em conjunto (mesma hora, mesmo local).

A anulação por verificação exige motivo escrito e fica na auditoria.

### 4.5 Saldo e pagamentos
- **Saldo disponível** = ganhos `confirmado` − pagamentos em curso (`pedido`, `aprovado`).
- `[levantamento_minimo = 2000 Kz]`.
- **Crédito:** usado como forma de pagamento nos próprios pedidos. Imediato. Soma-se aos métodos mistos de pagamento que a app já suporta.
- **Levantamento:** Multicaixa Express ou Unitel Money, para um número indicado pelo cliente. Manual na fase inicial.
- Acima de `[limite_parcelamento = 20000 Kz]`: 2 parcelas na mesma semana.
- Aprovação por utilizador com `indicacoes.aprovar_pagamentos`.
- Meta operacional: **primeiro levantamento pago no próprio dia**.
- Ao marcar um pagamento como `pago`, os ganhos `confirmado` mais antigos até ao valor passam a `pago`.

### 4.6 Lista de destaques
- Período: mês corrente, recomeça a cada dia 1.
- Só entram ganhos `confirmado` e `pago` com `confirmado_em` no mês.
- Nome exibido: **pseudónimo** por defeito (ex.: "Palanca Azul", "Imbondeiro 27"), gerado no registo sem ligação a dados pessoais. O cliente pode optar por mostrar o primeiro nome ou sair da lista.
- Cada entrada: posição, nome exibido, n.º de amigos com ganho no mês, valor do mês.
- Top `[tamanho_top = 10]`. O próprio cliente vê sempre a sua posição com "(tu)" e a distância para o top.
- Enquanto a lista tiver menos de `[limiar_intervalos = 20]` participantes, os valores aparecem em intervalos de 10.000 Kz.
- Mostra o total pago pelo programa no mês.

### 4.7 Pessoas como tu e contadores por zona
- **Pessoas como tu:** 2–3 exemplos reais do mês de indicadores com `[pessoas_como_tu_min = 3]` a `[pessoas_como_tu_max = 10]` amigos, com pseudónimo e valor. Aparece no ecrã Convida e Ganha e no **ecrã de fim de pedido**. Se não houver pelo menos 2 exemplos, o bloco não aparece.
- **Contadores por zona:** "X pedidos no teu bairro hoje", com base nas zonas de entrega existentes. Actualizado de hora a hora. Só aparece com pelo menos `[contador_minimo = 10]` pedidos.

### 4.8 Avaliações
- Uma avaliação por pedido entregue: estrelas (1–5) e comentário opcional até 200 caracteres.
- Disponível até `[prazo_avaliacao_dias = 3]` dias após a entrega.
- Comentários passam por filtro de palavras e podem ser ocultados pelo operador.
- **Fotos** (`avaliacoes_fotos`): até 2 por avaliação, publicadas só depois de aprovadas por um moderador (`avaliacoes.moderar`).
- A média de estrelas aparece por prato e por cozinha só com pelo menos `[avaliacoes_minimo = 5]` avaliações.
- Nome do autor: primeiro nome e inicial do apelido, ou pseudónimo se o cliente preferir.

### 4.9 Pedidos de grupo
- Um cliente **organiza** um grupo: local de entrega, hora de entrega e prazo para os colegas aderirem.
- Partilha por link/WhatsApp. Cada participante faz o **seu próprio pedido** dentro do grupo.
- Modo de pagamento: `individual` (cada um paga o seu na entrega) ou `empresa` (cliente Empresa paga tudo, com NIF na factura).
- Uma só entrega; a taxa de entrega é dividida pelos participantes ou coberta pela empresa, conforme `[regra_taxa_grupo = dividir]`.
- Cada pedido do grupo conta normalmente para o programa de indicação. Pedidos de grupo acontecem em locais `empresa`, por isso não activam o limite por local.
- Participantes novos podem usar o código de quem os convidou para o grupo.

### 4.10 Reconhecimento de equipa
- Métricas **por turno de cozinha**, semanais:
  - desperdício (da reconciliação de stock);
  - entregas a horas (pedido entregue até à hora prometida + `[tolerancia_entrega_min = 15]` minutos);
  - diferença de caixa (das caixas multi-posto).
- O operador pode registar um **reconhecimento** para um turno, com nota. Visível para os membros da cozinha na app do operador.
- Nunca há rankings públicos de pessoas. A auditoria não é usada para expor erros.

### 4.11 Relatórios de cozinha
- Por cozinha e por período: pedidos por dia, clientes novos, clientes vindos de indicação, retenção a 30/60/90 dias, média de avaliação, prato mais pedido.
- Exportação em CSV/PDF para uso comercial (recrutamento de cozinhas parceiras).

### 4.12 Permissões novas (organograma)

| Permissão | Permite |
|---|---|
| `indicacoes.ver` | Painel do programa e relatórios |
| `indicacoes.verificar` | Confirmar ou anular ganhos em verificação |
| `indicacoes.aprovar_pagamentos` | Aprovar e marcar levantamentos |
| `plataforma.parametros` | Alterar parâmetros, interruptores e nível Embaixador |
| `avaliacoes.moderar` | Aprovar fotos e ocultar comentários |
| `cozinhas.gerir` | Criar e editar cozinhas e perfis |
| `equipa.reconhecer` | Registar reconhecimentos de turno |
| `relatorios.exportar` | Exportar relatórios de cozinha |

### 4.13 Texto das regras para o cliente

> Ganhas 100 Kz por cada pedido dos amigos que convidares, durante 60 dias a contar do primeiro pedido deles. Não há limite de ganhos.
> O teu amigo ganha 500 Kz de desconto no primeiro pedido.
> Levantas o saldo a partir de 2.000 Kz ou usas em refeições. Acima de 10.000 Kz por semana, confirmamos os pedidos antes de pagar.
> Ganhos de contas falsas ou pedidos não pagos são anulados.
> Os teus ganhos podem aparecer na lista de destaques com um nome fictício. Podes sair da lista quando quiseres.

Os valores são preenchidos a partir de `parametros`.

---

## 5. Modelo de dados

> **Antes de aplicar:** os nomes `clientes`, `pedidos`, `pratos`, `turnos`, `caixas`, `movimentos_stock`, `zonas_entrega` e o estado `entregue_pago` são assumidos. Confirmar no `MODELO_DE_DADOS.md` existente e ajustar. Assume-se também uma função `cliente_actual()` que devolve o `clientes.id` do utilizador autenticado.

Valores monetários em **kwanzas inteiros** (`int`). Datas em `timestamptz`.

### 5.1 Configuração

```sql
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
  actualizado_em              timestamptz not null default now(),
  actualizado_por             uuid
);
insert into parametros (id) values (1);

create table funcionalidades (
  chave            text primary key,
  activa           boolean not null default false,
  actualizado_em   timestamptz not null default now(),
  actualizado_por  uuid
);
insert into funcionalidades (chave) values
  ('indicacao'),('destaques'),('pessoas_como_tu'),('contadores_zona'),
  ('perfil_cozinha'),('avaliacoes'),('avaliacoes_fotos'),
  ('reconhecimento_equipa'),('pedidos_grupo'),('multi_cozinha');
```

### 5.2 Cozinhas

```sql
create table cozinhas (
  id                     uuid primary key default gen_random_uuid(),
  nome                   text not null,              -- 'Cozinha da Alexandra'
  responsavel            text not null,
  foto_url               text,
  historia               text,
  estado                 text not null default 'activa'
                         check (estado in ('activa','pausada','inactiva')),
  consentimento_publico  boolean not null default false,
  criado_em              timestamptz not null default now()
);

-- Tabelas operacionais existentes passam a pertencer a uma cozinha
alter table pratos           add column cozinha_id uuid references cozinhas(id);
alter table turnos           add column cozinha_id uuid references cozinhas(id);
alter table caixas           add column cozinha_id uuid references cozinhas(id);
alter table movimentos_stock add column cozinha_id uuid references cozinhas(id);
-- Migração: criar a Cozinha da Alexandra e preencher cozinha_id em todas as linhas existentes;
-- depois tornar a coluna not null.
```

### 5.3 Locais e endereços

```sql
create table locais (
  id          uuid primary key default gen_random_uuid(),
  tipo        text not null check (tipo in ('residencial','empresa')),
  lat         double precision not null,
  lng         double precision not null,
  zona_id     uuid references zonas_entrega(id),
  referencia  text,                         -- 'Prédio azul, 3.º andar, porta 12'
  criado_em   timestamptz not null default now()
);
create index on locais (zona_id);

create table enderecos_cliente (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references clientes(id),
  local_id    uuid not null references locais(id),
  nome        text not null default 'Casa',  -- 'Casa', 'Trabalho'
  principal   boolean not null default false
);
```

### 5.4 Campos novos em `pedidos`

```sql
alter table pedidos
  add column cozinha_id          uuid references cozinhas(id),
  add column local_id            uuid references locais(id),
  add column dispositivo_id      text,          -- identificador de instalação da app
  add column desconto_indicacao  int not null default 0,   -- só o servidor escreve
  add column credito_usado       int not null default 0,   -- saldo de indicação usado
  add column grupo_id            uuid,           -- FK adicionada em 5.8
  add column hora_prometida      timestamptz,
  add column entregue_em         timestamptz,
  add column pagador_distinto    boolean;        -- marcado pelo entregador
```

### 5.5 Convida e Ganha

```sql
create table codigos_indicacao (
  cliente_id  uuid primary key references clientes(id),
  codigo      text not null unique,
  nivel       text not null default 'normal' check (nivel in ('normal','embaixador')),
  criado_em   timestamptz not null default now()
);

create table ligacoes_indicacao (
  indicado_id         uuid primary key references clientes(id),
  indicador_id        uuid not null references clientes(id),
  ligado_em           timestamptz not null default now(),
  primeiro_pedido_id  uuid references pedidos(id),
  expira_em           timestamptz,     -- null até ao 1.º pedido entregue e pago
  desconto_usado      boolean not null default false,
  check (indicado_id <> indicador_id)
);
create index on ligacoes_indicacao (indicador_id);

create table ganhos_indicacao (
  id               uuid primary key default gen_random_uuid(),
  pedido_id        uuid not null unique references pedidos(id),
  indicador_id     uuid not null references clientes(id),
  indicado_id      uuid not null references clientes(id),
  valor            int not null,
  estado           text not null
                   check (estado in ('em_verificacao','confirmado','pago','anulado')),
  motivo           text,   -- verificação: 'limite_semanal','limite_local','numero_pagamento_partilhado'
                           -- anulação: 'mesmo_dispositivo','pedido_estornado','rejeitado_verificacao'
  revisto_por      uuid,
  revisto_em       timestamptz,
  pagamento_id     uuid,
  criado_em        timestamptz not null default now(),
  confirmado_em    timestamptz
);
create index on ganhos_indicacao (indicador_id, estado);
create index on ganhos_indicacao (confirmado_em);

create table pagamentos_indicacao (
  id              uuid primary key default gen_random_uuid(),
  indicador_id    uuid not null references clientes(id),
  valor           int not null check (valor > 0),
  tipo            text not null check (tipo in ('credito','levantamento')),
  metodo          text check (metodo in ('multicaixa_express','unitel_money')),
  numero_destino  text,           -- telefone da carteira; usado nos sinais anti-fraude
  pedido_id       uuid references pedidos(id),   -- quando tipo = 'credito'
  grupo_id        uuid,           -- liga parcelas do mesmo levantamento
  parcela         int not null default 1,
  total_parcelas  int not null default 1,
  estado          text not null default 'pedido'
                  check (estado in ('pedido','aprovado','pago','rejeitado')),
  referencia      text,
  aprovado_por    uuid,
  pago_em         timestamptz,
  criado_em       timestamptz not null default now()
);
create index on pagamentos_indicacao (indicador_id, estado);
create index on pagamentos_indicacao (numero_destino);

create table perfil_destaques (
  cliente_id         uuid primary key references clientes(id),
  pseudonimo         text not null unique,
  mostrar_nome_real  boolean not null default false,
  sair_da_lista      boolean not null default false
);
```

### 5.6 Avaliações

```sql
create table avaliacoes (
  id              uuid primary key default gen_random_uuid(),
  pedido_id       uuid not null unique references pedidos(id),
  cliente_id      uuid not null references clientes(id),
  cozinha_id      uuid not null references cozinhas(id),
  estrelas        int not null check (estrelas between 1 and 5),
  comentario      text check (char_length(comentario) <= 200),
  oculta          boolean not null default false,
  ocultada_por    uuid,
  usar_pseudonimo boolean not null default false,
  criado_em       timestamptz not null default now()
);

create table avaliacoes_pratos (   -- estrelas por prato dentro do pedido (opcional)
  avaliacao_id  uuid references avaliacoes(id) on delete cascade,
  prato_id      uuid references pratos(id),
  estrelas      int not null check (estrelas between 1 and 5),
  primary key (avaliacao_id, prato_id)
);

create table fotos_avaliacao (
  id            uuid primary key default gen_random_uuid(),
  avaliacao_id  uuid not null references avaliacoes(id) on delete cascade,
  caminho       text not null,        -- Supabase Storage, bucket privado até aprovação
  estado        text not null default 'pendente'
                check (estado in ('pendente','aprovada','rejeitada')),
  moderado_por  uuid,
  moderado_em   timestamptz
);
```

### 5.7 Reconhecimento de equipa

```sql
create table reconhecimentos_turno (
  id          uuid primary key default gen_random_uuid(),
  turno_id    uuid not null references turnos(id),
  cozinha_id  uuid not null references cozinhas(id),
  semana      date not null,          -- segunda-feira da semana
  tipo        text not null check (tipo in ('menos_desperdicio','entregas_a_horas','caixa_certa','outro')),
  nota        text,
  criado_por  uuid not null,
  criado_em   timestamptz not null default now()
);
```

### 5.8 Pedidos de grupo

```sql
create table pedidos_grupo (
  id               uuid primary key default gen_random_uuid(),
  organizador_id   uuid not null references clientes(id),
  empresa_id       uuid references clientes(id),       -- cliente Empresa, quando paga
  local_id         uuid not null references locais(id),
  cozinha_id       uuid not null references cozinhas(id),
  hora_entrega     timestamptz not null,
  prazo_adesao     timestamptz not null,
  modo_pagamento   text not null check (modo_pagamento in ('individual','empresa')),
  codigo_convite   text not null unique,              -- para o link de adesão
  estado           text not null default 'aberto'
                   check (estado in ('aberto','fechado','em_preparacao','entregue','cancelado')),
  criado_em        timestamptz not null default now()
);
alter table pedidos add constraint pedidos_grupo_fk
  foreign key (grupo_id) references pedidos_grupo(id);
```

### 5.9 Fila de notificações

```sql
create table notificacoes_fila (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references clientes(id),
  codigo      text not null,        -- 'N2','N3',... ver secção 11
  dados       jsonb not null default '{}',
  enviada_em  timestamptz,
  criado_em   timestamptz not null default now()
);
```

Uma Edge Function lê a fila e envia as notificações push (Expo Push), respeitando os interruptores e as preferências do cliente.

---

## 6. Funções e triggers

### 6.1 Utilitários

```sql
create or replace function distancia_m(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8 language sql immutable as $$
  select 6371000 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

create or replace function mesmo_local(a uuid, b uuid)
returns boolean language sql stable as $$
  select a = b or exists (
    select 1 from locais la, locais lb, parametros p
    where la.id = a and lb.id = b and p.id = 1
      and la.tipo = lb.tipo
      and distancia_m(la.lat, la.lng, lb.lat, lb.lng) <= p.raio_mesmo_local_m
  );
$$;

create or replace function funcionalidade_activa(k text)
returns boolean language sql stable as $$
  select coalesce((select activa from funcionalidades where chave = k), false);
$$;

create or replace function inicio_semana_luanda()
returns timestamptz language sql stable as $$
  select date_trunc('week', now() at time zone 'Africa/Luanda') at time zone 'Africa/Luanda';
$$;
```

### 6.2 Registo de cliente
Trigger `after insert on clientes`:
1. Gerar código `MB-` + 4 dígitos aleatórios; repetir em colisão.
2. Gerar pseudónimo único a partir de listas de palavras (animais, árvores, lugares e símbolos angolanos + cor ou número). Nunca usar dados do cliente.
3. Inserir em `codigos_indicacao` e `perfil_destaques`.

### 6.3 `ligar_indicacao(p_codigo text)`
`security definer`, usa `cliente_actual()`. Valida por esta ordem e devolve um código de erro legível pela app:
- `programa_inactivo` se `indicacao` desligado;
- `codigo_inexistente`;
- `proprio_codigo`;
- `ja_ligado`;
- `cliente_nao_novo` se já existe pedido `entregue_pago`.
Se tudo passar, cria a linha em `ligacoes_indicacao` e enfileira `N2` para o indicador.

### 6.4 Desconto no pedido (`before insert on pedidos`)
O servidor ignora qualquer valor enviado pela app em `desconto_indicacao` e recalcula:

```sql
create or replace function calcular_desconto_indicacao()
returns trigger language plpgsql security definer as $$
declare
  p parametros; lig ligacoes_indicacao; loc locais; usados int;
begin
  new.desconto_indicacao := 0;
  if not funcionalidade_activa('indicacao') then return new; end if;

  select * into p from parametros where id = 1;
  select * into lig from ligacoes_indicacao where indicado_id = new.cliente_id;
  if not found or lig.desconto_usado then return new; end if;

  if exists (select 1 from pedidos
             where cliente_id = new.cliente_id and estado = 'entregue_pago') then
    return new;
  end if;

  select * into loc from locais where id = new.local_id;
  if loc.tipo = 'residencial' then
    select count(*) into usados
      from pedidos x
     where x.desconto_indicacao > 0 and x.estado = 'entregue_pago'
       and mesmo_local(x.local_id, new.local_id);
    if usados >= p.max_descontos_por_local then return new; end if;
  end if;

  new.desconto_indicacao := p.desconto_indicado;
  return new;
end $$;

create trigger trg_desconto_indicacao
before insert on pedidos
for each row execute function calcular_desconto_indicacao();
```

### 6.5 Ganho do indicador (`after update of estado on pedidos`)

```sql
create or replace function processar_ganho_indicacao()
returns trigger language plpgsql security definer as $$
declare
  p            parametros;
  lig          ligacoes_indicacao;
  loc          locais;
  nivel_ind    text;
  total_sem    int;
  indicados_local int;
  v_estado     text := 'confirmado';
  v_motivo     text := null;
begin
  -- Estorno de um pedido já pago
  if old.estado = 'entregue_pago' and new.estado <> 'entregue_pago' then
    update ganhos_indicacao
       set estado = 'anulado', motivo = 'pedido_estornado'
     where pedido_id = new.id and estado <> 'pago';
    return new;
  end if;

  if new.estado <> 'entregue_pago' or old.estado = 'entregue_pago' then
    return new;
  end if;
  if not funcionalidade_activa('indicacao') then return new; end if;

  select * into p from parametros where id = 1;
  select * into lig from ligacoes_indicacao where indicado_id = new.cliente_id;
  if not found then return new; end if;

  -- 1.º pedido pago: arranca o período
  if lig.expira_em is null then
    update ligacoes_indicacao
       set primeiro_pedido_id = new.id,
           expira_em = now() + make_interval(days => p.duracao_dias),
           desconto_usado = (new.desconto_indicacao > 0)
     where indicado_id = new.cliente_id
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
  select * into loc from locais where id = new.local_id;
  if v_estado = 'confirmado' and loc.tipo = 'residencial' then
    select count(distinct g.indicado_id) into indicados_local
      from ganhos_indicacao g join pedidos x on x.id = g.pedido_id
     where g.estado <> 'anulado'
       and g.indicado_id <> new.cliente_id
       and mesmo_local(x.local_id, new.local_id);
    if indicados_local >= p.max_indicados_por_local then
      v_estado := 'em_verificacao'; v_motivo := 'limite_local';
    end if;
  end if;

  -- Limite semanal (não se aplica a Embaixadores)
  if v_estado = 'confirmado' then
    select nivel into nivel_ind from codigos_indicacao where cliente_id = lig.indicador_id;
    if nivel_ind <> 'embaixador' then
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
    (pedido_id, indicador_id, indicado_id, valor, estado, motivo, confirmado_em)
  values
    (new.id, lig.indicador_id, new.cliente_id, p.ganho_por_pedido, v_estado, v_motivo,
     case when v_estado = 'confirmado' then now() end);

  -- Auditoria (sistema existente) e notificações
  -- perform registar_auditoria('ganho_indicacao', new.id, v_estado, v_motivo);
  if v_estado = 'confirmado' then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N3', jsonb_build_object('pedido_id', new.id));
  elsif v_estado = 'em_verificacao' and v_motivo = 'limite_semanal'
        and not exists (select 1 from ganhos_indicacao
                         where indicador_id = lig.indicador_id
                           and motivo = 'limite_semanal'
                           and criado_em >= inicio_semana_luanda()
                           and pedido_id <> new.id) then
    insert into notificacoes_fila (cliente_id, codigo, dados)
    values (lig.indicador_id, 'N4', '{}');
  end if;

  return new;
end $$;

create trigger trg_ganho_indicacao
after update of estado on pedidos
for each row execute function processar_ganho_indicacao();
```

### 6.6 Revisão de ganhos
`rever_ganho(p_ganho uuid, p_decisao text, p_motivo text)`: exige `indicacoes.verificar`. `confirmar` → `confirmado` com `confirmado_em = now()`; `anular` → `anulado`, `motivo = 'rejeitado_verificacao'`, motivo escrito obrigatório guardado na auditoria.

### 6.7 Pagamentos
- `pedir_levantamento(p_valor, p_metodo, p_numero)`: valida saldo, mínimo e interruptor; cria 1 ou 2 parcelas (acima de `limite_parcelamento`) com o mesmo `grupo_id`.
- `usar_credito(p_pedido, p_valor)`: valida saldo; cria pagamento `tipo = 'credito'`, `estado = 'pago'`; actualiza `pedidos.credito_usado`.
- `marcar_pago(p_pagamento, p_referencia)`: exige `indicacoes.aprovar_pagamentos` e referência; passa ganhos `confirmado` mais antigos a `pago` até ao valor; enfileira `N8`.

### 6.8 Jobs agendados (pg_cron ou Edge Function agendada)
- **De hora a hora:** recalcular contadores por zona.
- **Diariamente às 08h:** enfileirar `N6` para indicados que expiram em 5 dias.
- **Dias úteis às 11h:** enfileirar `N5` (máx. 2 por semana por cliente, só quem já partilhou, respeitando preferências).
- **Semanalmente:** enfileirar `N7` para quem está a até 3 amigos do top; calcular métricas de turno.

---

## 7. Vistas e funções de leitura

- **`saldo_indicacao`** (por indicador): `saldo_disponivel` = soma `confirmado` − soma pagamentos `pedido`/`aprovado`; `em_verificacao` = soma `em_verificacao`; ganhos de hoje e da semana.
- **`destaques_mes()`**: devolve posição, nome exibido (pseudónimo ou primeiro nome), n.º de amigos com ganho no mês, valor do mês ou intervalo (se participantes < `limiar_intervalos`). Exclui `sair_da_lista`. **Nunca** devolve ids nem telefones.
- **`minha_posicao()`**: posição do cliente autenticado e amigos em falta para o top.
- **`pessoas_como_tu()`**: 2–3 entradas reais entre `pessoas_como_tu_min` e `pessoas_como_tu_max` amigos; devolve vazio se houver menos de 2.
- **`total_pago_mes()`**: soma dos pagamentos `pago` no mês.
- **`contador_zona(p_zona)`**: pedidos `entregue_pago` hoje na zona; devolve `null` abaixo de `contador_minimo`.
- **`media_avaliacoes`**: média de estrelas por prato e por cozinha, só com `avaliacoes_minimo` ou mais (excluindo ocultas).
- **`metricas_turno`**: por turno e semana — desperdício (reconciliação de stock), % entregas a horas (`entregue_em <= hora_prometida + tolerancia_entrega_min`), diferença de caixa.
- **`relatorio_cozinha(p_cozinha, p_inicio, p_fim)`**: pedidos por dia, clientes novos, clientes vindos de indicação, retenção 30/60/90 dias, média de avaliação, prato mais pedido.

---

## 8. Segurança (RLS) e permissões

| Tabela | Cliente | Operador |
|---|---|---|
| `parametros`, `funcionalidades` | Ler | Escrever com `plataforma.parametros` |
| `cozinhas` | Ler activas com `consentimento_publico` | Escrever com `cozinhas.gerir` |
| `locais`, `enderecos_cliente` | Ler/escrever os seus | Ler |
| `codigos_indicacao` | Ler o seu | Ler; mudar `nivel` com `plataforma.parametros` |
| `ligacoes_indicacao` | Ler onde é indicador ou indicado; criar só via `ligar_indicacao` | Ler |
| `ganhos_indicacao` | Ler onde é indicador | Ler com `indicacoes.ver`; rever com `indicacoes.verificar` |
| `pagamentos_indicacao` | Ler os seus; criar só via funções | Aprovar com `indicacoes.aprovar_pagamentos` |
| `perfil_destaques` | Ler o seu; actualizar só `mostrar_nome_real` e `sair_da_lista` | Ler |
| `avaliacoes` | Criar para pedido próprio entregue dentro do prazo; ler não ocultas | Ocultar com `avaliacoes.moderar` |
| `fotos_avaliacao` | Enviar para avaliação própria; ler aprovadas | Moderar com `avaliacoes.moderar` |
| `pedidos_grupo` | Criar; ler os grupos em que participa ou com código válido | Ler |
| `reconhecimentos_turno` | — | Criar com `equipa.reconhecer`; membros da cozinha lêem |
| `notificacoes_fila` | — | Só serviço |

Campos que **só o servidor** escreve em `pedidos`: `desconto_indicacao`, `credito_usado`, `entregue_em`. `pagador_distinto` só por utilizadores com papel de entrega.

---

## 9. Ecrãs da app do cliente (cardapio-cliente)

### Marca
- **Manda Bué** como marca principal; **Delivery Angola** como descritivo, em tamanho menor. Presente no ecrã de abertura, cabeçalho, textos de partilha, notificações e página do link de convite.
- Prefixo dos códigos: `MB-`.

| Ecrã | Interruptor | Conteúdo |
|---|---|---|
| **C1. Convida e Ganha** | `indicacao` | Código com **Copiar**; botão principal **Partilhar no WhatsApp** (mensagem N1 + deep link); ganho de hoje, da semana, saldo disponível e em verificação ("Confirmamos estes pedidos antes de pagar"); lista de amigos com dias restantes ("Ana · 23 dias"), expirados em secção recolhida; botões **Levantar saldo** e **Destaques**; bloco "Pessoas como tu"; link "Como funciona" (texto 4.13). Estado vazio com convite a partilhar. |
| **C2. Campo de código** | `indicacao` | No registo ("Tens um código de convite?") e no checkout do 1.º pedido. Pré-preenchido pelo link. Mostra "−500 Kz" só depois da confirmação do servidor. Mensagens de erro para cada código de 6.3 e para o limite de descontos por morada. Desaparece após o 1.º pedido pago. |
| **C3. Destaques** | `destaques` | Top 10 do mês; posição própria com "(tu)" e amigos em falta; "Pessoas como tu"; total pago no mês; atalho para C5. |
| **C4. Levantar saldo** | `indicacao` | Saldo, mínimo, opção **Usar em refeições** ou **Receber em dinheiro** (método + número); aviso de 2 parcelas acima de 20.000 Kz; estado Pedido → Aprovado → Pago com referência; botão desactivado abaixo do mínimo ("Faltam X Kz"). |
| **C5. Privacidade na lista** | `destaques` | Pseudónimo actual; interruptores "Mostrar o meu primeiro nome" e "Não mostrar os meus ganhos" (ambos desligados por defeito). |
| **C6. Fim de pedido** | `pessoas_como_tu` | Após confirmar o pedido: resumo + bloco "Pessoas como tu" + botão de partilha do código. |
| **C7. Contador no início** | `contadores_zona` | "X pedidos no teu bairro hoje" no ecrã inicial, só acima do mínimo. |
| **C8. Perfil da cozinha** | `perfil_cozinha` | Foto, nome, história, pratos do dia, média de avaliações (se houver mínimo). "Hoje na Cozinha da Alexandra: …" no ecrã inicial. |
| **C9. Avaliar pedido** | `avaliacoes` | Após entrega (até 3 dias): estrelas, comentário curto, estrelas por prato opcional, opção de usar pseudónimo; fotos só com `avaliacoes_fotos`. |
| **C10. Avaliações** | `avaliacoes` | Lista no perfil da cozinha e em cada prato; só aprovadas/não ocultas. |
| **C11. Endereços** | — | Pin no mapa, referência escrita, tipo **Casa** (residencial) ou **Trabalho** (empresa); sugestão de local existente dentro do raio. |
| **C12. Criar grupo** | `pedidos_grupo` | Local (trabalho), hora de entrega, prazo de adesão, modo de pagamento; partilha por WhatsApp. |
| **C13. Grupo** | `pedidos_grupo` | Participantes (primeiro nome) e estado; "Junta o teu pedido"; contagem regressiva do prazo; cada um escolhe e confirma o seu pedido. |
| **C14. Definições de notificações** | — | Desligar N5 (lembrete do almoço) e N7 (destaques). |

---

## 10. Ecrãs da app do operador e da entrega

| Ecrã | Permissão | Conteúdo |
|---|---|---|
| **O1. Painel do programa** | `indicacoes.ver` | Custo semana/mês; vendas vindas de indicação e peso das comissões (%); clientes novos por indicação; indicadores activos; retenção após 60 dias; top indicadores com nome real (só interno); % anulados na verificação. |
| **O2. Verificação** | `indicacoes.verificar` | Ganhos `em_verificacao` agrupados por indicador, com motivo, pedido, indicado, local (mapa), dispositivo, número de levantamento, marca "pago por outra pessoa". Acções: Confirmar, Anular (motivo obrigatório), Confirmar todos. |
| **O3. Levantamentos** | `indicacoes.aprovar_pagamentos` | Pedidos por estado; destaque para primeiros levantamentos; Aprovar, Rejeitar, Marcar como pago (referência obrigatória); parcelas agrupadas. |
| **O4. Embaixadores** | `plataforma.parametros` | Elegíveis e actuais, contacto, Promover/Remover. |
| **O5. Parâmetros e interruptores** | `plataforma.parametros` | Todos os campos de `parametros` e a lista de `funcionalidades`, com confirmação e auditoria. |
| **O6. Cozinhas** | `cozinhas.gerir` | Criar/editar cozinha, foto, história, estado, consentimento público. |
| **O7. Moderação** | `avaliacoes.moderar` | Fotos pendentes (Aprovar/Rejeitar); comentários recentes (Ocultar). |
| **O8. Equipa** | `equipa.reconhecer` (criar); membros da cozinha (ver) | Métricas da semana por turno; registar reconhecimento; histórico de reconhecimentos. Sem rankings de pessoas. |
| **O9. Relatórios de cozinha** | `relatorios.exportar` | Relatório 7.x por cozinha e período; exportar CSV/PDF. |
| **O10. Grupos do dia** | pedidos | Grupos por hora de entrega e local, com todos os pedidos juntos para preparação e expedição. |
| **E1. Entrega** | papel de entrega | Ao entregar vários pedidos no mesmo local, marcar "pago por outra pessoa" por pedido; registar hora real de entrega. |

---

## 11. Notificações

| Código | Quando | Texto (exemplo) | Interruptor |
|---|---|---|---|
| N1 | Mensagem de partilha (enviada pelo cliente) | Estou a pedir no Manda Bué — Delivery Angola e está bom! Usa o meu código MB-4821 e ganhas 500 Kz de desconto no primeiro pedido. [link] | `indicacao` |
| N2 | Alguém liga-se ao código | O João entrou com o teu código! Ganhas 100 Kz em cada pedido dele durante 60 dias. | `indicacao` |
| N3 | Ganho confirmado | +100 Kz: o pedido do João foi entregue. Saldo desta semana: 1.300 Kz. | `indicacao` |
| N4 | 1.º ganho da semana em verificação por limite | Passaste os 10.000 Kz esta semana. Os próximos ganhos ficam em verificação e são pagos assim que confirmarmos os pedidos. | `indicacao` |
| N5 | Dias úteis 11h, máx. 2/semana | Hoje há [prato do dia]. Partilha o teu código com os colegas antes do almoço. | `indicacao` |
| N6 | 5 dias antes de um indicado expirar | O período da Ana termina em 5 dias. Convida mais amigos para continuares a ganhar. | `indicacao` |
| N7 | Semanal, perto do top | Palanca Azul, estás em 12.º lugar este mês. Faltam 3 amigos para entrares no top 10. | `destaques` |
| N8 | Levantamento pago | Pagámos 5.000 Kz por Multicaixa Express. Referência: XXXX. | `indicacao` |
| N9 | 1 hora após entrega | Como estava o almoço da Cozinha da Alexandra? Avalia em 10 segundos. | `avaliacoes` |
| N10 | Alguém entra no teu grupo | A Marta juntou-se ao teu grupo das 12h30. Já são 6. | `pedidos_grupo` |
| N11 | 15 min antes do fecho do grupo | O grupo das 12h30 fecha em 15 minutos. | `pedidos_grupo` |
| N12 | Reconhecimento do turno (app do operador) | Parabéns, turno da manhã: entregas a horas esta semana! | `reconhecimento_equipa` |

Todos os valores e nomes são preenchidos a partir dos dados e parâmetros.

---

## 12. Plano de fases

| Fase | Conteúdo | Interruptores ligados no fim | Critério para avançar |
|---|---|---|---|
| **P0. Piloto manual** | 10–20 clientes habituais, códigos à mão, registo em folha, pagamentos manuais. Não depende de código novo. | — | 2–4 semanas; valores validados ou ajustados |
| **I1. Fundações** | Todo o modelo de dados (secção 5), migração da Cozinha da Alexandra, locais e endereços, funções e triggers (6), vistas (7), RLS e permissões (8), fila de notificações, jobs. Testes da secção 13. | — (tudo desligado) | Todos os testes de I1 passam |
| **I2. App do cliente** | C1, C2, C4, C6, C7, C8, C11; deep link; N1–N4, N8 | `indicacao`, `pessoas_como_tu`, `contadores_zona`, `perfil_cozinha` (com consentimento) | — (liga só em I4) |
| **I3. App do operador** | O1–O6, O9, E1 | — | Operador consegue verificar e pagar ponta a ponta |
| **I4. Lançamento aberto** | Activar para todos; C3, C5; N5–N7; primeiros Embaixadores | `destaques` | 1 mês estável |
| **I5. Avaliações e equipa** | C9, C10 (sem fotos), C14, O7 (comentários), O8; N9, N12 | `avaliacoes`, `reconhecimento_equipa` | Métricas de turno aceites pela equipa |
| **I6. Pedidos de grupo** | C12, C13, O10; N10, N11 | `pedidos_grupo` | Testado com 2–3 escritórios |
| **I7. Fotos nas avaliações** | Envio de fotos, bucket privado, moderação em O7 | `avaliacoes_fotos` | Existe moderador designado |
| **I8. Rede de cozinhas** | Selector de cozinha no cliente, gestão multi-cozinha no operador, relatórios comparativos | `multi_cozinha` | Primeira cozinha parceira assinada |

A revisão de parâmetros (custo por cliente conquistado, retenção, % anulados) é feita 1–2 meses após I4 e depois trimestralmente, sempre no painel, sem alterar código.

---

## 13. Testes de aceitação (I1)

**Ligação**
1. Código inexistente → `codigo_inexistente`.
2. Próprio código → `proprio_codigo`.
3. Segundo código para o mesmo cliente → `ja_ligado`.
4. Cliente com pedido pago tenta ligar-se → `cliente_nao_novo`.

**Desconto**
5. Indicado novo, local residencial livre → desconto de 500 Kz aplicado pelo servidor, mesmo que a app envie outro valor.
6. 4.º desconto no mesmo local residencial → 0 Kz.
7. Local empresa com 10 indicados → todos com desconto.
8. 1.º pedido cancelado → desconto disponível no pedido seguinte.

**Ganho**
9. Pedido pago dentro dos 60 dias → ganho `confirmado`, N3 na fila.
10. Pedido pago no dia 61 → sem ganho.
11. `expira_em` definido no 1.º pedido pago, não na ligação.
12. Mesmo pedido a mudar de estado duas vezes → um só ganho.
13. Mesmo dispositivo → `anulado` / `mesmo_dispositivo`.
14. Colegas de casa (mesmo local residencial, tudo diferente), 1.º a 3.º indicados → `confirmado`.
15. 4.º indicado no mesmo local residencial → `em_verificacao` / `limite_local`.
16. Mesmo número de levantamento → `em_verificacao` / `numero_pagamento_partilhado`.
17. Colegas de escritório (local empresa) → `confirmado`, sem limite.
18. Soma semanal ≥ 10.000 Kz → `em_verificacao` / `limite_semanal`; N4 só uma vez por semana.
19. Embaixador acima de 10.000 Kz → `confirmado`.
20. Estorno de pedido com ganho `confirmado` → `anulado`; com ganho `pago` → mantém-se.
21. Interruptor `indicacao` desligado → nenhum desconto, nenhum ganho.

**Pagamentos**
22. Levantamento abaixo do mínimo → recusado.
23. Levantamento acima do saldo → recusado.
24. Levantamento de 25.000 Kz → 2 parcelas com o mesmo `grupo_id`.
25. Marcar pago sem referência → recusado; com referência → ganhos mais antigos passam a `pago`.

**Destaques e prova social**
26. Cliente com `sair_da_lista` → não aparece em `destaques_mes()`.
27. Menos de 20 participantes → valores em intervalos.
28. `destaques_mes()` nunca devolve ids nem telefones.
29. `pessoas_como_tu()` com menos de 2 exemplos → vazio.
30. `contador_zona()` abaixo de 10 → `null`.

**RLS**
31. Cliente A não lê ganhos, pagamentos, ligações nem endereços do cliente B.
32. Cliente não consegue escrever `desconto_indicacao`, `credito_usado` nem ganhos.

---

## 14. Métricas

| Métrica | Fórmula | Referência inicial |
|---|---|---|
| Custo por cliente conquistado | (ganhos pagos + descontos) ÷ indicados com ≥1 pedido pago | ~4.500 Kz |
| Peso das comissões | ganhos ÷ vendas de indicados | ~5% |
| Retenção após o período | indicados com pedido 30 dias após `expira_em` ÷ indicados expirados | a medir |
| Indicadores activos | indicadores com ≥1 ganho na semana | a medir |
| % anulados na verificação | anulados ÷ entraram em verificação | a vigiar se sobe |
| Tempo até ao 1.º pagamento | `pago_em` − `criado_em` no 1.º levantamento | mesmo dia |
| Entregas a horas | por turno, semanal | a medir |
| Média de avaliação | por cozinha e prato | a medir |
| Pedidos por grupo | participantes médios por grupo | a medir |

**Leitura:** indicados ficam após 60 dias → pode encurtar-se o período; saem antes → problema de serviço; poucos usam o código → aumentar o desconto; % anulados a subir → rever sinais anti-fraude.

---

## 15. Instrução para o Claude Code

Acrescentar ao `PROMPT_INICIAL.md`:

> Implementa o **Programa de Crescimento** conforme `PROJECTO_CRESCIMENTO_MANDA_BUE.md`, que substitui o programa de referência/incentivos do protótipo web e as adendas anteriores.
>
> 1. Começa pela fase **I1**: confirma os nomes reais das tabelas e campos existentes no `MODELO_DE_DADOS.md` e ajusta o SQL; cria a migração completa (secção 5), incluindo a criação da Cozinha da Alexandra e o preenchimento de `cozinha_id` nas linhas existentes; implementa as funções, triggers, vistas e RLS (secções 6–8); escreve os testes da secção 13 e garante que passam.
> 2. Todos os interruptores ficam **desligados** no fim de I1.
> 3. Segue as fases I2 a I8 pela ordem da secção 12, uma de cada vez, e pára no fim de cada fase para revisão.
> 4. Regras invioláveis: o servidor calcula todos os valores; nenhum valor fixo no código (tudo de `parametros`); nenhum dado fictício na interface; ids e telefones nunca expostos em listas públicas; toda a acção de verificação, pagamento e alteração de parâmetros é auditada.
> 5. Usa a marca **Manda Bué — Delivery Angola** e o prefixo `MB-` nos códigos.

---

## 16. Decisões em aberto

1. **Consentimento da Alexandra** para o perfil público (nome, foto, história). Até lá, `consentimento_publico = false`.
2. **Acordo sobre a marca** entre a plataforma e a Cozinha da Alexandra (quem regista o quê e o que acontece se a parceria terminar).
3. **Moderador de fotos** para activar I7.
4. **Regra da taxa de entrega em grupo** (`dividir` ou `empresa`): valor inicial `dividir`.
5. **Integração automática** com Multicaixa Express / Unitel Money: fora do âmbito; avaliar após I5.
6. **Registo de marca** "Manda Bué" no INAPI.
