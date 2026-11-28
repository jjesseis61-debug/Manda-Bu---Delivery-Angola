# Teste de funcionamento geral — 12 meses simulados

Simulação de 5 out. 2026 a 4 out. 2027 numa base local, nunca na produção. Usa todas as migrações
e o relógio do Postgres a avançar dia a dia. Clientes, cozinhas, estafetas, gerentes, finanças e
administrador fazem as mesmas chamadas que as apps, com as regras de acesso (RLS). As tarefas do
pg_cron correm à hora marcada. Guião e instruções em `scripts/simulacao/`.

## O ano em números

| | |
|---|---|
| Clientes registados | 4 179 (3 apagaram a conta) |
| Cozinhas | 4 (abertas nos dias 0, 60, 150 e 240; uma em pausa uma semana) |
| Pedidos | 71 468: 69 002 entregues, 2 338 cancelados (1 399 pelo cliente, 939 pela cozinha), 128 estornados |
| Faturado | 399,3 milhões Kz: dinheiro 282,5 M, Multicaixa Express 67,4 M, TPA 32,7 M, pacotes 14,3 M, saldo do Convida 2,4 M |
| Pedidos de grupo | 2 825 em 552 grupos |
| Pacotes | 468 adesões, 3 813 refeições usadas |
| Convida e Ganha | 3 024 ligações, 24 851 ganhos pagos ou confirmados (3,4 M Kz), 193 levantamentos pagos |
| Avaliações | 24 100 (média ≈ 4,2); 2 303 reclamações, todas respondidas menos as 16 dos últimos dias |
| Caixas | 859 fechadas; as 28 diferenças de caixa provocadas aparecem certas no fecho mensal |
| Comprovativos | 20 265 (217 rejeitados), todos conferidos antes de fechar a caixa |
| Notificações | 466 000 geradas e enviadas; 278 lembretes de avaliação descartados por validade |
| Stock | 313 796 consumos automáticos, 1 536 entradas |

Ao longo do ano houve também:
- todas as funcionalidades ligadas por fases;
- a subida do preço da muamba;
- a mudança do ganho do Convida (100 → 150 Kz, só nas ligações novas);
- doses do dia esgotadas, pratos montáveis com ingredientes tirados e atrasos avisados ao cliente;
- uma fraude montada com 6 contas falsas.

## Verificações — 26 de 26 certas

Dinheiro:
- as vendas de cada pedido batem com o valor final;
- os pagamentos somam o valor final;
- os estornos anulam as vendas;
- o esperado das 859 caixas está certo;
- o fecho de cada mês bate com as vendas ao kwanza e mostra exatamente as diferenças de caixa provocadas.

Convida e Ganha:
- nenhum saldo fica negativo;
- os ganhos só caem dentro do período e com o valor garantido, mesmo depois de mudar o parâmetro;
- os estornos anulam o ganho;
- o desconto do amigo só se aplica uma vez;
- ninguém levantou mais do que ganhou.

Pacotes:
- as refeições usadas batem com os pedidos;
- o cancelamento e o estorno devolvem a refeição.

Stock:
- há um consumo por venda;
- o que o cliente tirou não sai do stock;
- não há consumos repetidos.

Restantes:
- todas as notificações têm texto e nenhuma ficou esquecida;
- a taxa dos grupos divide-se certa e nenhum grupo ficou aberto;
- nunca se vendeu acima das doses do dia;
- todos os cancelamentos têm justificação;
- as contas apagadas ficaram anónimas;
- cada avaliação de 1 ou 2 estrelas abriu uma reclamação.

Privacidade: 30 clientes ao acaso, lidos como a app os lê, nunca viram pedidos, ganhos,
avaliações ou comprovativos de outros.

Falhas do servidor: nenhuma. As 7 recusas registadas são o servidor a recusar, bem, grupos numa
cozinha em pausa. A app nem mostra cozinhas em pausa; foi o guião que não verificou.

