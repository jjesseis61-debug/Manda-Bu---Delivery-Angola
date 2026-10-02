# Projecto Completo: Programa de Crescimento
## Manda Bué — Delivery Angola

Versão 1.1 · Setembro de 2026

> **Alterações da versão 1.1** (fase I1 implementada): nomes reais do `MODELO_DE_DADOS.md` (`pontos_entrega`, `zonas`,
> `pratos_base`, `caixa`, `estoque_diario`/`estoque_longo_prazo`); tabela `pedidos` com estado alterado só no servidor
> e venda gerada na entrega; campos de sincronização em todas as tabelas; valores garantidos na ligação; programa de
> indicação antigo substituído. Secções 3, 4, 5–8, 12, 13, 15 e 16 actualizadas.

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
| Ponto de entrega | Local físico de entrega (coordenadas + referência), partilhável por vários clientes (`pontos_entrega`). Não confundir com `locais`, os postos de venda |
| Valor garantido | Ganho por pedido e desconto em vigor no momento da ligação, que valem para toda a ligação |
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
- Tabelas **escritas só pelo servidor** (nunca pela fila de saída do dispositivo, nem da app do operador): ganhos, pagamentos, ligações, códigos, parâmetros, interruptores, fila de notificações, contadores. O **estado dos pedidos** também só muda no servidor (funções `mudar_estado_pedido` e `cancelar_pedido`).
- Todas as tabelas têm os 6 campos de sincronização do `MODELO_DE_DADOS.md` e uma estratégia de conflito definida.

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

### 4.2 Pontos de entrega e endereços
- Cada endereço de cliente aponta para um **ponto de entrega** (`pontos_entrega`): coordenadas (pin no mapa), zona de entrega (`zonas`), referência escrita e **tipo** (`residencial` ou `empresa`).
- Dois endereços são o **mesmo ponto** se estiverem a menos de `[raio_mesmo_local_m = 25]` metros e tiverem o mesmo tipo. A app sugere um ponto existente quando o pin cai dentro desse raio, para evitar duplicados (sem mostrar a referência escrita de pontos residenciais de outros clientes).
- Clientes do tipo Empresa (com NIF) usam pontos do tipo `empresa`. Um cliente Particular pode marcar um endereço como "trabalho" (`empresa`).

### 4.3 Convida e Ganha

**Código**
- Formato `MB-` + 4 dígitos (passa a 5 quando esgotar). Gerado no registo, único, permanente.
- Não deriva do nome nem do telefone.

**Ligação**
- O indicado insere o código no registo ou no checkout do primeiro pedido (ou chega pelo link de convite, que o pré-preenche).
- Única e permanente. Não se troca de indicador.
- Bloqueios: próprio código; cliente que já tem um pedido `entregue_pago` ou compras registadas em `vendas` (sistema anterior); código inexistente.
- **Valores garantidos:** no momento da ligação, o `ganho_por_pedido`, o `desconto_indicado` e a `duracao_dias` em vigor ficam guardados na ligação (`ganho_por_pedido_garantido`, `desconto_garantido`, `duracao_dias_garantida`). O desconto, todos os ganhos e o cálculo de `expira_em` dessa ligação usam estes valores. Mudar os parâmetros só afecta novas ligações.

**Ganho do indicado**
- `[desconto_indicado = 500 Kz]` no primeiro pedido.
- O desconto nunca passa o valor do pedido (subtotal + taxa de entrega): o valor final nunca fica negativo. É de uso único: num pedido mais pequeno do que o desconto, a parte que sobra não passa para o pedido seguinte.
- Validado no servidor. Se o primeiro pedido for cancelado, o desconto fica disponível para o seguinte.
- Limite por ponto residencial: no máximo `[max_descontos_por_local = 3]` descontos de primeiro pedido. A partir daí, a app informa "Este convite já foi usado o número máximo de vezes nesta morada" e o pedido segue sem desconto. Pontos `empresa` não têm este limite.
- Só um pedido em curso de cada vez pode levar o desconto.

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
- **Saldo disponível** = ganhos `confirmado` e `pago` − pagamentos `pedido`, `aprovado` e `pago` (equivale a "ganhos confirmados − pagamentos em curso", mas é exacto mesmo quando o crédito usado não coincide com ganhos inteiros).
- Se um pedido pago com crédito for cancelado ou estornado, o crédito volta ao saldo.
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
- Cada pedido do grupo conta normalmente para o programa de indicação. Pedidos de grupo acontecem em pontos de entrega `empresa`, por isso não activam o limite por ponto residencial.
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
| `pedidos.gerir` | Mudar o estado dos pedidos da app (confirmar, preparar, cancelar, estornar) |
| `entregas.registar` | Marcar pedidos em entrega e entregues e pagos (indicando a caixa); marcar "pago por outra pessoa" |

Todas estas permissões estão no catálogo `permissoes` (usado pela app do operador para montar o organograma). A atribuição continua em `direcoes.permissoes` e `funcionarios.permissoes_extra`.

### 4.13 Texto das regras para o cliente

> Ganhas 100 Kz por cada pedido dos amigos que convidares, durante 60 dias a contar do primeiro pedido deles. Não há limite de ganhos.
> O teu amigo ganha 500 Kz de desconto no primeiro pedido.
> Levantas o saldo a partir de 2.000 Kz ou usas em refeições. Acima de 10.000 Kz por semana, confirmamos os pedidos antes de pagar.
> Ganhos de contas falsas ou pedidos não pagos são anulados.
> Os teus ganhos podem aparecer na lista de destaques com um nome fictício. Podes sair da lista quando quiseres.

Os valores são preenchidos a partir de `parametros` (e, para cada amigo, a partir dos valores garantidos na ligação).

