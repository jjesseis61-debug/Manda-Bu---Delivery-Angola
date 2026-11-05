# Plano — Embaixador (venda social estilo Meesho)

> Estado: **planeado, não implementado.** Desenhado com o Jesse em 2026-11-05.
> Objetivo: evoluir o programa de indicação atual para uma camada de **venda social**
> (embaixadores que partilham e ganham comissão), inspirado no GTM da Meesho, mas adaptado
> a comida hiperlocal. É um passo **incremental** — o motor já existe.

## O que já existe (base real, não mexer sem necessidade)
- `codigos_indicacao` — código por cliente; `nivel` ∈ {`normal`, `embaixador`}; `ultima_partilha_em`.
- `ligacoes_indicacao` — indicado→indicador; desconto no 1.º pedido; `expira_em` (= 1.º pedido pago + `duracao_dias`).
- `ganhos_indicacao` — **comissão por pedido pago** do indicado; estados `em_verificacao|confirmado|pago|anulado`.
- `pagamentos_indicacao` — **levantamentos** (Multicaixa Express / Unitel Money), com parcelamento.
- Trigger `processar_ganho_indicacao()` — cria a comissão e aplica o antifraude.
- Parâmetros (`parametros`): `ganho_por_pedido=100`, `desconto_indicado=500`,
  `limite_verificacao_semanal=10000`, `limite_parcelamento=20000`, `limiar_embaixador=30`,
  `max_indicados_por_local`, `duracao_dias`.
- Antifraude já ativo: mesmo dispositivo (anula), mesmo número de carteira (verificação),
  densidade por local residencial (verificação), limite semanal (verificação).
- **Embaixador hoje:** promovido à mão (`definir_nivel_indicador`); única vantagem funcional =
  **isento do limite semanal**. Na prática, quase só um distintivo.

## Desenho proposto

### 1) Identidade & promoção
- **Auto-promoção** a embaixador ao atingir `limiar_embaixador` (30) indicados ativos (hoje é manual).
  Notificação de parabéns.
- **Despromoção suave:** cair abaixo de um mínimo de ativos durante N semanas → volta a normal.

### 2) Economia diferenciada (o que o embaixador ganha a mais)
| Perk | Normal | Embaixador |
|---|---|---|
| Comissão por pedido | `ganho_por_pedido` (100) | **mais alta** — novo param `ganho_por_pedido_embaixador` (ex.: 150–200) |
| Limite semanal | 10.000 → verificação | **isento** (já existe) |
| Duração do vínculo | `duracao_dias` | **renovável** enquanto o indicado se mantém ativo (novo) |
| Levantamento | mínimo/ritmo normal | **mínimo mais baixo / mais rápido** (novo) |

### 3) Ferramentas de venda social (o salto Meesho)
- **Deep-link partilhável** do cardápio / cozinha / prato com o código embutido → abre a app do
  cliente já "ligada" ao embaixador; partilha 1-toque no WhatsApp. (Há `registar_partilha`; falta o link profundo.)
- **Montra do embaixador** — página com os pratos que ele promove.
- **Material pronto** — imagem do prato + texto + código, para colar em grupos de WhatsApp.

### 4) Progressão / gamificação
- Níveis: Normal → Embaixador → **Embaixador Ouro** (ex.: 30 → 100 ativos), com comissão/benefícios crescentes.
- Metas, distintivos e **ranking por zona**.

### 5) Painel do embaixador
- Já existe: saldo, ganhos em verificação, histórico, levantar (`ganhos_em_verificacao`,
  `saldo_disponivel_de`, `pedir_levantamento`).
- Acrescentar: nº de indicados **ativos**, **quanto falta para o próximo nível**, **ganhos do mês**.

### 6) Antifraude (manter)
- Embaixador com limites maiores mas **sempre monitorizado** pelos mesmos sinais. É o que protege a
  economia (a Meesho sofreu com fraude de revenda; o modelo atual já tem as travas certas).

## Loop de crescimento
```
Embaixador partilha link do prato no WhatsApp
  → amigo pede (desconto de 500 Kz)
  → embaixador ganha comissão por cada pedido
  → levanta por Multicaixa/Unitel
  → partilha mais  →  mais pedidos   (CAC ≈ comissão, não ads)
```

## Onde mexer (implementação futura)
- **Backend:** novos parâmetros (`ganho_por_pedido_embaixador`, mínimos de levantamento por nível,
  regras de auto-promoção/renovação); ajustar `processar_ganho_indicacao()` para usar a comissão por
  nível e a renovação do vínculo; função de auto-promoção (cron ou no fecho do pedido); deep-links.
- **App cliente:** montra/painel do embaixador, botões de partilha WhatsApp com o link, progresso de nível.
- **App operador:** já tem gestão de embaixadores, ganhos e levantamentos; acrescentar os novos níveis.
- Sem alterar a lógica de comida/entrega. Implica APKs novos quando se fizer.

## Notas de diferença vs Meesho
- Meesho = bens físicos, dropship sem stock, revenda com margem. Aqui = **comida perecível, hiperlocal**,
  com capacidade limitada (doses/horários) e frota própria. Por isso o embaixador **indica/promove** (ganha
  comissão), não "revende com stock". Densidade **zona-a-zona** e confiança do **pagamento em dinheiro**
  continuam a ser as alavancas locais.
