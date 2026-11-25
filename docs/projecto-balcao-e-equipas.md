# Balcão de panelas (fase 2) e Junta Bué no trabalho

> Estado: **análise aprovada para implementar no futuro** (25/11/2026). Nada disto está implementado.
> Imagens de referência em [`projecto-balcao-e-equipas/`](projecto-balcao-e-equipas/) (ilustrações, não ecrãs reais).
> Tudo passa pelas cinco lentes de [`especialistas.md`](especialistas.md) antes de se dar por terminado.

## 0. Pendentes urgentes (não esperar pelo projecto)

- **Sprite e Coca-Cola de Viana gastam 48 latas por prato.** Nas opções do grupo Bebida, o ingrediente
  ficou com quantidade 48 (devia ser 1): a app mostra «Resta 1» e a primeira venda entregue desconta 48
  latas do stock. Corrigir no operador (Editar → quantidade do ingrediente = 1) ou por SQL.
- **A conta fica tapada no ecrã do balcão** quando há bebida no tabuleiro: o tabuleiro fica largo demais e
  esconde o primeiro algarismo do total e o «N itens». Estreitar o tabuleiro ou pôr a conta por baixo.
- No operador, o campo da quantidade do ingrediente deve chamar-se «Quantidade gasta por prato».

## 1. Balcão de panelas: um recipiente próprio para cada comida

O que existe hoje (APK de 24/11, teste `teste_balcao_panelas`, grupo B): panela de metal (bases e
proteínas), panela de barro (feijão, muamba, calulu…), tigela (acompanhamentos), copo (sumo natural) e
lata (gasosa, água), escolhidos pelo nome do grupo e da opção (`apps/cliente/src/lib/balcaoPanelas.ts`).

**Problema** (imagem `06-balcao-hoje-batata-em-panela.jpg`): a batata frita aparece numa panela. Cada
comida tem de estar no recipiente em que se serve de verdade.

| Comida | Recipiente | No prato / tabuleiro |
|---|---|---|
| Arroz, funje, massa | panela de metal | zona da base |
| Batata frita, mandioca frita, banana frita | **cartucho ou cesto de batatas fritas** (papel às riscas) | zona da base ou do acompanhamento |
| Frango, peixe, carne grelhados | **travessa ou grelha** | zona da proteína |
| Feijão, muamba, calulu, kizaka | panela de barro | zona da proteína ou do acompanhamento |
| Salada | **saladeira** (tigela de vidro) | zona do acompanhamento |
| Sopa, caldo | **malga ou terrina** com tampa | ao lado do prato, no tabuleiro |
| Pão, broa | **cesto de pão** | ao lado do prato |
| Molhos, jindungo | **molheira** pequena | ao lado do prato |
| Sobremesa (pudim, mousse, cocada, gelado) | **taça de sobremesa** | **prato de sobremesa**, no tabuleiro |
| Fruta (banana, papaia, melancia, ananás) | **fruteira** ou prato de fruta cortada | **prato de sobremesa**, no tabuleiro |
| Sumo natural | copo | tabuleiro |
| Gasosa, água | lata ou garrafa | tabuleiro |

**Regras de desenho**
- O prato principal só leva base, proteína e acompanhamentos. Sopa, pão, molho, sobremesa, fruta e
  bebida ficam **à volta do prato, no tabuleiro**, cada um no seu recipiente pequeno.
- Passos pela ordem de uma refeição: base → proteína → acompanhamentos → sobremesa/fruta → bebida.
  Perguntas: «E de sobremesa?», «Uma fruta?», «E para beber?».
- Hoje o tipo é deduzido pelo nome. **Fase seguinte:** a cozinha escolhe no operador o recipiente de cada
  grupo, e opcionalmente de cada opção (coluna nova `recipiente` em `opcoes_grupos` e em `opcoes`), com a
  dedução pelo nome como valor por defeito.
- Os recipientes são desenhados na app (sem imagens novas para descarregar); a fotografia da comida
  aparece dentro do recipiente.