### 4.14 Pedidos da app e vendas
- Os pedidos da app do cliente ficam em `pedidos` (o `MODELO_DE_DADOS.md` não tinha pedidos da app, e `vendas` é append-only).
- Ciclo: `pendente → confirmado → em_preparacao → em_entrega → entregue_pago`; `cancelado` antes da entrega; `entregue_pago → estornado`.
- O estado **só muda no servidor**. O cliente cancela enquanto o pedido está `pendente`; o operador muda o estado com `pedidos.gerir`; o entregador marca a entrega com `entregas.registar`.
- **Regra 8:** marcar `entregue_pago` exige a **caixa** (posto) onde o dinheiro entrou: uma caixa aberta da mesma cozinha. A venda regista esse local (`vendas.local` = posto da caixa, `vendas.caixa_id`).
- **Regra 7:** as parcelas do pedido mais o crédito de indicação têm de somar o **valor final** (subtotal + taxa − desconto). O entregador pode registar as parcelas efectivamente recebidas ao marcar a entrega.
- Quando o pedido chega a `entregue_pago`, o servidor **gera uma venda por item** (origem `App cliente`, `linha_pedido` = 1, 2, …): a taxa de entrega fica só na primeira venda; o desconto e cada parcela são repartidos proporcionalmente, com o arredondamento na última venda; a soma das vendas é o valor final e as parcelas de cada venda somam o total dessa venda.
- **Regra 3:** um estorno gera, para cada venda, uma venda de compensação (origem `App cliente (estorno)`) com valores negativos, `qtd = 0` e `movimenta_stock = false`: **não repõe stock**.
- **Consumo de stock (regra 3):** o servidor desconta o stock **só das vendas que gera a partir de pedidos** (`vendas.stock_consumido_por = 'servidor'`); as vendas da app do operador (`'dispositivo'`, por defeito) continuam a ser descontadas pela própria app. Um dispositivo nunca consegue marcar `'servidor'`.
  - Consumo = receita do prato (`pratos_base.componentes`) − componentes excluídos, com os ajustados, × `qtd`, convertido para a unidade base (g, ml, unidade); movimento `Consumo` em `estoque_longo_prazo` na cozinha da venda, com `venda_id` (único com `produto_id`: nunca desconta duas vezes).
  - Só produtos `Longo Prazo`; os `Diário` ficam para a reconciliação do dia. Itens sem prato não descontam.
  - Unidade desconhecida, produto inexistente ou sem tipo de stock: a venda passa e fica um aviso `stock_consumo_pendente` na auditoria.
  - O `prato_base_id` de cada item é validado quando o pedido é criado (`prato_invalido`).
  - Formatos no item: `componentes_excluidos: [produto_id, …]`; `componentes_ajustados: [{produto_id, quantidade, unidade}, …]` (substitui a quantidade da receita; acrescenta se o produto não estiver na receita).
  - **Guarda (regra 10):** um consumo em `estoque_longo_prazo` vindo de um dispositivo (`dispositivo_id <> 'servidor'` ou sessão `authenticated`/`anon`) para uma venda `App cliente` é descartado e registado na auditoria (`consumo_dispositivo_bloqueado`, `bloqueado = true`). Descarta-se em vez de dar erro para o registo na auditoria não ser desfeito e a fila de saída não repetir a tentativa sem fim.
- **Requisito da app do operador (Expo):**
  1. Aceitar a coluna `estoque_longo_prazo.venda_id` na sincronização (vem preenchida nos consumos do servidor) e preenchê-la nos consumos que a app regista para as suas próprias vendas.
  2. **Nunca** correr o consumo automático para vendas com origem `App cliente` (nem `App cliente (estorno)`): essas vendas chegam pela sincronização com `stock_consumido_por = 'servidor'` e já foram descontadas no servidor. A app só desconta vendas com `stock_consumido_por = 'dispositivo'`.
  3. Não enviar `stock_consumido_por = 'servidor'` (o servidor força `dispositivo` nas escritas vindas de dispositivos).
- Os ganhos de indicação são calculados em `pedidos`.

### 4.15 Programa de indicação antigo
As tabelas `indicacoes`, `recompensas_indicacao` e `config_indicacao` do protótipo são **substituídas** pelo Programa de Crescimento e não são criadas. A base de dados de desenvolvimento não tinha dados a arquivar.

---

## 5. Modelo de dados

O SQL definitivo está nas migrações em `supabase/migrations/` (aplicadas por esta ordem):

| Migração | Conteúdo |
|---|---|
| `20260930165537_modelo_base.sql` | Tabelas do `MODELO_DE_DADOS.md` (incluindo `pedidos`), índices recomendados, RLS activo por defeito |
| `20260930173725_crescimento_i1.sql` | Modelo do programa (5.1–5.9), Cozinha da Alexandra, funções, triggers, vistas, RLS |
| `20260930173922_crescimento_i1_ajustes.sql` | Nomes finais (`pontos_entrega`), estado do pedido só no servidor, venda gerada, campos de sincronização em todas as tabelas, valores garantidos na ligação |
| `20260930183237_crescimento_i1_decisoes.sql` | Duração garantida, vendas por item (regra 7), caixa na entrega (regra 8), estorno sem stock (regra 3), catálogo de permissões |
| `20261001040216_crescimento_i1_endurecimento.sql` | `search_path` fixo, funções de trigger não expostas, índices nas chaves estrangeiras |
| `20261001041532_crescimento_i1_consumo_stock.sql` | Consumo de stock das vendas geradas de pedidos (regra 3), validação dos itens do pedido |
| `20261001043509_crescimento_i1_privilegios.sql` | Guarda do consumo sem funções expostas; funções SECURITY DEFINER internas fora do alcance das apps |
| `20261001052041_crescimento_i2_app_cliente.sql` | I2: registo do cliente, cardápio com preços no servidor, amigos convidados, tokens de push, textos das notificações |
| `20261001052738_crescimento_i2_desconto_limite.sql` | Desconto de indicação limitado ao valor do pedido |

**Nomes reais.** Os nomes assumidos na versão 1.0 foram substituídos pelos do `MODELO_DE_DADOS.md`:

| Versão 1.0 | Nome real |
|---|---|
| `pratos` | `pratos_base` |
| `caixas` | `caixa` |
| `movimentos_stock` | `estoque_diario`, `estoque_longo_prazo` (e `distribuicoes`) |
| `zonas_entrega` | `zonas` |
| `locais` (pontos de entrega) | **`pontos_entrega`** — `locais` já existe e são os postos de venda |
| `local_id` | **`ponto_entrega_id`** |
| `credito_usado` | `credito_indicacao_usado` |
| `pagamentos_indicacao.grupo_id` | `lote_id` (parcelas do mesmo levantamento) |
| `actualizado_em` / `actualizado_por` | `atualizado_em` / `atualizado_por` |

**Campos de sincronização.** Todas as tabelas (base e novas, incluindo `parametros` e `funcionalidades`) têm
`id` (UUID), `dispositivo_id`, `criado_em`, `atualizado_em`, `sincronizado_em`, `deletado_em`. O servidor preenche
`sincronizado_em` em cada escrita; as linhas criadas pelo servidor têm `dispositivo_id = 'servidor'`.
A estratégia de conflito de cada tabela está no `MODELO_DE_DADOS.md` e registada na própria tabela (`comment on table`).

Valores monetários em **kwanzas inteiros** (`int`). Datas em `timestamptz`. Fuso para dias, semanas e meses: `Africa/Luanda`.

### 5.1 Configuração
- **`parametros`** — registo único (`unico = true`, chave `id` UUID). Todos os valores do programa com os valores
  iniciais da secção 4, mais `tamanho_intervalo = 10000` (intervalos da lista de destaques). Só o servidor escreve:
  alteração por `alterar_parametros(jsonb)`, com `plataforma.parametros`, auditada.
- **`funcionalidades`** — `chave` única, `activa` (todas `false` no fim de I1). Alteração por
  `alterar_funcionalidade(chave, activa)`, com `plataforma.parametros`, auditada.

