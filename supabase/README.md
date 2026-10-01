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
| `20261001091617_crescimento_i3_app_operador.sql` | I3: `funcionarios.telefone` e entrada por SMS (`definir_telefone_funcionario`, `ligar_funcionario`, `meu_funcionario`); leituras do operador com permissão do organograma: `painel_programa` (O1), `ganhos_em_verificacao` e `confirmar_ganhos_indicador` (O2), `levantamentos_operador` (O3), `embaixadores` (O4), `pedidos_operador` (E1); RLS de leitura em `caixa`; N3 vinda da verificação com o nome do amigo e o saldo da semana; auditoria das escritas em `cozinhas` e `cardapio` (O6). | aplicada |
| `20261001144534_crescimento_i4_lancamento.sql` | I4: C5 "Não mostrar os meus ganhos" (`perfil_destaques.ocultar_ganhos`; valores escondidos para os outros em `destaques_mes`); N5 com o prato do dia; textos de N5, N6 e N7 e envio pela Edge Function, respeitando no envio as preferências do cliente. Não liga interruptores. | aplicada |
| `20261001155248_crescimento_i5_avaliacoes_equipa.sql` | I5: avaliações lidas pelos clientes só pelas suas linhas; lista pública e médias por funções sem ids (`avaliacoes_publicas`, `medias_avaliacoes`); estrelas por prato só de pratos do pedido; O7 (`avaliacoes_moderacao`); N9 (`job_n9_avaliacao`, de 15 em 15 minutos); N12 e push para funcionários (`notificacoes_fila.funcionario_id`, `dispositivos_push.funcionario_id`, `registar_token_push_funcionario`, nova `notificacoes_por_enviar` com o destino, usada pela Edge Function; `notificacoes_pendentes` fica sem uso); `meu_funcionario().cozinhas_equipa`. Sem `drop`: a política muda com `alter policy`. | aplicada |
| `20261001161430_crescimento_i6_pedidos_grupo.sql` | I6: criar grupo validado no servidor (local de trabalho do próprio cliente, prazo e hora, modo empresa só para clientes Empresa; a app não altera grupos); pedido no grupo com o ponto e a zona do grupo e a taxa a 0 até ao fecho (`orcamento_pedido` devolve a estimativa); fecho pelo prazo (`job_grupos`, de 5 em 5 minutos), pelo organizador ou pelo operador, com a taxa da zona repartida (`regra_taxa_grupo`) ou toda no pedido da empresa; `cancelar_grupo`; N10 com hora e código, N11; `grupo_detalhe`, `meus_grupos`; O10 (`grupos_operador`, `mudar_estado_grupo`); o grupo acompanha o estado dos pedidos. | aplicada |
| `20261001162633_crescimento_i7_fotos_avaliacoes.sql` | I7: bucket privado `fotos-avaliacoes` (só JPEG, até 5 MB); o servidor define o caminho de cada foto (`<id>.jpg`); políticas do storage: envia só o autor, para uma foto sua pendente, com `avaliacoes_fotos` ligado; lê quem pode ver a foto (aprovada e avaliação visível, o próprio, moderadores); até 2 fotos por avaliação; `lista_avaliacoes` (lista pública com as fotos aprovadas) e `fotos_pendentes` (O7). | aplicada |

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
| `functions/enviar-notificacoes` | Envia a fila (clientes N2–N11; equipa N12) pelo push da Expo, um pedido por app (a Expo recusa tokens de projectos diferentes no mesmo pedido); desactiva tokens rejeitados; marca como enviadas | Publicada sem verificação de JWT, com autenticação própria: segredo `ENVIO_SEGREDO` (obrigatório) no cabeçalho `x-envio-segredo`. Agendar com `select agendar_envio_notificacoes('<url da função>', '<segredo>');` depois de activar `pg_cron` e `pg_net`. |

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
| `18_avaliacoes_equipa.test.sql` | I5: avaliar pelo telemóvel (C9), lista pública sem ids e médias (C10), moderação e palavras filtradas (O7), N9, reconhecimentos e N12 com push da equipa (O8) |
| `16_lancamento.test.sql` | I4: esconder ganhos na lista (C5), textos N5–N7, N5 com prato do dia, envio com preferências e interruptor |
| `17_preferencias_notificacao.test.sql` | C14: o cliente desliga N5 e N7 pela app, só no seu perfil e só essas colunas; N5 não é enfileirada |
| `19_pedidos_grupo.test.sql` | I6: criar grupo (C12) e validações, aderir (C13) com desconto, N10/N11, fecho e repartição da taxa, modo empresa, cancelar, O10 |
| `20_fotos_avaliacoes.test.sql` | I7: envio para o bucket privado (caminho do servidor, só o autor, limite de 2), privacidade das pendentes, fila e decisão de moderação (O7), visibilidade depois de aprovada e com a avaliação oculta |
| `15_app_operador.test.sql` | I3: telefone e ligação dos funcionários, painel (O1), verificação e "Confirmar todos" com N3 (O2), levantamentos (O3), embaixadores (O4), fila de entregas e caixas (E1), auditoria de cozinhas e cardápio (O6) |

