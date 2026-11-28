# Piloto da Junta Bué no trabalho

> Preparado a 28/11/2026. O piloto é com a equipa da colega que propôs a ideia. Tudo está atrás do
> interruptor `equipas_trabalho` (desligado): enquanto estiver desligado, nenhum cliente vê a equipa.

## 1. Antes de começar (uma vez)

1. Aplicar no SQL Editor as migrações `20261227000000_balcao_recipientes.sql` e
   `20261228000000_equipas_trabalho.sql` (por esta ordem).
2. Gerar os APKs novos do cliente e do operador e publicar a app web.
3. Ligar o interruptor (Parâmetros → interruptores, ou no SQL Editor):
   ```sql
   update funcionalidades set activa = true where chave = 'equipas_trabalho';
   ```
4. Confirmar que o `pg_cron` tem a tarefa `mb_equipas` (abre o grupo do dia a cada 10 minutos):
   ```sql
   select jobname, schedule from cron.job where jobname = 'mb_equipas';
   ```

## 2. Montar a equipa (com a responsável, ao vivo)

1. A responsável abre **Conta → A minha equipa**, escolhe a cozinha no Início, dá o nome à equipa,
   o endereço do trabalho, a hora da entrega e até quando se pede.
2. Junta os colegas pelo código de cada um (**Convida e Ganha → o meu código**, ex.: MB4812).
3. Cada colega aceita na app e escolhe as autorizações: «pode pedir o meu almoço» e «pode ver a
   minha conta do mês». Explicar que pode retirá-las quando quiser.
4. No operador (**Equipas no trabalho**), quem gere clientes confirma o **limite mensal** (proposto:
   40.000 Kz, mais baixo no primeiro mês se se preferir) e a **origem** (plataforma ou cozinha).
5. As Finanças propõem o **acordo** (proposto: plataforma paga; 3% / 5% / 10%; escalões 10 e 15
   almoços por dia; bebidas não contam; tecto 1.000 Kz por refeição) e a cozinha aceita-o.

## 3. Durante o piloto (4 semanas)

| O que acompanhar | Onde | Alvo |
|---|---|---|
| Colegas que pedem por dia útil | Operador → Equipas → grupo de hoje | subir semana a semana |
| Pedidos feitos pela responsável em nome de outros | Auditoria (`pedido_por_colega`) | menos de metade |
| Recusas dos colegas | Avisos «recusou o almoço» | quase nenhuma |
| Refeições extra pedidas / aprovadas | Operador → Equipas | aprovadas a tempo |
| Contas pagas até dia 10 | Operador → Equipas → Contas | todas |
| Benefício desbloqueado e pago | Operador → Equipas → Acordo e benefício | pago no mês seguinte |

**Grupo de controlo (Skinner):** escolher outra equipa do mesmo bairro que já pede em grupo sem a
equipa fixa e comparar os almoços por dia útil das duas, nas mesmas 4 semanas.

**Sinais de alarme (vigilância):** muitos pedidos em nome dos outros, muitas recusas, refeições
extra todos os dias, cozinha a passar clientes para acordos «só a cozinha».

## 4. Decidir no fim

- Continuar, ajustar os escalões ou o limite, ou parar (desligar `equipas_trabalho`).
- Responder às decisões que faltam (secção 3.6 de `projecto-balcao-e-equipas.md`).
- Confirmar com o contabilista a fatura a crédito de cada almoço e o recibo do pagamento do mês.

## 5. As cinco lentes

- **Bandura:** a responsável vê metas próximas («mais 3 almoços por dia para os 5%»), comparada consigo própria.
- **Cialdini:** o colega autoriza, é avisado quando pedem por ele e pode recusar; a conta de cada um é privada.
- **Rogers:** é a vaquinha do almoço e a conta no fim do mês; a responsável é a líder de opinião.
- **Prahalad:** paga-se ao mês, como se recebe; em dinheiro ou por referência; a responsável ganha um rendimento.
- **Skinner:** o benefício chega quando o colega paga; uma refeição por dia e o limite travam abusos; piloto com grupo de controlo.