### 5.2 Cozinhas
- **`cozinhas`** — `nome`, `responsavel`, `foto_url`, `historia`, `estado` (activa/pausada/inactiva),
  `consentimento_publico` (false até decisão 16.1). A migração cria a **Cozinha da Alexandra**.
- `cozinha_id` obrigatório (por defeito `cozinha_padrao()`, a cozinha activa mais antiga) em `pratos_base`, `turnos`,
  `caixa`, `estoque_diario`, `estoque_longo_prazo`, `distribuicoes`, `vendas`, `pre_encomendas`, `pedidos_especiais`
  e `pedidos`. As linhas existentes são preenchidas com a Cozinha da Alexandra.
- `turnos.periodo` (manha/tarde/noite): turno de cozinha para o reconhecimento de equipa.

### 5.3 Pontos de entrega e endereços
- **`pontos_entrega`** — `tipo` (residencial/empresa), `lat`, `lng`, `zona_id` → `zonas`, `referencia`,
  `criado_por_cliente`.
- **`enderecos_cliente`** — `cliente_id`, `ponto_entrega_id`, `nome` (Casa/Trabalho), `principal`.
  Clientes Empresa só usam pontos do tipo `empresa`.

### 5.4 Pedidos da app do cliente
**`pedidos`** (tabela do esquema base, porque `vendas` é append-only e não tem estado):
`cliente_id`, `zona_id`, `estado`, `itens` (`[{prato_base_id, nome, qtd, preco_unitario}]`), `subtotal`,
`taxa_entrega`, `parcelas`, `observacoes`, `motivo_cancelamento`, `hora_prometida`, `entregue_em`; e, do programa,
`cozinha_id`, `ponto_entrega_id`, `desconto_indicacao`, `credito_indicacao_usado`, `grupo_id`, `pagador_distinto`,
`caixa_id` (caixa onde o dinheiro entrou, obrigatória em `entregue_pago`).

Ciclo de estados: `pendente → confirmado → em_preparacao → em_entrega → entregue_pago`; `cancelado` a partir de
qualquer estado antes da entrega; `entregue_pago → estornado`. Só avança; pode saltar etapas.

`vendas` ganha `pedido_id`, `linha_pedido`, `caixa_id` e `movimenta_stock` (ver 6.9).

### 5.5 Convida e Ganha
- **`codigos_indicacao`** — `cliente_id` (único), `codigo` (`MB-` + 4 dígitos), `nivel` (normal/embaixador),
  `ultima_partilha_em`.
- **`ligacoes_indicacao`** — `indicado_id` (único), `indicador_id`, `ligado_em`, `primeiro_pedido_id`, `expira_em`
  (vazio até ao 1.º pedido entregue e pago), `desconto_usado`, **`ganho_por_pedido_garantido`**,
  **`desconto_garantido`**, **`duracao_dias_garantida`** (copiados de `parametros` no momento da ligação).
- **`ganhos_indicacao`** — `pedido_id` (único), `indicador_id`, `indicado_id`, `valor`, `estado`, `motivo`,
  `nota_revisao`, `revisto_por`, `revisto_em`, `pagamento_id`, `confirmado_em`.
- **`pagamentos_indicacao`** — `indicador_id`, `valor`, `tipo` (credito/levantamento), `metodo`, `numero_destino`,
  `pedido_id`, `lote_id`, `parcela`, `total_parcelas`, `estado` (pedido/aprovado/pago/rejeitado), `referencia`,
  `motivo_rejeicao`, `aprovado_por`, `pago_em`.
- **`perfil_destaques`** — `cliente_id`, `pseudonimo`, `mostrar_nome_real`, `sair_da_lista`.
- **`preferencias_notificacao`** — `cliente_id`, `lembrete_almoco` (N5), `destaques` (N7).

### 5.6 Avaliações
`avaliacoes` (uma por pedido; `cozinha_id` vem do pedido), `avaliacoes_pratos` (estrelas por prato),
`fotos_avaliacao` (máx. 2, `pendente` até moderação), `palavras_filtradas` (filtro de comentários, começa vazio).

### 5.7 Reconhecimento de equipa
`reconhecimentos_turno` — `cozinha_id`, `semana` (segunda-feira), `periodo`, `tipo`, `nota`, `criado_por`.
Reconhece o turno da cozinha, nunca uma pessoa (uma linha de `turnos` é o turno de um funcionário).

### 5.8 Pedidos de grupo
`pedidos_grupo` — `organizador_id`, `empresa_id`, `ponto_entrega_id`, `cozinha_id`, `hora_entrega`, `prazo_adesao`,
`modo_pagamento`, `codigo_convite` (`G-` + 6 caracteres, gerado no servidor), `estado`.

### 5.9 Fila de notificações e contadores
`notificacoes_fila` (`cliente_id`, `codigo` N1–N15, `dados`, `enviada_em`) e `contadores_zona` (cache horária de
pedidos pagos por zona e dia). Não sincronizam para o telemóvel.

---

## 6. Funções e triggers

### 6.1 Utilitários
`distancia_m`, `mesmo_ponto_entrega(a, b)` (mesmo tipo e a ≤ `raio_mesmo_local_m`), `funcionalidade_activa(chave)`,
`inicio_dia_luanda()`, `inicio_semana_luanda()`, `inicio_mes_luanda()`, `hoje_luanda()`, `normalizar_telefone`.

Identidade: `clientes.auth_user_id` e `funcionarios.auth_user_id` ligam ao utilizador do Supabase Auth.
`cliente_actual()`, `funcionario_actual()`, `tem_permissao(p)` (administrador principal tem tudo;
`permissoes_extra` prevalece sobre as permissões da direcção).

Auditoria: `registar_auditoria(acao, ref_tipo, ref_id, detalhe)` escreve em `auditoria`; sem funcionário,
`funcionario_nome = 'sistema'`. A tabela recusa UPDATE, DELETE e TRUNCATE (só o servidor pode marcar `sincronizado_em`).

### 6.2 Registo de cliente
Trigger `after insert on clientes`: gera o código `MB-dddd` (passa a 5 dígitos quando se esgotar), o pseudónimo
(palavra angolana + qualidade ou número, sem dados do cliente) e as preferências de notificação.

### 6.3 `ligar_indicacao(p_codigo)`
Devolve `programa_inactivo`, `sem_sessao`, `codigo_inexistente`, `proprio_codigo`, `ja_ligado`, `cliente_nao_novo`
ou `ok`. "Cliente não novo" = tem um pedido `entregue_pago` **ou compras em `vendas`** (sistema anterior).
Ao ligar, copia `ganho_por_pedido`, `desconto_indicado` e `duracao_dias` para a ligação (valores garantidos), enfileira N2 e audita.

### 6.4 Desconto no pedido (`before insert on pedidos`)
O servidor ignora o valor enviado pela app e recalcula com `avaliar_desconto_indicacao`:
- 0 se o programa estiver desligado, sem ligação, desconto já usado, cliente não novo, ou já houver um pedido
  em curso com desconto;