## O que a simulação encontrou

1. **Ecrãs lentos com o volume de um ano (urgente).** As regras de acesso (RLS) chamam
   `cliente_actual()`, `e_funcionario()` e `tem_permissao()` uma vez por linha da tabela. Com 71 mil
   pedidos, um cliente esperava 8,6 s para ver os seus pedidos. Envolvidas em `(select …)`, como a
   Supabase recomenda, a mesma leitura leva 0,04 s. Há 102 regras com este padrão.
2. **Relatório anual da cozinha: 12,8 s.** A retenção (voltou a pedir aos 30, 60 e 90 dias?)
   comparava cada cliente novo com todos os pedidos. Com o último pedido de cada cliente o resultado
   é igual e leva 0,19 s.
3. **Investigador financeiro demasiado sensível.** Um só comprovativo rejeitado abre um caso
   (3 pontos por rejeição, limite 3). Com 1 % de rejeições, 14 dos 18 funcionários teriam um caso
   todos os meses, o que dá trabalho e custo de Claude sem razão. Proposta: contar a taxa de
   rejeição em relação ao número de comprovativos.
4. **Fraude na mesma morada.**
   - As 3 contas falsas no mesmo telemóvel foram apanhadas logo: 73 ganhos anulados.
   - As 3 contas na mesma casa com telemóveis diferentes cabem no limite de 3 por morada e
     receberam 92 ganhos.
   - A vigilância do Convida apanha este caso (1 caso, pontuação 11, "6 no mesmo local"), mas só
     corre com o agente ligado.
5. **Tamanho da base de dados.**
   - Um ano a este ritmo ocupa 655 MB, sobretudo `notificacoes_fila` (180 MB), `auditoria` (157 MB)
     e `estoque_longo_prazo` (110 MB).
   - No plano gratuito da Supabase (500 MB), o limite chegaria por volta do 10.º mês.
   - Proposta: apagar notificações enviadas com mais de 90 dias e arquivar a auditoria antiga.

Tempos com o volume do ano, nesta base local (o relógio simulado torna-a mais lenta do que a
produção):

| Consulta | Tempo |
|---|---|
| Pedidos do operador | 1–4 ms |
| Orçamento do carrinho | 3 ms |
| Destaques do mês | 7 ms |
| Fecho diário / mensal | 54 / 193 ms |
| Painel do Convida do ano | 389 ms |
| Relatório comparativo do ano | 1,3 s |

## O que não foi testado

- Os agentes com Claude não foram chamados: sem chave e com custo. As tarefas criam os casos,
  os planos e as análises, que ficam à espera.
- O envio real das notificações push e as fotos (só os caminhos e as regras do armazenamento).
- As apps em si: os ecrãs têm os seus testes Jest; aqui exercitou-se o servidor como as apps o usam.

## Correcções (4 out. 2026)

| | Estado | Medido na base com um ano de dados |
|---|---|---|
| (a) Regras de acesso com `(select …)` (93 regras) | aplicada na produção | cliente vê os seus pedidos: 8,6 s → 0,05 s |
| (b) Retenção do relatório da cozinha | aplicada na produção | relatório do ano: 12,8 s → 0,19 s, resultado igual |
| (c) Investigador: rejeições pela taxa (tolerância de 2 %) | aplicada na produção | casos de agosto: 14 → 2 |
| (d) Limpeza diária (notificações > 90 dias, auditoria > 2 anos) | por aplicar | — |

Testes: 918/918 na base local. Na produção, com rollback:
- teste 52 (partes a, b e c): 7 de 7;
- regras de acesso (06): 29 de 29;
- tabelas base (22): 25 de 26. O que falha conta os administradores e encontra também o administrador real que já existe.
- investigador (42): 21 de 22. O que falha espera que o aviso N24 vá só para as duas pessoas das finanças do teste, e ele vai também para o administrador real.