- Mudar o desenho a meio do teste mistura duas versões no grupo B: **recomeçar a contagem** do teste
  `balcao_panelas` quando esta fase sair.

**Lentes:** Rogers: o recipiente que se vê na cantina e em casa, nada a aprender. Bandura: um passo
de cada vez, pela ordem da refeição. Cialdini: coerência (nada de batata frita numa panela) dá confiança.
Prahalad: desenhado na app, sem gastar dados. Skinner: medir de novo com grupo de controlo.

## 2. O prato servido no ecrã «O teu pedido»

Imagem `02-prato-no-pedido.png`. Recomendada a **opção B**: em cada linha do pedido, o tabuleiro pequeno
(cerca de 88 px) à esquerda, com o prato com zonas e a bebida ao lado, o nome e a composição ao centro e
− 1 + à direita. Tocar no prato mostra a lista com os preços. A morada, a conta e o «Confirmar pedido»
ficam juntos e à vista. Rejeitadas: A (em cima e grande: o cliente tem de rolar para pagar) e C (entre a
morada e a conta: afasta a conta do botão). O prato com zonas passa a componente comum (balcão, pedido e
mais tarde o acompanhamento do pedido).

## 3. Junta Bué no trabalho (equipas de colegas)

Imagens `03-…`, `04-…` e `05-…`. Ponto de partida: os pedidos de grupo (`pedidos_grupo`, ligado), a
conta de empresa (fatura única à empresa), os pacotes pagos antes e o «pagar antes» com confirmação das
Finanças. **Não existe** hoje: grupo que se repete todos os dias, conta do mês por pessoa, responsável
com benefício.

### 3.1 Equipa fixa com responsável
- Um colega (a responsável) cria a equipa uma vez: local de trabalho, hora da entrega, prazo para pedir e
  dias da semana; junta os colegas pelo código MB-xxxx.
- Todos os dias úteis o grupo do dia abre sozinho; de manhã, cada um recebe «Vais almoçar hoje?».
  Quem não vem não pede. No prazo, o grupo fecha e sai uma só entrega.
- **Autorizações do colega** (pode retirá-las quando quiser): «a responsável pode pedir o meu almoço» e
  «a responsável pode ver a minha conta do mês».
- **Pedir em nome do colega:** a responsável vê quem ainda não pediu e pode pedir por ele (repetindo o
  prato habitual). O colega recebe logo «A Maria pediu o teu almoço» e pode trocar ou recusar até ao prazo.

### 3.2 Uma refeição por dia, com excepção aprovada pela cozinha
- Regra: **uma refeição por colega por dia**, quer seja ele a pedir quer seja a responsável.
- Excepção: «Pedir mais refeições hoje» (quantas e porquê, por exemplo visitas). A cozinha aprova tudo,
  só uma parte ou recusa, vendo as doses que lhe restam. Sem resposta até ao prazo, fica recusado.
  Vale só nesse dia, conta para as doses e vai para a conta do mês de quem pediu (o que passar do limite
  paga-se no dia).

### 3.3 Conta do mês de cada colega
- Cada almoço soma-se à conta de quem comeu; cada um vê a sua, dia a dia, com o limite mensal.
- No fim do mês paga **por referência** (Multicaixa Express, Unitel Money), confirmada pelas Finanças,
  ou **em dinheiro**, registado pela cozinha («Recebi em dinheiro…», com recibo e entrada na Caixa).
- Pode pagar o próprio colega ou a responsável em nome dele (sempre identificado; com dinheiro: «pago à
  Maria» → «entregue à cozinha»).
- Atraso: esse colega passa a pagar no dia; o grupo continua para os outros.
- Fatura: cada almoço tem a fatura do software certificado em nome do colega (venda a crédito); o
  pagamento do mês dá o recibo. **Confirmar com o contabilista** (regras da AGT).

### 3.4 Benefício da responsável (acordo por grupo)
- **Percentagem de cada prato pedido no grupo**, por escalão. O colega paga o preço normal (ex.: 7.000 Kz)
  e a fatura não muda; o benefício sai do que a cozinha recebe.