- 0 se o ponto for residencial e já tiver `max_descontos_por_local` descontos pagos (mesmo ponto = até 25 m);
- senão, **`desconto_garantido` da ligação** (não o parâmetro actual).

`meu_desconto_indicacao(p_ponto)` devolve `(valor, motivo)` para o ecrã C2 mostrar "−500 Kz" ou a mensagem de limite.

### 6.5 Ganho do indicador (`after update of estado on pedidos`)
Como na versão 1.0 (período a partir do 1.º pedido pago, sinais anti-fraude, limite por local, limite semanal,
embaixadores, estorno, N3/N4), com duas diferenças:
- o valor do ganho é **`ganho_por_pedido_garantido`** e o período é **`duracao_dias_garantida`** da ligação: mudar os parâmetros só afecta novas ligações;
- o sinal "mesmo dispositivo" usa o campo comum `dispositivo_id` dos pedidos e ignora linhas criadas pelo servidor.

### 6.6 Revisão de ganhos
`rever_ganho(ganho, 'confirmar'|'anular', motivo)`, com `indicacoes.verificar`; anular exige motivo escrito
(guardado em `nota_revisao` e na auditoria). `definir_nivel_indicador(cliente, nivel)` com `plataforma.parametros`.

### 6.7 Pagamentos
- **Saldo** = ganhos `confirmado` + `pago` − pagamentos `pedido` + `aprovado` + `pago` (igual a "confirmado − em curso",
  mas exacto mesmo quando o crédito usado não é múltiplo de um ganho).
- `pedir_levantamento(valor, metodo, numero)`: mínimo, saldo, método e número válidos; acima de `limite_parcelamento`
  cria 2 parcelas com o mesmo `lote_id`.
- `usar_credito(pedido, valor)`: pagamento `credito` já `pago`; soma a `pedidos.credito_indicacao_usado`.
  Se o pedido for cancelado ou estornado, o crédito volta ao saldo.
- `aprovar_levantamento`, `rejeitar_levantamento` (motivo obrigatório), `marcar_pago` (referência obrigatória):
  com `indicacoes.aprovar_pagamentos`. Os ganhos confirmados mais antigos cobertos pelo total pago passam a `pago`. N8.

### 6.8 Jobs agendados
`job_contadores_zona` (de hora a hora), `job_n6_expiracao` (08h), `job_n5_lembrete` (dias úteis 11h, máx. 2/semana,
só quem partilhou e não desligou), `job_n7_destaques` (segundas 08h). Respeitam os interruptores.
`agendar_jobs()` agenda-os com `pg_cron` quando a extensão está activa (horas em UTC; Luanda = UTC+1).

### 6.9 Estado do pedido e venda gerada
- O estado **só muda no servidor**: `mudar_estado_pedido(pedido, estado, motivo, caixa, parcelas)` (`pedidos.gerir`;
  o entregador, com `entregas.registar`, só marca `em_entrega` e `entregue_pago`) e `cancelar_pedido(pedido, motivo)`
  (o cliente, enquanto `pendente`). Nenhuma escrita directa de `estado` é aceite, nem da fila de saída do operador.
- `marcar_pagador_distinto(pedido, valor)` com `entregas.registar`.
- **Entregue e pago** exige `caixa` (aberta, da mesma cozinha — regra 8) e parcelas + crédito = valor final (regra 7).
  O servidor grava `entregue_em` e **gera uma venda por item**:

  | Campo da venda | Valor |
  |---|---|
  | `origem`, `pedido_id`, `linha_pedido` | `App cliente`, o pedido, n.º do item |
  | `produto`, `qtd`, `prato_base_id` | do item |
  | `valor_antes_desconto` | parte do subtotal do item (qtd × preço, repartido para somar o subtotal) + taxa só na linha 1 |
  | `desconto_aplicado` | desconto de indicação proporcional; arredondamento na última linha |
  | `valor_total` | `valor_antes_desconto − desconto_aplicado`; soma de todas as linhas = valor final |
  | `parcelas` | cada parcela do pedido (e "Crédito indicação") repartida proporcionalmente; somam o total da linha; arredondamento na última linha |
  | `local`, `caixa_id` | posto e caixa onde o dinheiro entrou |
  | `zona_nome`, `tipo_entrega`, `entrega`, `movimenta_stock` | zona do ponto de entrega, `true`, `true` |

- **Estorno:** uma venda `App cliente (estorno)` por linha, com valores e parcelas negativos, `qtd = 0` e
  `movimenta_stock = false` — não repõe stock (regra 3). Qualquer cálculo de consumo a partir de vendas usa só
  `movimenta_stock = true`.

---

## 7. Vistas e funções de leitura

- **`saldo_indicacao`** (vista, respeita RLS): `saldo_disponivel`, `em_verificacao`, `ganho_hoje`, `ganho_semana`,
  `total_recebido` por indicador.
- **`destaques_mes()`**: posição, nome exibido, amigos, valor (ou `valor_min`/`valor_max` abaixo de
  `limiar_intervalos`), `sou_eu`. Exclui `sair_da_lista`. Nunca devolve ids nem telefones. Vazia com `destaques` desligado.
- **`minha_posicao()`**: posição, amigos, `amigos_em_falta` para o top, `no_top`.
- **`pessoas_como_tu()`**: 2–3 exemplos reais entre `pessoas_como_tu_min` e `_max` amigos; vazio se houver menos de 2.
- **`total_pago_mes()`**, **`contador_zona(zona)`** (null abaixo de `contador_minimo`).
- **`media_avaliacoes_cozinha`**, **`media_avaliacoes_prato`** (vistas; só com `avaliacoes_minimo`, sem ocultas).
- **`metricas_turno(cozinha, semana)`**: por período — quebras registadas em `distribuicoes`, entregas a horas,
  diferença de caixa (`caixa.fechamento->>'diferenca'`). Com `equipa.reconhecer` ou para membros da cozinha.
- **`relatorio_cozinha(cozinha, início, fim)`**: pedidos por dia, clientes novos, vindos de indicação, retenção
  30/60/90, média de avaliação, prato mais pedido. Com `relatorios.exportar`.
- Apoio às apps: `pontos_entrega_proximos(lat, lng, tipo)` (não devolve a referência de pontos residenciais),
  `grupo_por_codigo(codigo)`, `avaliacao_permitida(pedido)`, `registar_partilha()`.

---

## 8. Segurança (RLS) e permissões

RLS está activo em **todas** as tabelas. As tabelas base sem políticas só são acessíveis ao servidor até as
políticas das apps do operador serem definidas.

