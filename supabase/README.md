# Base de dados — Manda Bué — Delivery Angola

## Migrações

| Ficheiro | Conteúdo |
|---|---|
| `migrations/20260930120000_modelo_base.sql` | Tabelas existentes do `MODELO_DE_DADOS.md`. Idempotente (`if not exists`): não altera um projecto onde já existam. |
| `migrations/20260930120100_crescimento_i1.sql` | Programa de Crescimento, fase I1: modelo de dados (secção 5), Cozinha da Alexandra, funções e triggers (6), vistas (7), RLS e permissões (8), fila de notificações e jobs. Deixa **todos os interruptores desligados**. |

Aplicar no Supabase: `supabase db push` (ou `supabase migration up` em local).

### Dependências da migração I1 nas tabelas existentes

Se o esquema real diferir do `MODELO_DE_DADOS.md`, confirmar estas colunas antes de aplicar:
`clientes(id, tipo, nome, telefone)`, `funcionarios(id, nome, direcao_id, administrador_principal, permissoes_extra jsonb)`,
`direcoes(id, permissoes jsonb)`, `turnos(id, funcionario_id, data, hora_inicio, hora_fim)`, `zonas(id)`,
`pratos_base(id)`, `vendas(cliente_id)`, `caixa(data, funcionario_id, fechamento jsonb)`,
`distribuicoes(quantidade_quebra)` e `auditoria(funcionario_id, funcionario_nome, acao, detalhe, ref_id, ref_tipo, bloqueado)`.

### Jobs agendados

`agendar_jobs()` agenda os jobs com `pg_cron` **se a extensão já estiver activa** (a migração não a
activa). Depois de activar o `pg_cron` no painel do Supabase, correr `select agendar_jobs();`.
Os jobs respeitam os interruptores: com tudo desligado não enfileiram nada.

| Job | Quando (Luanda) | Função |
|---|---|---|
| Contadores por zona | de hora a hora | `job_contadores_zona()` |
| N6 — indicado expira em 5 dias | diariamente às 08h | `job_n6_expiracao()` |
| N5 — lembrete do almoço | dias úteis às 11h | `job_n5_lembrete()` |
| N7 — perto do top | segundas às 08h | `job_n7_destaques()` |

## Testes (secção 13)

Testes pgTAP em `tests/`. Cada ficheiro corre numa transacção com `rollback`.

| Ficheiro | Testes da secção 13 |
|---|---|
| `00_estrutura.test.sql` | Interruptores desligados, parâmetros, Cozinha da Alexandra, `cozinha_id`, registo de cliente, auditoria imutável, RLS activo |
| `01_ligacao.test.sql` | 1–4 |
| `02_desconto.test.sql` | 5–8 |
| `03_ganho.test.sql` | 9–21 (e revisão de ganhos, 6.6) |
| `04_pagamentos.test.sql` | 22–25 (e crédito em refeições) |
| `05_destaques.test.sql` | 26–30 |
| `06_rls.test.sql` | 31–32 (executados com o papel `authenticated`) |
| `07_funcoes_apoio.test.sql` | Jobs, avaliações, grupos, locais, métricas de turno, relatório |

Correr:

- **Supabase CLI:** `supabase test db`
- **Postgres local sem Docker** (precisa de `psql`, `pg_prove` e `pgtap`):
  `scripts/testar_bd.sh` — cria a base `mandabue_teste`, aplica `local/supabase_shim.sql`
  (papéis, `auth.uid()` e privilégios por defeito do Supabase), as migrações e corre os testes.
