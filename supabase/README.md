# Base de dados — Manda Bué — Delivery Angola

## Migrações

Aplicadas por esta ordem. **Uma migração já aplicada nunca se edita:** qualquer alteração é uma migração nova.

| Ficheiro | Conteúdo | Projecto de desenvolvimento `laruvuambdovnkojwrzp` |
|---|---|---|
| `20260930165537_modelo_base.sql` | Tabelas do `MODELO_DE_DADOS.md`, incluindo `pedidos` (pedidos da app). 6 campos de sincronização, índices recomendados, RLS activo e fechado por defeito. Não cria o programa de indicação antigo. | aplicada |
| `20260930173725_crescimento_i1.sql` | Programa de Crescimento, fase I1: modelo (secção 5), Cozinha da Alexandra, funções e triggers (6), vistas (7), RLS e permissões (8), fila de notificações, jobs. | aplicada |
| `20260930173922_crescimento_i1_ajustes.sql` | `pontos_entrega`/`ponto_entrega_id`; estado do pedido só no servidor; venda gerada em `entregue_pago`; 6 campos de sincronização em `parametros` e `funcionalidades`; escrita só pelo servidor; valores garantidos na ligação. | aplicada |
| `20260930183237_crescimento_i1_decisoes.sql` | `duracao_dias_garantida`; uma venda por item (taxa na 1.ª, desconto e parcelas proporcionais, soma = valor final — regra 7); caixa obrigatória em `entregue_pago` e registada na venda (regra 8); estorno sem reposição de stock (regra 3); catálogo `permissoes`. | aplicada |
| `20261001040216_crescimento_i1_endurecimento.sql` | Correcções aos avisos do Supabase: `search_path` fixo, funções de trigger não expostas, índices nas chaves estrangeiras, nome do índice de `vendas.local`. | aplicada |
| `20261001041532_crescimento_i1_consumo_stock.sql` | Regra 3 (consumo): o servidor desconta o stock só das vendas que gera de pedidos (`vendas.stock_consumido_por`); itens do pedido validados (`prato_base_id` existente); componentes excluídos/ajustados; conversão para a unidade base; só produtos `Longo Prazo`; índice único `estoque_longo_prazo (venda_id, produto_id) where venda_id is not null`; guarda (regra 10): consumo de dispositivo para venda `App cliente` descartado e auditado como bloqueado; avisos `stock_consumo_pendente`. | aplicada |
| `20261001043509_crescimento_i1_privilegios.sql` | Guarda do consumo de stock passa a SECURITY DEFINER (um trigger SECURITY INVOKER anterior marca as sessões do telemóvel); `origem_venda`, `auditar_consumo_bloqueado` e `gerar_codigo_grupo` deixam de ser chamáveis pelas apps. | aplicada |
| `20261001052041_crescimento_i2_app_cliente.sql` | I2: `registar_cliente`/`meu_perfil` (registo pelo telefone confirmado por SMS; liga clientes do balcão); `cardapio` (preço, disponível, prato do dia) e preço dos pedidos da app calculado no servidor (`orcamento_pedido`, `trg_pedidos_00_cardapio`); `meus_amigos`; `dispositivos_push` e tokens Expo; textos N2/N3/N4/N8 e funções do serviço de envio (só `service_role`). | aplicada |
| `20261001052738_crescimento_i2_desconto_limite.sql` | O desconto de indicação nunca passa o valor do pedido (subtotal + taxa): valor final nunca negativo, no pedido e no orçamento. Uso único (o que sobra não passa para o pedido seguinte). | aplicada |

Os números de versão dos ficheiros são os que o Supabase registou ao aplicar, para `supabase migration list` e
`supabase db push` não voltarem a aplicá-las.

No fim das migrações **todos os interruptores ficam desligados**.

### Jobs agendados

`agendar_jobs()` agenda os jobs com `pg_cron` **se a extensão já estiver activa** (as migrações não a activam).
Depois de activar o `pg_cron` no painel do Supabase, correr `select agendar_jobs();`.
Os jobs respeitam os interruptores: com tudo desligado não enfileiram nada.

| Job | Quando (Luanda) | Função |
|---|---|---|
| Contadores por zona | de hora a hora | `job_contadores_zona()` |
| N6 — indicado expira em 5 dias | diariamente às 08h | `job_n6_expiracao()` |
| N5 — lembrete do almoço | dias úteis às 11h | `job_n5_lembrete()` |
| N7 — perto do top | segundas às 08h | `job_n7_destaques()` |

## Edge Functions

| Função | O que faz | Configuração |
|---|---|---|
| `functions/enviar-notificacoes` | Envia a fila (N2, N3, N4, N8) pelo push da Expo; desactiva tokens rejeitados; marca como enviadas | Publicada sem verificação de JWT, com autenticação própria: segredo `ENVIO_SEGREDO` (obrigatório) no cabeçalho `x-envio-segredo`. Agendar com `select agendar_envio_notificacoes('<url da função>', '<segredo>');` depois de activar `pg_cron` e `pg_net`. |

## Testes

Testes pgTAP em `tests/`. Cada ficheiro corre numa transacção e desfaz tudo no fim: nenhum dado de teste fica na
base de dados.