| Tabela | Cliente | Operador |
|---|---|---|
| `parametros`, `funcionalidades` | Ler | Ler; alterar só por `alterar_parametros` / `alterar_funcionalidade` (`plataforma.parametros`) |
| `cozinhas` | Ler activas com `consentimento_publico` | Ler; escrever com `cozinhas.gerir` |
| `pontos_entrega`, `enderecos_cliente` | Ler/escrever os seus | Ler |
| `pedidos` | Criar (estado `pendente`); ler os seus; cancelar só por `cancelar_pedido` | Ler; estado só por `mudar_estado_pedido`; `hora_prometida`/`observacoes` com `pedidos.gerir` |
| `codigos_indicacao` | Ler o seu | Ler com `indicacoes.ver`; nível por `definir_nivel_indicador` |
| `ligacoes_indicacao` | Ler onde é indicador ou indicado | Ler com `indicacoes.ver` |
| `ganhos_indicacao` | Ler onde é indicador | Ler com `indicacoes.ver`/`verificar`; rever por `rever_ganho` |
| `pagamentos_indicacao` | Ler os seus; criar só por funções | Ler; aprovar/pagar por funções |
| `perfil_destaques` | Ler o seu; actualizar só `mostrar_nome_real` e `sair_da_lista` | Ler |
| `preferencias_notificacao` | Ler/actualizar as suas | — |
| `avaliacoes` | Criar para pedido próprio entregue dentro do prazo; ler não ocultas | Ocultar por `ocultar_avaliacao` |
| `fotos_avaliacao` | Enviar para avaliação própria (com `avaliacoes_fotos`); ler aprovadas | Moderar por `moderar_foto` |
| `pedidos_grupo` | Criar; ler os seus ou por `grupo_por_codigo` | Ler |
| `reconhecimentos_turno` | — | Criar com `equipa.reconhecer`; membros da cozinha lêem |
| `notificacoes_fila`, `contadores_zona` | — | Só serviço |
| `permissoes` (catálogo) | Ler | Ler (só o servidor escreve) |

**Escrita só pelo servidor.** `parametros`, `funcionalidades`, `codigos_indicacao`, `ligacoes_indicacao`,
`ganhos_indicacao`, `pagamentos_indicacao`, `notificacoes_fila`, `contadores_zona` e `permissoes` recusam qualquer escrita vinda de
uma sessão de dispositivo (trigger `bloquear_escrita_dispositivo`), mesmo que um privilégio seja concedido por engano.
Nunca entram na fila de saída do telemóvel.

**Campos de `pedidos` só do servidor:** `estado`, `desconto_indicacao`, `credito_indicacao_usado`, `entregue_em`,
`pagador_distinto`, `caixa_id`.

As funções de trigger e as auxiliares internas não são chamáveis pelas apps; todas as funções têm `search_path` fixo.

**Tabelas base (app do operador).** Acesso por permissão do organograma; nas tabelas com `cozinha_id` o funcionário
tem também de ser da cozinha (tem um turno lá) ou ter `cozinhas.gerir` (`pode_na_cozinha`). Os clientes não lhes
chegam directamente. Nenhuma tem DELETE (apaga-se com `deletado_em`).

| Tabela | Ler | Escrever |
|---|---|---|
| `vendas` | `vendas.registar` ou `relatorios.exportar` na cozinha; `financas.gerir` | Criar com `vendas.registar` na cozinha, nunca `App cliente` nem com `pedido_id`; append-only |
| `estoque_diario`, `estoque_longo_prazo` | `stock.gerir` na cozinha | Criar com `stock.gerir` na cozinha; append-only |
| `distribuicoes` | `stock.gerir` na cozinha | Criar; depois só estado, recebimento, devolução e quebra |
| `caixa` | `vendas.registar`/`entregas.registar`/`pedidos.gerir` | Abrir e fechar com `vendas.registar` ou `entregas.registar` na cozinha |
| `pre_encomendas`, `pedidos_especiais` | `vendas.registar` na cozinha | Idem |
| `clientes` | `clientes.gerir`, `vendas.registar`, `financas.gerir` | Dados com `clientes.gerir`; `limite_credito`/`desconto` só `financas.gerir`; `auth_user_id` só o servidor |
| `pagamentos_credito` | `vendas.registar`, `financas.gerir` | Pagamentos com `vendas.registar`; notas de crédito só `financas.gerir`; append-only |
| `custos` | `financas.gerir` | `financas.gerir` |
| `produtos`, `locais` | Toda a equipa | `stock.gerir` / `cozinhas.gerir` |
| `turnos` | Os seus e os da sua cozinha | `equipa.gerir` na cozinha |
| `refeicoes_funcionarios` | As suas; `equipa.gerir`, `vendas.registar` | Criar com `equipa.gerir` ou `vendas.registar`; append-only |
| `direcoes`, `funcionarios` | Direcções: toda a equipa; funcionários: a sua ficha, `equipa.gerir`, administrador | Só o administrador principal |
| `auditoria` | `auditoria.ver` | Cada funcionário regista as suas acções; imutável |

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
| N13 | Pagamento do pacote confirmado | O teu Almoço do Mês está activo: 22 refeições até 31/10. Bom almoço! | `pacotes` |
| N14 | Pacote a acabar (3 refeições ou 3 dias) | Restam 3 refeições no teu Almoço do Mês. Renova para continuares a almoçar sem pagar na entrega. | `pacotes` |
| N15 | Nova adesão por confirmar (app do operador) | Ana aderiu ao Almoço do Mês (Multicaixa Express, 50.000 Kz). Confirma o pagamento. | `pacotes` |

Todos os valores e nomes são preenchidos a partir dos dados e parâmetros.

---

## 12. Plano de fases

| Fase | Conteúdo | Interruptores ligados no fim | Critério para avançar |
|---|---|---|---|
| **P0. Piloto manual** | 10–20 clientes habituais, códigos à mão, registo em folha, pagamentos manuais. Não depende de código novo. | — | 2–4 semanas; valores validados ou ajustados |
| **I1. Fundações** | Esquema base com `pedidos`, todo o modelo de dados (secção 5), migração da Cozinha da Alexandra, pontos de entrega e endereços, funções e triggers (6), venda gerada na entrega, vistas (7), RLS e permissões (8), fila de notificações, jobs. Testes da secção 13. | — (tudo desligado) | Todos os testes de I1 passam |
| **I2. App do cliente** | C1, C2, C4, C6, C7, C8, C11; deep link; N1–N4, N8 | `indicacao`, `pessoas_como_tu`, `contadores_zona`, `perfil_cozinha` (com consentimento) | — (liga só em I4) |
| **I3. App do operador** | O1–O6, O9, E1 | — | Operador consegue verificar e pagar ponta a ponta |
| **I4. Lançamento aberto** | Activar para todos; C3, C5, C14; N5–N7; primeiros Embaixadores | `destaques` | 1 mês estável |
| **I5. Avaliações e equipa** | C9, C10 (sem fotos), O7 (comentários), O8; N9, N12 | `avaliacoes`, `reconhecimento_equipa` | Métricas de turno aceites pela equipa |
| **I6. Pedidos de grupo** | C12, C13, O10; N10, N11 | `pedidos_grupo` | Testado com 2–3 escritórios |
| **I7. Fotos nas avaliações** | Envio de fotos, bucket privado, moderação em O7 | `avaliacoes_fotos` | Existe moderador designado |
| **I8. Rede de cozinhas** | Selector de cozinha no cliente, gestão multi-cozinha no operador, relatórios comparativos | `multi_cozinha` | Primeira cozinha parceira assinada |
| **I9. Pratos montáveis** | Grupos de opções por prato (base, acompanhamentos, extras) com preço extra; ecrã "Montar o prato"; gestão das opções no O6 | `pratos_montaveis` | Opções carregadas para os pratos montáveis |
| **I10. Como chegar** | Morada, horário e ponto de cada cozinha; botão que abre a navegação do Google Maps | `como_chegar` | Localização gravada e autorizada pela responsável |
| **I11. Acompanhamento da entrega** | Estafeta partilha a posição enquanto tem pedidos a caminho; o cliente vê-o no mapa com tempo estimado | `acompanhamento_entrega` | Testado com estafetas reais; chave do Google Maps no build |
| **I12. Pacotes do mês** | "Almoço do Mês" pré-pago (ex.: 20 + 2 de oferta, entrega grátis, 30 dias, pausa até 5 dias, reembolso das não usadas); pagamento por Multicaixa Express, Unitel Money ou na loja confirmado pela equipa; prova social por local e zona | `pacotes` | Pacote criado no catálogo; instruções de pagamento no build; equipa com `pacotes.gerir` |