- Base: o prato com as opções, pelo valor pago; **sem a taxa de entrega**; bebidas por decidir.
- Escalões propostos: **3%** até 9 almoços por dia, **5%** de 10 a 14 e **10%** a partir de 15, pela média
  do mês anterior e fixos durante o mês. Arredondado ao kwanza, por prato.
- O benefício sobe todos os dias e **desbloqueia-se colega a colega**, quando cada um paga.
- **Quem paga o benefício** (escolha no acordo):
  - plataforma (comissão actual de 10%: aguenta cerca de 5%);
  - plataforma + cozinha (desconto de volume da cozinha);
  - **só a cozinha**: comissão da plataforma 0%, entrega 0 Kz (a cozinha leva ou os colegas levantam),
    pagamento em dinheiro. Só para equipas **trazidas pela cozinha** (origem guardada no acordo); as
    trazidas pela plataforma mantêm a comissão.
- Tecto por refeição no sistema; o acordo é criado por quem tem permissão de Finanças/comercial e
  **aceite pela cozinha**; tudo na auditoria. O relatório da cozinha mostra a linha «Benefício da equipa».
- **Duas contas separadas:** o benefício da equipa (almoços do grupo) e o ganha-ganha (Kambas) dos
  convidados de fora. **Cada pedido conta só num programa:** se é de um grupo com acordo, benefício da
  equipa; senão, ganha-ganha.

### 3.5 Lentes
- **Bandura:** metas próximas («faltam 3 colegas pagarem», «faltam 6 almoços por dia para os 5%»);
  a responsável comparada consigo própria.
- **Cialdini:** unidade entre colegas; o colega autoriza, é avisado e pode recusar; nada escondido no
  preço; o extracto de cada um é privado (só a responsável autorizada o vê).
- **Rogers:** é a vaquinha do almoço do escritório e a conta no fim do mês, agora com ferramentas;
  a responsável é a líder de opinião e embaixadora natural; três escalões fixos para ser simples.
- **Prahalad:** os colegas recebem ao mês e pagam ao mês; a responsável ganha um rendimento; o risco fica
  com quem conhece os colegas (como no microcrédito em grupo); o acordo tem de deixar ganho à cozinha,
  à plataforma e à responsável.
- **Skinner:** o benefício chega quando o colega paga (o comportamento certo); a regra de uma refeição por
  dia e os limites travam abusos; alertas no painel de vigilância (muitos pedidos em nome de outros, muitas
  recusas, cozinhas a passar clientes para acordos a 0%); piloto com uma equipa real e grupo de controlo.

### 3.6 Decisões que faltam
1. Bebidas contam para o benefício (e com que %)?
2. Limites dos escalões (9 / 10–14 / 15) e escalão pela média do mês anterior?
3. Tecto do custo total da cozinha quando a plataforma também cobra comissão (ex.: 20%)?
4. Limite mensal por colega (ex.: 40.000 Kz) e se começa mais baixo no primeiro mês.
5. Até que hora e até que valor a responsável pode pedir em nome do colega.
6. Pagamento do benefício: dinheiro (Finanças ou cozinha) ou desconto nos almoços dela.
7. «Só a cozinha» para sempre a 0% ou uma mensalidade pequena pela ferramenta.

## 4. Ordem de implementação sugerida

1. Pendentes urgentes (secção 0).
2. Recipientes próprios no balcão, incluindo sobremesa e fruta no tabuleiro, e recomeçar o teste.
3. Prato servido no ecrã «O teu pedido» (opção B).
4. Equipa fixa com responsável e grupo do dia automático.
5. Uma refeição por dia e pedido extra aprovado pela cozinha.
6. Pedido em nome do colega (autorização, aviso e recusa).
7. Conta do mês por colega: referência, dinheiro registado pela cozinha, recibo e atrasos.
8. Acordo por grupo, escalões, «só a cozinha», benefício que se desbloqueia e as duas contas da responsável.
9. Piloto com a equipa da colega que propôs a ideia.
