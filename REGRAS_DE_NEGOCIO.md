# Regras de Negócio — Já Validadas no Protótipo

Estas regras foram testadas com casos concretos no protótipo web. A app nativa deve replicar exatamente
este comportamento — não são sugestões, são decisões já tomadas e confirmadas.

## 1. Precificação

- `preço sem imposto = custo × (1 + margem%)`
- `preço final = preço sem imposto × (1 + IVA% se aplicável)`
- Custo é sempre "por unidade de compra" (ex: por kg, por litro, por unidade)
- Para calcular o preço de uma **quantidade específica** (ex: 500g de um produto comprado por kg):
  `preço = (quantidade_em_unidade_base / fator_da_unidade_de_compra) × preço_final_por_unidade_de_compra`
  — fator: 1kg = 1000g, 1L = 1000ml, unidade = 1

## 2. Pratos montáveis

- Cada componente tem quantidade e unidade próprias (não é só "incluído/excluído")
- Ao excluir um componente, perguntar sempre o motivo: **"Escolha do cliente"** ou **"Falta de estoque"**
- **Escolha do cliente** → nunca cobrado, preço recalculado sem esse componente
- **Falta de estoque, dentro da tolerância configurada** (ex: até 1 componente) → preço cheio mantido,
  a casa assume o custo
- **Falta de estoque, acima da tolerância** → preço recalculado só pelos componentes entregues
- A tolerância é configurável, só editável por quem tem a permissão `configuracoesAvancadas`
- A quantidade de cada componente pode ser ajustada **só para aquela venda específica**, sem alterar a
  receita padrão do prato

## 3. Estoque e consumo automático

- Produtos "Diário": saldo reinicia todos os dias, compra é só do dia
- Produtos "Longo Prazo": saldo acumula entre dias, entrada e consumo sempre na unidade base (grama/ml)
- **Toda venda de um prato montável desconta automaticamente** o estoque dos seus componentes — não é
  preciso lançamento manual (aplica-se tanto a Diário como Longo Prazo)
- Consumo automático deve ser proporcional: `quantidade_do_componente × quantidade_de_porções_vendidas`

## 4. Distribuição de estoque (Stock → Cozinha) e reconciliação

- Registar distribuição **não desconta** o saldo do estoque (quem desconta é a venda, no momento da venda)
- Devolução e quebra também **não alteram** o saldo do estoque — servem só para reconciliação
- Quebra/perda é uma categoria própria, separada de devolução — evita confundir acidente legítimo com desvio
- Fórmula de reconciliação por produto e por dia:
  `Enviado − Devolvido − Quebra/Perda − Vendido = Diferença não contabilizada`
  Uma diferença > 0 é saída de stock sem explicação — deve ser sinalizada visualmente

## 5. Crédito (fiado)

- Limite de crédito é definido **por cliente**, nunca um valor fixo do sistema
- **Limite = 0 significa "sem crédito autorizado"** — bloqueia qualquer venda a crédito para quem não
  tem a permissão `definirLimiteCredito`
- Quem tem a permissão pode sempre autorizar uma venda a crédito, mesmo acima do limite ou com limite 0
- O cálculo do limite deve considerar o **valor já com desconto aplicado**, não o valor de tabela
- Saldo do cliente pode ficar **negativo** (representa crédito a favor do cliente, ex: nota de crédito) —
  nesse caso, mostrar como "Crédito disponível", não como dívida

## 6. Desconto por cliente

- Percentual definido por cliente, só editável por quem tem a permissão `definirDesconto`
- Aplica-se automaticamente ao selecionar o cliente numa venda, com preview antes de confirmar
- Aplica-se independentemente da forma de pagamento (não é exclusivo de vendas a crédito)

## 7. Pagamento misto (parcelas)

- Uma venda pode ser paga em **várias parcelas**, cada uma com o seu método: Dinheiro, Cartão,
  Transferência, **Cartão de terceiro** (com nome de quem emprestou o cartão), Fiado
- A soma das parcelas **tem de bater exatamente** com o valor final da venda (com desconto e taxa de
  entrega já incluídos) antes de permitir guardar
- O Caixa físico só soma a parcela **Dinheiro** de cada venda — nunca o valor total
- O saldo devedor do cliente só soma a parcela **Fiado** — nunca o valor total da venda

## 8. Nota de crédito / devolução (pré-encomendas e pedidos especiais)

- Pré-encomendas e pedidos especiais **só geram venda real (contam no faturamento) quando confirmados
  como entregues** — nunca no momento do registo, para não contar pedidos que depois são cancelados
- Se o pedido tinha pagamento antecipado e é cancelado: perguntar sempre **devolver dinheiro** (vira
  custo "Reembolso") ou **emitir nota de crédito** (soma ao saldo do cliente, como um pagamento)
- Ao confirmar a entrega, perguntar sempre **em que posto/caixa o dinheiro entrou fisicamente**, para a
  reconciliação de caixa bater certo

## 9. Permissões e organograma

- Estrutura: Administrador Principal (pode haver vários) → Direções (criadas livremente, com permissões
  configuráveis) → Funcionário (pertence a uma Direção, herda as permissões dela, mais permissões
  individuais extra atribuídas por cima)
- `temPermissao(funcionario, permissao)`:
  1. Se `administrador_principal` → sempre `true`
  2. Senão, se a Direção do funcionário tem essa permissão → `true`
  3. Senão, se o funcionário tem essa permissão nas suas permissões extra individuais → `true`
  4. Caso contrário → `false`

## 10. Auditoria

- Regista **ações de negócio com significado**, não cada tecla — granularidade tipo "Venda registada",
  "Limite de crédito alterado de X para Y"
- Toda alteração de um valor único mostra **antes → depois** explicitamente
- **Tentativas bloqueadas contam como registo de auditoria também** — ex: alguém tentou vender a crédito
  acima do limite e foi impedido; isso fica registado, não só as ações bem-sucedidas
- Acesso à auditoria é exclusivo de quem tem a permissão `verAuditoria`
- Retenção configurada: 60 meses
- Cada registo de auditoria liga-se ao `id` do registo de negócio a que se refere (`ref_id`), para
  permitir ver o histórico completo de um pedido/venda específico

## 11. Rastreio de responsabilidade

- Pré-encomendas e pedidos especiais guardam sempre **quem registou**, **quem aprovou** (se aplicável),
  **quem entregou**, e **quem cancelou** (se aplicável) — nomes diferentes em cada campo, porque podem
  ser pessoas diferentes em momentos diferentes
- Turnos de trabalho cruzam-se com o horário das vendas para aproximar "quem estava a trabalhar quando
  este prato foi vendido"