**Feito (migração `20261001184650_crescimento_rls_tabelas_base.sql`, ver secção 8):** ~~Tarefa pendente antes de a app do operador sincronizar (I3)~~: as tabelas base tinham RLS activo **sem políticas**
(fechadas a `authenticated`/`anon`): `auditoria`, `caixa`, `clientes`, `custos`, `direcoes`, `distribuicoes`,
`estoque_diario`, `estoque_longo_prazo`, `funcionarios`, `locais`, `pagamentos_credito`, `pedidos_especiais`,
`pre_encomendas`, `produtos`, `refeicoes_funcionarios`, `turnos`, `vendas`. Precisam de políticas por permissão do
organograma (`tem_permissao`, `membro_da_cozinha`) antes de a app do operador sincronizar. O verificador do Supabase
conta 19 tabelas sem políticas: as outras duas, `notificacoes_fila` e `contadores_zona`, são só do servidor e ficam
fechadas de propósito. Não criadas em I1.

**Estado da I2 (app do cliente, `apps/cliente`):** implementados C1, C2 (registo e checkout), C4, C6, C7, C8, C11,
deep link `mandabue://convite/MB-1234`, N1 (mensagem de partilha) e o envio de N2, N3, N4 e N8 (Edge Function
`enviar-notificacoes` + Expo Push). Para isso a I2 incluiu também a base da app: entrada por SMS, registo, cardápio,
carrinho, checkout e acompanhamento do pedido. Interruptores continuam todos desligados (ligam em I4).

**Pendente para pôr a I2 em uso:**
1. Fornecedor de SMS configurado no Supabase Auth (Twilio, MessageBird, Vonage…).
2. Projecto EAS (`npx eas-cli init`) e o `projectId` em `app.json` → `extra.eas.projectId`; sem ele a app não pede o token de push. Push no Android exige uma *development build* (não funciona no Expo Go).
3. Segredo `ENVIO_SEGREDO` na Edge Function; activar `pg_cron` e `pg_net`; `select agendar_envio_notificacoes(url, segredo)`.
4. Chave do Google Maps para o mapa no Android em produção (`app.json` → `android.config.googleMaps.apiKey`).
5. Cardápio e zonas (com `taxa`) preenchidos pelo operador; o pedido da app exige um endereço com zona.
6. Página https do link de convite (para quem ainda não tem a app): precisa de domínio; hoje o link é `mandabue://`.
7. App local-first (SQLite e fila de saída offline) — a app da I2 funciona com ligação à rede.

**Estado da I3 (app do operador, `apps/operador`):** implementados O1 (painel do programa, 7 dias / mês), O2
(verificação agrupada por indicador, confirmar/anular com motivo, "Confirmar todos", local no mapa), O3
(levantamentos: aprovar, rejeitar com motivo, marcar pago com referência, primeiro levantamento em destaque,
parcelas), O4 (embaixadores elegíveis e actuais, promover/remover), O5 (parâmetros e interruptores com
confirmação, auditados), O6 (cozinhas: estado, história, foto, consentimento; cardápio), O9 (relatório por cozinha
em CSV e PDF) e E1 (entregas agrupadas por ponto, estados, caixa aberta e formas de pagamento, pagador distinto).
Entrada por telefone + SMS: o administrador principal regista o número do funcionário
(`definir_telefone_funcionario`); no primeiro login a conta liga-se ao funcionário; os ecrãs seguem as permissões
do organograma e o servidor volta a verificá-las. A app corre em Android e na web. Interruptores continuam todos
desligados.

**Pendente para pôr a I3 em uso:**
1. Telefones dos funcionários registados pelo administrador principal (`select definir_telefone_funcionario(id, '9XXXXXXXX')` ou um ecrã de equipa numa fase seguinte); o fornecedor de SMS é o mesmo da I2.
2. Gestão de zonas (com `taxa`) e de caixas fica fora da I3: continuam a ser feitas pelo sistema actual.
3. ~~Políticas RLS das restantes tabelas base~~ feitas (secção 8, "Tabelas base").
4. Remover do Supabase o esquema `testes` e a extensão `pgtap` (o ambiente bloqueou o `drop`; ver `supabase/README.md`).

**Estado da I4 (lançamento aberto):** código pronto, interruptores ainda desligados. App do cliente: C3
(Destaques: top do mês com "(tu)", posição própria e amigos em falta, "Pessoas como tu", total pago no mês, atalho
para C5) e C5 (pseudónimo, "Mostrar o meu primeiro nome", "Não mostrar os meus ganhos"); botão Destaques no C1;
toque em N5/N6 abre o C1 e em N7 abre o C3. Servidor: N5 com o prato do dia, textos de N5–N7 e envio pela Edge
Function (N5 e N7 respeitam as preferências do cliente também no momento do envio). Os primeiros Embaixadores
promovem-se no O4.

**Para fazer o lançamento (ligar os interruptores no O5):** é uma decisão operacional e depende dos pendentes da I2
e da I3 (fornecedor de SMS, projecto EAS e push, `ENVIO_SEGREDO`, `pg_cron`/`pg_net` com `agendar_jobs()` e
`agendar_envio_notificacoes(...)`, cardápio e zonas preenchidos, telefones dos funcionários). Ordem sugerida:
`indicacao`, `pessoas_como_tu`, `contadores_zona`, `perfil_cozinha` (com consentimento) e por fim `destaques`.
O C14 (desligar N5 e N7 na app, em Conta → Notificações) foi antecipado da I5 para a I4, para os clientes
poderem desligar estes avisos desde o lançamento; usa as permissões já existentes (sem migração).

