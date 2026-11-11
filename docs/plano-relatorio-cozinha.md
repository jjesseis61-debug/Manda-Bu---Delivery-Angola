# Plano — Relatório da cozinha (detalhado, diário ou por datas)

> Estado: **implementado (11/11/2026)** — migração `20261112000000_relatorio_cozinha_detalhado.sql`,
> ecrã **Relatórios** do operador. Falta aplicar a migração à produção e um APK do operador.
> Feito: períodos (hoje/ontem/7 dias/mês/mês anterior/datas), A com comparação, B, C, D, F, G, H, I,
> PDF e CSV, comissão por cozinha e fecho do dia automático (N42).
> **Fase 3 (11/11/2026, migração `20261115000000_relatorio_rentabilidade.sql`):** custo de uma dose por
> prato/opção (ecrã «Custos e margens»), despesas por cozinha (ecrã «Despesas»), secção
> **Rentabilidade** (custo dos pratos, % das vendas, margem bruta, despesas, resultado aproximado,
> margem por prato) e **Doses** (esgotou em quantos dias e a que horas, sobras, desperdício), com
> histórico das doses guardado às 23:55. Falta: tempos por etapa (confirmar → preparar → sair).
> Nota: sem fichas técnicas na produção, o custo é escrito pela cozinha (estimativa com os custos actuais).
> Objetivo: a responsável da cozinha (e a gestão) perceber, num só sítio, **quanto vendeu,
> o que vendeu, quanto recebeu e de que forma, o que correu mal e onde melhorar** — num dia
> ou num período à escolha.

## 1. O que existe hoje (diagnóstico)
Relatório por cozinha (`relatorio_cozinha`):
- Pedidos por dia, clientes novos e por indicação, retenção 30/60/90, média das avaliações,
  prato mais pedido.
- Períodos fixos: **7 dias, 30 dias, este mês**. Não há "hoje", "ontem" nem datas à escolha.
- **Não mostra dinheiro** (vendas, descontos, formas de pagamento) — só o comparativo entre
  cozinhas mostra vendas e ticket médio.
- Já existem peças soltas noutros ecrãs: **fecho diário** e **conciliação** (caixa,
  pagamentos electrónicos, alertas), avaliações, reclamações, custos e compras.

**Problema:** a cozinha não tem um relatório único e detalhado; a informação de dinheiro e
de operação está espalhada e sem período livre.

## 2. Período
- Atalhos: **Hoje · Ontem · Últimos 7 dias · Este mês · Mês anterior · Escolher datas** (de/até).
- Limite: até 366 dias por relatório.
- Datas sempre no **dia de Luanda** (nunca UTC — ver o caso das 23h UTC já corrigido nos testes).
- **Comparação automática com o período anterior equivalente** (ex.: esta semana vs a anterior),
  com a variação em % ao lado de cada número principal (▲ / ▼).

## 3. O que deve constar (visão de especialista em restauração/entregas)
Ordenado do mais importante para o menos. Cada secção responde a uma pergunta da gestão.

### A. Resumo (cartões no topo) — *"Como correu?"*
| Indicador | Definição |
|---|---|
| Vendas brutas | Soma dos pratos dos pedidos entregues (subtotal) |
| Descontos | Convite + saldo Convida usado + outros, separados |
| Vendas líquidas | Brutas − descontos |
| Taxas de entrega | Total cobrado em entregas (separado das vendas de comida) |
| Pedidos entregues | Nº |
| Ticket médio | Vendas brutas ÷ pedidos entregues |
| Cancelados | Nº, valor e % (e quem cancelou: cliente / cozinha) |
| Clientes | Únicos · novos · recorrentes |
| Avaliação média | ★ e nº de avaliações |
| Entregas a horas | % dentro da hora prometida (com a tolerância) |

### B. Vendas no tempo — *"Quando vendemos?"*
- **Por dia**: pedidos, vendas, ticket médio (tabela + gráfico de barras).
- **Por hora do dia**: mostra as horas de pico → ajustar turnos, doses e estafetas.
- **Por dia da semana** (em períodos ≥ 14 dias).

### C. Cardápio — *"O que vendemos e o que dá dinheiro?"*
- Por prato: **quantidade, receita e % do total**, ordenado (análise ABC / Pareto: os ~20%
  de pratos que fazem ~80% das vendas).
- **Pratos montados ("Serve o teu próprio prato")**: opções mais escolhidas, valor médio do prato.
- **Pratos esgotados**: quantas vezes e a que horas (doses chegaram a 0) → vendas perdidas.
- **Pratos que não venderam** no período → candidatos a sair do cardápio.
- Avaliação média **por prato**.

### D. Dinheiro e pagamentos — *"Quanto recebemos e como?"*
- Por forma de pagamento: **dinheiro, Multicaixa Express, Unitel Money, transferência**,
  pacote pré-pago, conta de empresa, saldo Convida.
- Comprovativos por conferir; diferenças de caixa (sangrias, faltas/sobras); caixas não fechadas.
- Ligação ao **fecho diário** e à **conciliação** já existentes (reutilizar, não duplicar).

### E. Custos e margem — *"Ganhámos dinheiro?"* (quando houver dados)
- **Custo estimado dos pratos vendidos (CMV)** a partir do custo dos produtos das receitas.
- **Margem bruta** (vendas líquidas − CMV) e **% CMV** (referência do setor: 28–35%).
- Despesas lançadas (`custos`) e compras do período (`estoque_diario`).
- Resultado aproximado: margem bruta − despesas.

### F. Operação e serviço — *"Fomos rápidos e fiáveis?"*
- Tempos médios: **confirmar → preparar → sair → entregar**.
- % a horas, atrasos avisados ao cliente e motivos.
- **Cancelamentos por motivo** (top 5).
- **Por estafeta**: entregas, tempo médio, % a horas, recusas.
- **Por preparador**: pedidos preparados.
- Pedidos **agendados** e de **grupo/empresa** (nº e valor).

