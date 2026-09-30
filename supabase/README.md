# Base de dados — Manda Bué — Delivery Angola

## Migrações

Aplicadas por esta ordem. **Uma migração já aplicada nunca se edita:** qualquer alteração é uma migração nova.

| Ficheiro | Conteúdo | Projecto de desenvolvimento `laruvuambdovnkojwrzp` |
|---|---|---|
| `20260930165537_modelo_base.sql` | Tabelas do `MODELO_DE_DADOS.md`, incluindo `pedidos` (pedidos da app). 6 campos de sincronização, índices recomendados, RLS activo e fechado por defeito. Não cria o programa de indicação antigo. | aplicada |
| `20260930173725_crescimento_i1.sql` | Programa de Crescimento, fase I1: modelo (secção 5), Cozinha da Alexandra, funções e triggers (6), vistas (7), RLS e permissões (8), fila de notificações, jobs. | aplicada |
| `20260930173922_crescimento_i1_ajustes.sql` | `pontos_entrega`/`ponto_entrega_id`; estado do pedido só no servidor; venda gerada em `entregue_pago`; 6 campos de sincronização em `parametros` e `funcionalidades`; escrita só pelo servidor; valores garantidos na ligação. | aplicada |
| `20260930180000_crescimento_i1_endurecimento.sql` | Correcções aos avisos do Supabase: `search_path` fixo, funções de trigger não expostas, índices nas chaves estrangeiras, nome do índice de `vendas.local`. | **por aplicar** (a aguardar confirmação) |

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

### Como correr

- **Supabase CLI (local):** `supabase test db`.
- **Postgres local sem Docker** (precisa de `psql`, `pg_prove` e `pgtap`): `scripts/testar_bd.sh` — cria a base
  `mandabue_teste`, aplica `local/supabase_shim.sql` (papéis, `auth.uid()` e privilégios por defeito do Supabase),
  as migrações e corre os testes.
- **Projecto Supabase remoto (SQL editor, API ou MCP):** `scripts/bundle_testes.py <pasta>` gera um script por
  teste, sem comandos do `psql`. Cada script termina com um erro intencional cuja mensagem é o relatório TAP
  (`ok 1 - …`); o erro desfaz a transacção inteira.

### Resultados (30 de Setembro de 2026)

| Onde | 00–08 | 09 |
|---|---|---|
| Postgres 16 local, 4 migrações | 188/188 | 5/5 |
| Supabase `laruvuambdovnkojwrzp` (Postgres 17), 3 migrações aplicadas | 188/188 | por correr (migração por aplicar) |

A comparação do esquema (funções, colunas, restrições, índices, políticas, triggers, vistas, comentários e
privilégios) entre o Supabase e a base local construída a partir destes ficheiros deu resultados idênticos.

### Dependências nas tabelas base

As funções dependem destas colunas do esquema base: `clientes(id, tipo, nome, telefone, auth_user_id)`,
`funcionarios(id, nome, direcao_id, administrador_principal, permissoes_extra jsonb, auth_user_id)`,
`direcoes(id, permissoes jsonb)`, `turnos(id, funcionario_id, data, hora_inicio, hora_fim, periodo)`,
`zonas(id, nome, tipo)`, `pratos_base(id)`, `vendas`, `caixa(data, funcionario_id, fechamento jsonb)`,
`distribuicoes(quantidade_quebra)` e `auditoria`.