**Estado da I5 (avaliações e equipa):** código pronto, interruptores `avaliacoes` e `reconhecimento_equipa`
desligados. App do cliente: C9 (avaliar até 3 dias após a entrega: estrelas, comentário até 200 caracteres,
estrelas por prato, pseudónimo; botão no pedido e N9), C10 (lista na cozinha e em cada prato do cardápio, média só
com o mínimo; autor com primeiro nome e inicial ou pseudónimo). App do operador: O7 (comentários recentes com
Ocultar/Mostrar e palavras filtradas; as fotos ficam para a I7) e O8 (métricas da semana por turno, registar
reconhecimento, histórico; visível para quem tem `equipa.reconhecer` e para os membros da cozinha). N9 uma hora
depois da entrega se o pedido não foi avaliado; N12 por push para os membros do turno reconhecido (a app do
operador também regista o telemóvel). Para não expor ids, os clientes deixam de ler as avaliações dos outros
directamente: a lista e as médias vêm de funções do servidor.

**Pendente para pôr a I5 em uso:**
1. Projecto EAS também para a app do operador (`extra.eas.projectId`) para o N12 chegar por push.
2. Turnos registados com `periodo` (manhã/tarde/noite) e `hora_prometida` nos pedidos, para as métricas de turno terem dados.
3. Critério da fase: métricas de turno aceites pela equipa.

**Estado da I6 (pedidos de grupo):** código pronto, interruptor `pedidos_grupo` desligado. App do cliente: C12
(criar grupo no local de trabalho, hora de entrega de meia em meia hora, prazo 30 min/1 h/2 h antes, "a empresa
paga tudo" só para contas Empresa, partilha por WhatsApp com o link `mandabue://grupo/G-XXXXXX`) e C13 (participantes
por primeiro nome e estado, contagem regressiva, "Junta o teu pedido", taxa estimada por pessoa; o organizador fecha
ou cancela). No checkout dentro do grupo não se escolhe endereço: o pedido vai para o local do grupo e a parte da
entrega fica fixa no fecho. App do operador: O10 (grupos do dia com o resumo dos pratos para preparar, todos os
pedidos juntos, confirmar/preparar/sair de uma vez; a entrega e o pagamento de cada pessoa continuam em E1).

**Decisões tomadas na I6 (a rever se quiseres outra regra):**
1. A taxa de entrega do grupo (taxa da zona, uma só entrega) fica a 0 em cada pedido até o grupo fechar; no fecho é
   dividida por igual pelos pedidos (os primeiros a aderir levam 1 Kz a mais até a soma bater certo). No modo
   "empresa", ou com `regra_taxa_grupo = empresa` e organizador Empresa, fica toda no pedido da empresa.
2. O grupo fecha sozinho no prazo de adesão (job de 5 em 5 minutos); o organizador ou o operador podem fechar antes.
3. Cancelar um grupo só é possível antes de algum pedido entrar em preparação; cancela os pedidos ainda pendentes ou
   confirmados.

**Pendente para pôr a I6 em uso:** `pg_cron` activo com `select agendar_jobs();` (inclui o job dos grupos);
testar com 2–3 escritórios (critério da fase).

**Estado da I7 (fotos nas avaliações):** código pronto, interruptor `avaliacoes_fotos` desligado. App do cliente: no
C9 junta até 2 fotos (galeria, reduzidas para JPEG até 1280 px); as fotos são enviadas depois da avaliação e ficam
privadas até um moderador as aprovar; no C10 aparecem as fotos aprovadas. App do operador: O7 mostra as fotos por
aprovar (com a avaliação e o autor) e Aprovar/Rejeitar, auditado. Ficheiros num bucket privado (`fotos-avaliacoes`),
lidos só com endereços temporários e só por quem a política deixa.

**Pendente para pôr a I7 em uso:** designar o moderador (permissão `avaliacoes.moderar` no organograma) — critério
da fase. As fotos rejeitadas ficam no bucket sem acesso de ninguém além dos moderadores; apagá-las de vez é uma
tarefa de manutenção (Storage do Supabase).

**Estado da I8 (rede de cozinhas):** código pronto, interruptor `multi_cozinha` desligado. App do cliente: com o
interruptor ligado e mais de uma cozinha activa, o início mostra o selector de cozinha (a Cozinha da Alexandra
primeiro); o cardápio, o perfil da cozinha (C8) e o checkout passam a ser da cozinha escolhida; mudar de cozinha
esvazia o carrinho; um pedido de grupo é sempre da cozinha do grupo. App do operador: O9 com "Comparar cozinhas"
(pedidos, vendas, ticket médio, cancelados, clientes, novos, por indicação, entregas a horas, avaliações) em CSV e
PDF; filtro por cozinha nas entregas (E1) e nos grupos do dia (O10). A gestão de cada cozinha e do seu cardápio já
estava no O6 (criar cozinha, estado activa/pausada/inactiva, consentimento, pratos).

**Pendente para pôr a I8 em uso:** a primeira cozinha parceira assinada (critério da fase): criá-la no O6, com o
cardápio, o consentimento público se a responsável o der, e turnos/caixas na cozinha. Uma cozinha pausada sai do
selector e não aceita pedidos.

**Estado das I9–I11 (2 de Outubro de 2026):** código pronto, interruptores desligados.
- **I9 · Pratos montáveis:** no O6, cada prato tem "Opções" (grupos com mínimo e máximo, opções com preço extra e
  esgotada). No cliente, um prato com opções mostra "Montar" e abre o ecrã de montar, com o preço a actualizar e o
  botão desligado até os grupos obrigatórios estarem escolhidos. O servidor valida tudo e calcula o preço; o nome do
  item leva as opções, por isso a cozinha, a entrega e a venda as mostram. Falta: as opções não descontam stock.
