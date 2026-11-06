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

---

## Painel do embaixador — à luz da autoeficácia (Bandura)

Desenho assente nas 4 fontes de autoeficácia; a **"primeira vitória garantida"** é a peça central.

| Fonte de autoeficácia | No painel |
|---|---|
| **1. Experiência de domínio** (a mais forte) | "A tua primeira vitória" — missão guiada de 3 passos que leva aos **primeiros 100 Kz rápido e garantido** |
| **2. Aprendizagem vicária** (modelagem) | Cartão "Pessoas como tu" — um embaixador **real da mesma zona** a ganhar |
| **3. Persuasão social** | **Bónus de boas-vindas** + celebração ruidosa quando a 1.ª comissão cai |
| **4. Estados emocionais** (baixar ansiedade) | "Leva 10 segundos · a mensagem já vai pronta" — passos claros, sem jargão |

**"Garantida" = mecânica, não slogan:** (a) mensagem pronta + partilha 1-toque; (b) a vitória dispara
no **1.º pedido do 1.º amigo** (barreira mínima); (c) **bónus de boas-vindas** no 1.º amigo para a
primeira recompensa ser maior e certa; (d) **celebração** imediata que reforça o domínio.

**Ecrã 1 — novo embaixador (primeira vitória):** cartão-herói "A tua primeira vitória" (3 passos +
barra: *és embaixador* ✓ · *partilha um prato* ● · *um amigo pede → ganhas* ○) + botão WhatsApp grande;
bónus de boas-vindas (ex.: +300 Kz no 1.º amigo); "Pessoas como tu" (modelo real da zona); "Como ganhas" 1-2-3.

**Ecrã 2 — já ativo:** saldo + Levantar; progresso para "Embaixador Ouro" (sub-metas próximas);
ganhos do mês + nº de pedidos; ranking da zona (#2 na Maianga); lista de amigos ativos.

> Ideia-chave: a primeira vitória **não se deixa ao acaso** — desenha-se para acontecer cedo, ser pequena e ser celebrada.

## Mensagem pronta (WhatsApp) + deep-link do prato

### Deep-link do prato
- **Link partilhado (https):** `https://mandabue.ao/p/{cardapio_id}?r={CODIGO_DO_EMBAIXADOR}`
  (`cardapio_id` → rota `montar/[id]`; `r` → `codigos_indicacao.codigo`).
- **Cartão no WhatsApp (Open Graph):** página web do prato com `og:image` (foto), `og:title`, `og:description`
  ("…ganha 500 Kz no 1.º pedido"). Sem OG, o WhatsApp mostra só o link cru.
- **Ao clicar:**
  - App instalada → abre `montar/{id}` com `?r=` → a app chama **`ligarIndicacao(r)`** 1× (se ainda não ligado)
    e mostra o prato. Scheme equivalente: `mandabue://montar/{id}?r={CODIGO}`.
  - Sem app → página web do prato + "Abrir/Instalar"; o `r` fica guardado (*deferred deep link*) para aplicar
    após instalar/registar.
- **Reutiliza:** rota `convite/[codigo]` (fallback só-código, já liga a indicação); rota `montar/[id]`
  (passa a ler `?r=`); **`registarPartilha()`** ao partilhar (atualiza `ultima_partilha_em` e alimenta o
  progresso da 1.ª vitória). Antifraude de `ligar_indicacao` mantém-se (o link não o contorna).
- **Infra nova (1×):** domínio `mandabue.ao` + Android App Links / iOS Universal Links (o `scheme mandabue`
  já existe para o caso interno) + página web do prato com meta-tags OG. Sem domínio ainda: começar com
  `mandabue://` + `convite/{codigo}` e evoluir para o link-do-prato com preview.

### Mensagem pronta (a app compõe; editável)
Via `Share` nativo ou `https://wa.me/?text=<texto+link URL-encoded>`. Benefício do amigo primeiro (500 Kz),
prato + preço concretos, 1 emoji, negrito do WhatsApp, link no fim. Valores vêm dos parâmetros reais
(`desconto_indicado`) e do cardápio.

- **Prato específico:** `🐟 Experimenta o *Choco frito* da Manda Bué (12.000 Kz) — comida de casa entregue aí. Pede pela app e ganhas *500 Kz de desconto* no teu 1.º pedido 👇 {link}`
- **Cozinha / geral:** `🍛 A *Cozinha da Tia* (aqui da Maianga) está a bombar na Manda Bué. Pede pela app e tens *500 Kz* no 1.º pedido 👇 {link}`
- **Curta:** `Comida de casa na Manda Bué 😋 Ganha *500 Kz* no 1.º pedido 👇 {link}`

> Mockups de referência (painel + WhatsApp) foram partilhados no chat em 2026-11-05/06.
