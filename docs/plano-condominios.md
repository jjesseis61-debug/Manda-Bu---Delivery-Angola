# Cozinha de condomínio

> Estado: **Fase 1 em produção (16/11/2026)** — `20261125000000_condominios.sql`.
> **Fase 2 implementada (16/11/2026)** — `20261126000000_condominios_fase2.sql`; falta aplicar à produção e APKs.
> Tudo atrás do interruptor `condominios` (precisa de `multi_cozinha`).

## Fase 1
- Condomínio = área no mapa (centro + raio, margem 50 m) ligada a uma cozinha (nunca a principal) e,
  opcionalmente, a uma zona (taxa, entrega grátis, relatório por zona).
- O GPS do telemóvel decide o que se vê; o servidor confirma que o endereço do pedido é lá dentro.
- Membros activos lá dentro: com a cozinha aberta vêem só ela; fechada vêem o cartão "fechada" e as
  outras; ao fim de 12 h fechada fica invisível.
- Lista de moradores: link com código ou a cozinha pelo telefone; vagas, data limite, aprovação opcional;
  a lista fecha sozinha. Entregas: estafeta da cozinha ou serviço contratado.

## Fase 2
- **Lista de espera** (ligada por defeito): vagas cheias → espera por ordem; sai alguém ou sobem as
  vagas → entra o primeiro, com aviso. Posição visível no link.
- **Campanhas**: por condomínio, zona ou todos; cozinha opcional; % nos pratos ou preço especial em
  pratos escolhidos; datas, dias, horas, pedido mínimo, só membros, limites por cliente e total.
  O desconto entra no preço dos pratos (`preco_original` em cada linha, `pedidos.campanha_id`).
  **Não acumula com o convite: vale o maior** (decisão do dono); com a campanha o convite não se gasta.
  Resultados por campanha; aviso aos clientes (uma vez); cartaz no início do cliente.
- **Relatório do condomínio** (30 dias): membros, novos, saídas, espera, pedidos, vendas, ticket,
  membros que pediram, pedidos com promoção, pratos e horas.

## Por decidir / Fase 3
- Venda de serviços (o dono vai indicar quais).
- Contorno exacto do condomínio (polígono), horário automático de abertura, acesso do parceiro de entregas.