### Como correr

- **Supabase CLI (local):** `supabase test db`.
- **Postgres local sem Docker** (precisa de `psql`, `pg_prove` e `pgtap`): `scripts/testar_bd.sh` — cria a base
  `mandabue_teste`, aplica `local/supabase_shim.sql` (papéis, `auth.uid()` e privilégios por defeito do Supabase),
  as migrações e corre os testes.
- **Projecto Supabase remoto (SQL editor, API ou MCP):** `scripts/bundle_testes.py <pasta>` gera um script por
  teste, sem comandos do `psql`. Cada script termina com um erro intencional cuja mensagem é o relatório TAP
  (`ok 1 - …`); o erro desfaz a transacção inteira.

### Resultados (1 de Outubro de 2026)

| Teste | Postgres 16 local, 15 migrações | Supabase `laruvuambdovnkojwrzp` |
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
| 15 app do operador | 28/28 | 28/28 (em partes, ver abaixo) |
| 16 lançamento (I4) | 16/16 | 16/16 |
| 17 preferências de notificação (C14) | 6/6 | 6/6 |
| 18 avaliações e equipa (I5) | 30/30 | 30/30 |
| 19 pedidos de grupo (I6) | 33/33 | 33/33 |
| 20 fotos nas avaliações (I7) | 19/19 | 19/19 |
| **Total** | **445/445** | |

Na I2 voltaram a correr no Supabase os testes afectados por cada migração (app do cliente: 06, 08, 09, 12 e 13;
desconto limitado: 02, 09 e 14); os restantes não dependem delas (e todos passam localmente).

Na I3 correram no Supabase, depois da migração da app do operador: 09 (5/5), as 3 verificações de catálogo do 12
(funções chamáveis pelas apps e por `anon`) e o 15 inteiro, dividido em partes. Nas partes remotas do 15 as situações
que o teste local cria alterando `parametros` (limite semanal 0, levantamento mínimo 100, limiar de Embaixador 1)
foram criadas com dados de teste, sem tocar na linha de `parametros` de produção. O 03 e o resto do 12 não voltaram a
correr remotamente (o ambiente bloqueou as escritas em massa); passam localmente.

Na I4 correram no Supabase o 16 (16/16), o 05 (15/15: sem a verificação que altera `limiar_intervalos` em
`parametros`) e as verificações de `search_path`, `anon` e privilégios das funções alteradas.

Na I5 correram no Supabase o 18 (30/30) e as verificações de catálogo do 09 e do 12 (funções chamáveis pelas apps,
`anon`, `search_path`, funções de trigger, índices das chaves estrangeiras). A Edge Function `enviar-notificacoes`
foi publicada de novo (versão 2), sem verificação de JWT e com o segredo próprio, como antes.

Na I6 correram no Supabase o 19 (33/33) e as verificações de catálogo (funções chamáveis pelas apps, `anon`,
`search_path`, funções de trigger, índices). A Edge Function foi publicada de novo (versão 3: envia o código do
grupo para a app abrir o grupo ao tocar em N10/N11).

Na I7 correram no Supabase o 20 (19/19, com o storage real) e as verificações de catálogo. Localmente,
`local/supabase_shim.sql` simula `storage.buckets` e `storage.objects` (com RLS) para os testes.

Nenhum dado de teste ficou na base (contagens de `funcionarios`, `clientes`, `pedidos`, `cardapio` e `caixa` a 0;
interruptores todos desligados). **Por remover:** o esquema `testes` e a extensão `pgtap` ficaram instalados no
Supabase porque o ambiente bloqueou o `drop`; correr no SQL editor
`drop schema if exists testes cascade; drop extension if exists pgtap;`.

A comparação do esquema (funções, colunas, restrições, índices, políticas, triggers, vistas, comentários e
privilégios) entre o Supabase e uma base local construída com as primeiras 4 migrações deu resultados idênticos (comparação feita antes do endurecimento e do consumo de stock).

### Dependências nas tabelas base

As funções dependem destas colunas do esquema base: `clientes(id, tipo, nome, telefone, auth_user_id)`,
`funcionarios(id, nome, direcao_id, administrador_principal, permissoes_extra jsonb, auth_user_id)`,
`direcoes(id, permissoes jsonb)`, `turnos(id, funcionario_id, data, hora_inicio, hora_fim, periodo)`,
`zonas(id, nome, tipo)`, `pratos_base(id)`, `vendas`, `caixa(data, funcionario_id, fechamento jsonb)`,
`distribuicoes(quantidade_quebra)` e `auditoria`.