- **I10 · Como chegar:** no O6, "Localização" com morada, horário, ponto (escrito ou "usar a localização deste
  telemóvel") e a autorização da responsável. No cliente, um cartão com a morada e "Como chegar" no início e no perfil
  da cozinha (com mapa), que abre a navegação do Google Maps. Sem API paga.
- **I11 · Acompanhamento da entrega:** quem marca "Saiu para entrega" fica como estafeta do pedido. No ecrã de
  entregas, a app do estafeta envia a posição (de 15 em 15 s ou a cada 30 m) enquanto tem pedidos a caminho e o ecrã
  está aberto. O cliente vê no ecrã do pedido o estafeta e o destino no mapa, a distância e o tempo estimado
  (distância × 1,4 a 25 km/h), actualizados de 10 em 10 s. Só se guarda a última posição e apaga-se no fim.
  Limitações: sem localização em segundo plano (o ecrã tem de ficar aberto) e o tempo é uma estimativa; para rotas
  reais será precisa uma API de rotas paga, com a chave guardada como segredo de uma Edge Function.

**Estado da I12 · Pacotes do mês (2 de Outubro de 2026):** código pronto, interruptor desligado.
- Cliente: Conta → "Pacote do mês" e um botão no início. Catálogo com os benefícios (refeições de oferta, poupança,
  entrega grátis, validade, pausa, reembolso), cartão de prova social ("4 colegas do teu local de trabalho já almoçam
  com um pacote", só a partir de `contador_minimo`, sem nomes), escolha do pagamento e adesão. Enquanto o pagamento não
  é confirmado, o ecrã mostra as instruções (`EXPO_PUBLIC_INSTRUCOES_PAGAMENTO`) e deixa cancelar. Com o pacote em
  vigor: refeições por usar, validade, poupança e "Pausar 1 dia".
- Carrinho: "Pagar com o pacote" (ligado por defeito). Cada prato gasta uma refeição e o pacote paga até ao valor da
  refeição; o resto (por exemplo um prato mais caro) e o que o saldo do Convida e Ganha não cobrir paga-se na entrega.
  Com entrega grátis, o pacote paga também a taxa, excepto nos pedidos de grupo.
- Operador: "Pacotes do mês" (`pacotes.gerir`): confirmar pagamentos (referência para Multicaixa Express e Unitel
  Money, caixa aberto para pagamentos na loja), reembolsar (as refeições pagas e não usadas) e gerir o catálogo.
- Contas: o pagamento do pacote entra como pagamento adiantado; a venda leva a parcela "Pacote" quando a refeição é
  entregue. Pedido cancelado ou estornado: as refeições voltam ao pacote.
- Antes de ligar: criar o pacote no catálogo, preencher `EXPO_PUBLIC_INSTRUCOES_PAGAMENTO` (números e morada) e dar
  `pacotes.gerir` a quem confirma os pagamentos. Falta: o pagamento é confirmado à mão (sem integração com a EMIS ou a
  Unitel).
- Avisos (push): N13 ao cliente quando o pagamento é confirmado ("O teu Almoço do Mês está activo: 22 refeições até
  31/10"); N14 quando restam 3 refeições ou menos e 3 dias antes do fim se ainda houver refeições (job diário às 9h de
  Luanda; correr `agendar_jobs()` de novo para o agendar); N15 à equipa com `pacotes.gerir` quando há uma adesão por
  confirmar. Tocar no aviso abre o ecrã dos pacotes nas duas apps.

**Correcções depois da análise do sistema (2 de Outubro de 2026):**
- Pedido criado com id gerado no telemóvel: retentar depois de uma falha de rede já não cria um pedido repetido.
- Edge Function `enviar-notificacoes` v4: marca as notificações como enviadas lote a lote; uma falha da Expo a meio
  já não repete o que chegou aos telemóveis.
- Validade das notificações (N5 2 horas, N10/N11 3 horas, N7/N9 24 horas, N6 48 horas, outras 7 dias) e limpeza
  diária da fila.
- Apagar a conta na app do cliente (Conta → Apagar a conta) e página de política de privacidade, exigidas pela
  Google Play e pela App Store. Antes de publicar: preencher `EXPO_PUBLIC_CONTACTO_PRIVACIDADE` e rever o texto com
  um jurista (Lei n.º 22/11 de Protecção de Dados Pessoais).
- Chave do Google Maps para Android lida de `GOOGLE_MAPS_ANDROID_API_KEY` (sem ela o mapa do novo endereço fica em
  branco em Android).
- CI em `.github/workflows/testes.yml`: base de dados, Edge Function e as duas apps em cada PR.

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
32. Cliente não consegue escrever `desconto_indicacao`, `credito_indicacao_usado` nem ganhos.

**Acrescentados na versão 1.1**

*Valores garantidos na ligação*
33. A ligação guarda o `ganho_por_pedido` e o `desconto_indicado` em vigor.
34. Parâmetros alterados depois da ligação → o desconto e o ganho usam os valores garantidos.
35. Valor alterado a meio dos 60 dias → os ganhos de ligações já existentes não mudam.
36. Nova ligação depois da alteração → usa os valores novos.

*Pedidos e vendas*
37. Cliente e operador não escrevem o estado do pedido directamente; o operador muda-o por `mudar_estado_pedido`.
38. Entregador marca `entregue_pago`, mas não cancela.
39. `entregue_pago` gera uma venda `App cliente` com total = subtotal + taxa − desconto; repetir o estado não a duplica.
40. Estorno gera uma venda de compensação com valores negativos.
41. Crédito de indicação aparece como parcela da venda; pedido cancelado devolve o crédito ao saldo.

*Sincronização e segurança*
42. Todas as tabelas novas têm os 6 campos de sincronização e uma estratégia de conflito registada.
43. Tabelas escritas só pelo servidor recusam escritas de dispositivos, mesmo com privilégio concedido por engano.
44. `dispositivo_id = 'servidor'` não dispara o sinal de mesmo dispositivo.
45. Parâmetros e interruptores só mudam pelas funções do servidor (auditadas).
46. Todas as funções têm `search_path` fixo; funções de trigger não são chamáveis pelas apps; todas as chaves estrangeiras têm índice.

*Decisões (duração, vendas por item, caixa, estorno, permissões)*
47. A ligação guarda `duracao_dias`; alterar a duração não muda o `expira_em` de ligações existentes; novas ligações usam a nova.
48. Entregue e pago sem caixa, com caixa fechada ou com parcelas que não somam o valor final → recusado.
49. Uma venda por item: taxa só na primeira, desconto e parcelas proporcionais com arredondamento na última, soma = valor final; cada venda regista o posto e a caixa.
50. Estorno: compensação por linha com valores negativos, `qtd = 0`, `movimenta_stock = false`; nenhum movimento de stock.
51. `pedidos.gerir` e `entregas.registar` estão no catálogo de permissões.

Os testes estão em `supabase/tests/` (pgTAP) e correm com `supabase test db`, `scripts/testar_bd.sh` ou, no SQL editor do Supabase, com os scripts gerados por `scripts/bundle_testes.py`.

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
> 1. A fase **I1** está implementada em `supabase/migrations/` (esquema base → crescimento I1 → ajustes I1 → endurecimento), com os testes da secção 13 em `supabase/tests/`. Migrações já aplicadas nunca se editam: qualquer alteração é uma migração nova.
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
7. **`REGRAS_DE_NEGOCIO.md`** não está no repositório. As regras 3, 7 e 8 foram aplicadas como descritas pelo responsável (6.9). Confirmar: "caixa aberta" = `caixa.fechamento` vazio.
8. **`pg_cron`**: activar a extensão no Supabase e correr `select agendar_jobs();` antes de ligar interruptores que dependem de jobs (I2/I4).
9. ~~**Políticas RLS das tabelas base**~~: feitas (secção 8). Falta atribuir as permissões novas às direcções no organograma.