### G. Clientes e zonas — *"Quem compra e de onde?"*
- Clientes novos vs recorrentes, retenção, vindos por indicação.
- **Por zona/bairro**: pedidos e vendas (onde está a procura; onde investir em entregas).
- Top clientes do período (uso interno).

### H. Qualidade — *"Os clientes estão satisfeitos?"*
- Distribuição de estrelas (1–5), comentários negativos recentes.
- **Reclamações**: nº, motivos, reembolsos/compensações dadas.

### I. Convida e Ganha nesta cozinha
- Pedidos com desconto de convite (nº e custo).
- Comissões geradas pelos pedidos desta cozinha.

## 4. Formatos
- **Ecrã**: cartões de resumo + secções recolhíveis (abrir só o que interessa).
- **PDF**: pronto a imprimir ou enviar por WhatsApp — cabeçalho com cozinha, período,
  "gerado por / em", e só as secções com dados.
- **CSV (Excel)**: duas folhas — **por pedido** e **por prato** — para análise própria.
- (Fase 3) **Envio automático do fecho do dia** às 23h para a responsável (push / WhatsApp / e-mail).

## 5. Permissões
- **Gerente**: só a(s) sua(s) cozinha(s).
- **Finanças / admin**: todas as cozinhas + comparativo.
- Exportar mantém a permissão `relatorios.exportar`.
- Sem dados pessoais desnecessários no PDF (telefone do cliente não sai).

## 6. Técnico
- Nova RPC `relatorio_cozinha_detalhado(p_cozinha, p_inicio, p_fim)` → `jsonb` com uma
  chave por secção (A–I) e o bloco do período anterior para as variações.
  Mantém-se a RPC atual até a nova estar em uso (sem quebrar APKs antigos).
- **Definições únicas** (para os números baterem certo com o fecho diário e a conciliação):
  venda = pedido **entregue**; cancelado conta à parte; datas em `Africa/Luanda`.
- Desempenho: limite de 366 dias; índices em `pedidos (cozinha_id, entregue_em)` se preciso.
- Segurança: `SECURITY DEFINER` com `exigir_permissao` + filtro pela cozinha do gerente;
  entra na lista do teste `12_privilegios`.
- Testes **pgTAP** por secção (valores conhecidos) + testes jest do ecrã.
- A confirmar na implementação: histórico de **doses por dia** (para esgotados/sobras) e se
  todas as receitas têm custo de produto preenchido (para o CMV).

## 7. Fases (entregar valor cedo)
1. **Fase 1 — o essencial**: períodos (hoje/ontem/datas), resumo A com comparação,
   vendas por dia/hora (B), por prato (C) e por forma de pagamento (D). PDF e CSV.
2. **Fase 2 — operação**: tempos, estafetas, cancelamentos por motivo, zonas (F, G), qualidade (H).
3. **Fase 3 — rentabilidade e automação**: CMV/margem e despesas (E), esgotados/sobras,
   Convida (I), envio automático do fecho do dia.

## 8. Perguntas em aberto (para o dono do produto)
1. Há uma **comissão da plataforma** por cozinha? Se sim, o relatório deve mostrar
   *"a receber pela cozinha"* (vendas − comissão − descontos suportados pela plataforma).
2. Quem suporta o **desconto de convite** e o **saldo Convida**: a cozinha ou a plataforma?
   (Muda o valor líquido da cozinha.)
3. O relatório deve mostrar **IVA** separado?
4. O fecho do dia automático deve ir para quem, e por que canal?

## 9. Decisões (dono do produto, 11/11/2026)
1. **Comissão da plataforma: sim, uma % por cozinha** (`cozinhas.comissao_percent`, 0–50 %, só o
   admin da plataforma a muda). O relatório mostra **a receber pela cozinha = vendas de comida − comissão**.
2. **Desconto de convite e saldo Convida: por cozinha** (`cozinhas.convida_cozinha_percent`, no ecrã
   da cozinha, só o admin): **Plataforma (0%)**, **Cozinha (100%)** ou **dividir** (ex.: 50%).
   Regra de uso: cozinhas **com fluxo** → plataforma; cozinhas **sem fluxo** → cozinha. A parte da
   cozinha sai do «a receber pela cozinha». As comissões dos convidantes ficam com a plataforma.
3. **IVA: não, por agora.**
4. **Fecho do dia às 23h (Luanda): push (N42) aos gerentes da cozinha e ao administrador principal**,
   só às cozinhas com movimento no dia.

## Tempo de cada etapa (11/11/2026)
Secção "Tempo de cada etapa" no relatório (e no CSV/PDF), função `tempos_etapas_cozinha`:
- Etapas dos pedidos entregues (sem agendados): **confirmar** (feito → confirmado), **começar** (→ em preparação),
  **preparar e esperar estafeta** (→ saiu), **caminho** (→ entregue) e o **total**.
- Para cada uma: o tempo **normal** (mediana) e o dos **10% piores** (p90); a etapa que mais pesa fica marcada,
  com um conselho prático. Também: entregues a tempo vs hora prometida (inclui agendados) e atraso normal,
  por hora do pedido, caminho por estafeta e os 5 pedidos mais lentos (com a etapa onde perderam tempo).
- Horas: novas colunas `pedidos.confirmado_em` e `pedidos.saiu_em` (gravadas pelo servidor na transição);
  para pedidos antigos usa-se a auditoria (`pedido_estado`), que tem o histórico desde o início.
- Limitação: não há o estado "pronto", por isso a preparação inclui a espera pelo estafeta.
