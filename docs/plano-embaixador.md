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

### 1) Identidade & promoção — **2 níveis** (decisão 2026-11-07)
30 indicados ativos como porta de entrada é **demasiado alto** (quase ninguém chega → o benefício
nunca liga; e mata a autoeficácia, que precisa de metas próximas). Por isso: **dois degraus** — um
baixo e motivador, outro alto para o benefício caro/sensível.
- **Auto-promoção a Embaixador** ao atingir **~5 indicados ativos** (alcançável). Notificação de parabéns.
- **Auto-promoção a Embaixador Ouro** ao atingir **~30 indicados ativos** (onde vive o benefício arriscado).
- **Despromoção suave:** cair abaixo de um mínimo de ativos durante N semanas → desce de nível.

### 2) Economia diferenciada (valores propostos, ajustáveis)
| Perk | Normal | **Embaixador** (≥5) | **Embaixador Ouro** (≥30) |
|---|---|---|---|
| Comissão por pedido | `ganho_por_pedido` (100) | **150** (`ganho_por_pedido_embaixador`) | **200** (`ganho_por_pedido_ouro`) |
| Bónus de boas-vindas (1.º amigo) | — | **+300** (`bonus_boas_vindas`) | **+300** |
| **Limite semanal** (10.000 → verificação) | aplica-se | **aplica-se** (segurança) | **isento** (o perk atual, só no topo) |
| Levantamento mínimo | normal | **mais baixo** | **ainda mais baixo** |
| Duração do vínculo | `duracao_dias` | renovável enquanto o indicado se mantém ativo | renovável |

> **Chave de segurança:** o degrau **barato e motivador** (comissão 150 + bónus) fica **baixo (5)**; o
> degrau **caro e sensível** (isenção do limite semanal) fica **em cima (30)** — exatamente onde está
> hoje. Assim não se baixa a segurança atual e ganha-se um nível de entrada atingível.

### 3) Ferramentas de venda social (o salto Meesho)
- **Deep-link partilhável** do cardápio / cozinha / prato com o código embutido → abre a app do
  cliente já "ligada" ao embaixador; partilha 1-toque no WhatsApp. (Há `registar_partilha`; falta o link profundo.)
- **Montra do embaixador** — página com os pratos que ele promove.
- **Material pronto** — imagem do prato + texto + código, para colar em grupos de WhatsApp.

### 4) Progressão / gamificação
- Níveis: **Normal → Embaixador (≥5) → Embaixador Ouro (≥30)**, com comissão/benefícios crescentes.
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

## Estado de implementação
- **Fase 1 (app — primeira vitória):** ✅ implementada (`apps/cliente/.../convida.tsx`, commit d0abbd3).
- **Fase 2 (backend — economia 2 níveis):** ✅ migração escrita e **validada localmente**
  (`supabase/migrations/20261104000000_embaixador_niveis.sql`); **falta aplicar à produção com autorização**.
  Validado: comissão por nível (100/150/200), bónus de boas-vindas +300 só na 1.ª vitória,
  promoção automática a embaixador aos 5 activos, isenção do limite semanal só para Ouro,
  comissão nunca abaixo do valor garantido. Sem funções novas chamáveis pelas apps → 12_privilegios intacto.
  - **Decisões aplicadas na migração (a confirmar antes de produção):**
    - *"Activo"* = indicado com ≥1 ganho confirmado/pago **e** vínculo vivo (não basta criar a ligação — evita fraude).
    - *Comissão normal* = **exactamente o valor garantido (snapshot)** da ligação; subir o parâmetro não altera
      ligações existentes. Só Embaixador/Ouro recebem a taxa do nível (150/200) como uplift (nunca abaixo do garantido).
    - *Bónus de boas-vindas* = **uma vez por embaixador**, na 1.ª vitória confirmada (a "primeira vitória garantida").
      **Desligado por defeito (`bonus_boas_vindas=0`)** — o mecanismo está pronto e testado; liga-se com um valor
      confirmado (`update parametros set bonus_boas_vindas=300`). Quando ligado, soma-se ao valor do ganho (aparece no push N3).
    - *Despromoção* automática **não** implementada (só sobe); fica para um cron posterior.
    - *Push de parabéns pela promoção* não implementado nesta fase (a app mostra o novo nível via `meu_perfil`);
      evita tocar no pipeline de texto/envio das notificações.
- **Fase 3 (deep-link do prato + OG + PWA/domínio):** planeada (secção abaixo).

## Onde mexer (implementação futura)
- **Backend (Fase 2 — 2 níveis):**
  - `codigos_indicacao.nivel`: alterar o CHECK para aceitar **`ouro`** (hoje só `normal`/`embaixador`).
  - Novos parâmetros: `ganho_por_pedido_embaixador` (150), `ganho_por_pedido_ouro` (200),
    `bonus_boas_vindas` (300), `limiar_embaixador` = **5** (entrada) e `limiar_ouro` = **30**
    (hoje `limiar_embaixador`=30 passa a ser o de Ouro), mínimos de levantamento por nível.
  - `processar_ganho_indicacao()`: comissão por **nível** (100/150/200); **bónus** no 1.º ganho de cada
    indicado; **isenção do limite semanal só para `ouro`** (hoje é para `embaixador`); renovação do vínculo.
  - **Auto-promoção** (cron ou no fecho do pedido): `embaixador` ao atingir 5 ativos, `ouro` aos 30;
    despromoção suave.
  - Expor `nivel` no `meu_perfil` e `limiar_embaixador`/`limiar_ouro` nos parâmetros (para o painel).
  - Testes pgTAP (incl. 12_privilegios) + aplicar com autorização.
- **Deep-links** (Fase 3): ver secção própria abaixo.
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
