# IVA e faturação — Manda Bué (Angola)

## Como a app se posiciona

A app Manda Bué é um **canal de encomenda online**. **Não emite faturas.** O que o cliente vê é um
**resumo da encomenda** (documento não fiscal). A **fatura fiscal** é emitida pelo **software de
faturação certificado pela AGT** na cozinha/restaurante, no momento da entrega ou do pagamento.

Isto está agora escrito na app:
- No **carrinho** e no **ecrã do pedido**: "Preços com IVA incluído, quando aplicável. A fatura é
  emitida na cozinha, na entrega."
- No ecrã do pedido: "Este é o resumo da tua encomenda, não é uma fatura."

Os preços mostrados ao cliente (`cardapio.preco`) são o **preço final com IVA incluído**, como se
usa em Angola. Os campos `iva_aplicavel`/`iva`/`margem` nos produtos servem só para o **cálculo
interno de custo e preço** (ex.: valor dos ingredientes nos pratos montáveis) — não para emitir
documento fiscal.

## Enquadramento legal (a confirmar com o contabilista)

- **IVA — taxa normal: 14%** (Código do IVA, Lei n.º 7/19).
- **Taxa reduzida de 5%** para ~20 categorias de bens alimentares de amplo consumo / cesta básica
  (produto cru), em vigor desde 1 de janeiro de 2024.
- **Refeição confecionada (restauração)** é um serviço — em regra na **taxa normal de 14%**;
  **confirmar**, por haver nuances.
- **Regime de não sujeição:** faturação anual até **10 milhões de Kz** → **não sujeito a IVA**
  (não cobra IVA). Muitas cozinhas pequenas poderão estar aqui.
- **Faturação:** Decreto Presidencial n.º 292/18 (faturas e documentos equivalentes) e o novo
  **Decreto Presidencial n.º 71/25** (Regime Jurídico das Faturas, faturação eletrónica) + Decreto
  Executivo n.º 683/25 (estrutura de dados, SAF-T (AO), validação da AGT). **Software de faturação
  tem de ser certificado pela AGT**; cumprimento pleno da faturação eletrónica a partir de
  **1 de janeiro de 2027**, com período de adaptação antes disso.

## Perguntas para o contabilista

1. Qual a taxa de IVA aplicável às **refeições confecionadas** vendidas por cada cozinha (14%? 5% em
   algum caso? isento?).
2. Cada cozinha está em que **regime** (geral, simplificado, ou não sujeição por faturar ≤ 10M Kz)?
3. O **software de faturação certificado** que cada cozinha usa (ou vai usar) emite a fatura do
   pedido recebido pela app, e como recebe os dados do pedido?
4. Calendário de adoção da **faturação eletrónica** (AGT) para as cozinhas até 2027.

## Fontes

- Ministério das Finanças — IVA 5% para bens alimentares (1 jan. 2024).
- OGE 2026 (Lei n.º 14/25) — medidas fiscais.
- Decreto Presidencial n.º 71/25 — Regime Jurídico das Faturas.
- Decreto Executivo n.º 683/25 — estrutura de dados e SAF-T (AO).
- Decreto Presidencial n.º 292/18 — faturas e documentos equivalentes.