| Ficheiro | Cobre |
|---|---|
| `00_estrutura.test.sql` | Interruptores desligados, parâmetros, Cozinha da Alexandra, `cozinha_id`, registo de cliente, auditoria imutável, RLS |
| `01_ligacao.test.sql` | Secção 13, testes 1–4 |
| `02_desconto.test.sql` | Testes 5–8 |
| `03_ganho.test.sql` | Testes 9–21 e revisão de ganhos |
| `04_pagamentos.test.sql` | Testes 22–25 e crédito em refeições |
| `05_destaques.test.sql` | Testes 26–30 |
| `06_rls.test.sql` | Testes 31–32 (com o papel `authenticated`), estado só no servidor, escrita só pelo servidor |
| `07_funcoes_apoio.test.sql` | Jobs, avaliações, grupos, pontos de entrega, métricas de turno, relatório |
| `08_ajustes_i1.test.sql` | Testes 33–45: nomes, sincronização, valores garantidos, venda gerada |
| `09_endurecimento.test.sql` | Teste 46: `search_path`, funções de trigger, índices (precisa da migração de endurecimento) |
| `10_decisoes_i1.test.sql` | Testes 47–51: duração garantida, vendas por item, caixa, estorno sem stock, permissões |
| `11_consumo_stock.test.sql` | Consumo de stock das vendas de pedidos: validação dos itens, conversão de unidades, excluídos/ajustados, diários, consumo uma só vez (incl. segunda tentativa do servidor), estorno, vendas do operador, guarda contra consumo de dispositivo (auditado como bloqueado), avisos |
| `12_privilegios.test.sql` | Funções SECURITY DEFINER chamáveis pelas apps (lista fechada), nenhuma para `anon`; grupo criado pela app; guarda do consumo com sessão do telemóvel |
| `13_app_cliente.test.sql` | I2: registo e ligação ao cliente do balcão, cardápio e preço no servidor, ponto/zona, desconto no orçamento, amigos, tokens de push, textos e fila de notificações |
| `14_desconto_limite.test.sql` | Desconto limitado ao valor do pedido (com e sem taxa), orçamento, entrega com valor final 0, uso único |

### Como correr

- **Supabase CLI (local):** `supabase test db`.
- **Postgres local sem Docker** (precisa de `psql`, `pg_prove` e `pgtap`): `scripts/testar_bd.sh` — cria a base
  `mandabue_teste`, aplica `local/supabase_shim.sql` (papéis, `auth.uid()` e privilégios por defeito do Supabase),
  as migrações e corre os testes.
- **Projecto Supabase remoto (SQL editor, API ou MCP):** `scripts/bundle_testes.py <pasta>` gera um script por
  teste, sem comandos do `psql`. Cada script termina com um erro intencional cuja mensagem é o relatório TAP
  (`ok 1 - …`); o erro desfaz a transacção inteira.

### Resultados (30 de Setembro de 2026)

| Teste | Postgres 16 local, 9 migrações | Supabase `laruvuambdovnkojwrzp`, 9 migrações |
|---|---|---|
| 00 estrutura | 19/19 | 19/19 |
| 01 ligação | 9/9 | 9/9 |
| 02 desconto | 12/12 | 12/12 |
| 03 ganho | 30/30 | 30/30 |
| 04 pagamentos | 22/22 | 22/22 |
| 05 destaques | 16/16 | 16/16 |
| 06 RLS | 29/29 | 29/29 |
| 07 funções de apoio | 19/19 | 19/19 |
| 08 ajustes I1 | 32/32 | 32/32 (a verificação alterada na I2 voltou a correr) |
| 09 endurecimento | 5/5 | 5/5 |
| 10 decisões I1 | 29/29 | 29/29 |
| 11 consumo de stock | 35/35 | 35/35 |
| 12 privilégios | 8/8 | 8/8 |
| 13 app do cliente | 37/37 | 37/37 |
| 14 desconto limitado | 11/11 | 11/11 |
| **Total** | **313/313** | **313/313** |

Na I2 voltaram a correr no Supabase os testes afectados por cada migração (app do cliente: 06, 08, 09, 12 e 13;
desconto limitado: 02, 09 e 14); os restantes não dependem delas (e todos passam localmente).

No fim, o esquema `testes` e a extensão `pgtap` foram removidos do Supabase e não ficou nenhum dado de teste.

A comparação do esquema (funções, colunas, restrições, índices, políticas, triggers, vistas, comentários e
privilégios) entre o Supabase e uma base local construída com as primeiras 4 migrações deu resultados idênticos (comparação feita antes do endurecimento e do consumo de stock).

### Dependências nas tabelas base

As funções dependem destas colunas do esquema base: `clientes(id, tipo, nome, telefone, auth_user_id)`,
`funcionarios(id, nome, direcao_id, administrador_principal, permissoes_extra jsonb, auth_user_id)`,
`direcoes(id, permissoes jsonb)`, `turnos(id, funcionario_id, data, hora_inicio, hora_fim, periodo)`,
`zonas(id, nome, tipo)`, `pratos_base(id)`, `vendas`, `caixa(data, funcionario_id, fechamento jsonb)`,
`distribuicoes(quantidade_quebra)` e `auditoria`.
