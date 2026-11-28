# Convida e Ganha — 1.º pedido sem comissão e telemóveis com várias contas

> Estado: **implementado (11/11/2026)** — migração `20261113000000_convida_primeiro_pedido_aparelhos.sql`.
> Falta aplicar à produção e APKs (cliente e operador).

## Análise (dono do produto)
O desconto de boas-vindas (1.000 Kz, só em pedidos ≥ 5.000 Kz) reduz a **margem**, não faz sair
dinheiro: um prato de 5.000 Kz que custa ~3.500 Kz a produzir é vendido por 4.000 Kz. Todos os
benefícios do Convida exigem **pedidos reais e pagos**. O único ponto apertado era o 1.º pedido
com desconto **e** comissão (5.000 − 1.000 − 600 = 3.400 Kz).

## Decisões
1. **Sem comissão no 1.º pedido do convidado** (o do desconto). As comissões começam no 2.º pedido,
   durante os mesmos 60 dias. Parâmetro `comissao_primeiro_pedido` (desligado) para voltar atrás.
2. **Telemóveis com várias contas: só alerta.** Não se bloqueia nem se corta nada (famílias
   partilham telemóveis). A app regista o aparelho de cada conta (Android ID / iOS vendor + id da
   instalação; na PWA só o id do navegador) e a **Vigilância** mostra os telemóveis com
   `alerta_contas_por_aparelho` (3) ou mais contas, com quem convidou quem.
3. O desconto de convite continua disponível também na PWA.
