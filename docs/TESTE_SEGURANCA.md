# Teste de segurança (ataque simulado)

Um atacante a tentar furar a aplicação, contra a base **local** de simulação (um ano de dados:
4.179 clientes, 71.468 pedidos), nunca contra a produção. Cada tentativa corre com o papel e a
sessão que o atacante teria — anónimo (chave pública), cliente autenticado ou funcionário — e passa
pelas mesmas regras de acesso (RLS) da Supabase. Guião: `scripts/simulacao/ataque.py`. Cada
tentativa corre numa transacção desfeita no fim: não altera nada.

## Resultado: 66 de 66 tentativas tratadas como deviam

| # | O que o atacante tentou | Resultado |
|---|---|---|
| 1 | **Anónimo lê 21 tabelas** (clientes, pedidos, ganhos, comprovativos, vendas, caixa, auditoria, notificações, segredos…) | Travado: sem permissão em todas |
| 2 | **Anónimo chama 10 funções** (registar_cliente, meu_perfil, funções de serviço, tarefas do cron, registar_auditoria) | Travado: sem permissão em todas |
| 3 | **Cliente lê dados de outro cliente** (pedidos, ganhos, endereços, saldo, avaliações, conversas, lista de clientes, justificação de cancelamento) | Travado: 0 linhas; a justificação devolve NULL a quem não é o dono |
| 4 | **Cliente escreve o que não é dele** (cancelar pedido de outro, usar o saldo de outro, dar-se desconto, marcar o pedido como pago, baixar o subtotal, inventar ganhos, marcar levantamentos como pagos, subir o limite de crédito, pôr-se embaixador, tornar-se funcionário, mudar parâmetros e interruptores, ler a fila de notificações) | Travado: erro ou 0 linhas em todas |
| 5 | **Funcionário (só entregas) excede permissões** (mudar preços, parâmetros, interruptores; promover-se a administrador; aprovar levantamentos; ler custos; abrir investigações; apagar vendas) | Travado em todas |
| 6 | **Fraude e integridade** (forjar uma venda "App cliente", apagar ou alterar a auditoria, apagar a auditoria fingindo-se de serviço) | Travado em todas |
| 7 | **Injeção e abuso** (SQL no código de indicação, valor negativo no levantamento, cardápio inexistente no orçamento) | O SQL fica texto inofensivo (a tabela `pedidos` continua lá); os valores inválidos são recusados |

Porque é que tantas escritas são travadas "sem erro": as regras de acesso filtram a linha e o
`update`/`delete` mexe em **zero** linhas, sem erro mas sem efeito. O guião confirma o efeito real
(linhas mexidas, valor depois), não só a ausência de erro.

## Postura da produção (confirmada só com leituras do catálogo, sem ataques)

- As 64 tabelas têm RLS ligado; **nenhuma** tabela sem RLS.
- O anónimo não lê nenhuma tabela de dados: mesmo as 5 com concessão ao anónimo (cardápio, opções,
  grupos de opções, pacotes, localização das cozinhas) não têm política de leitura para o anónimo,
  por isso devolvem 0 linhas. A concessão é um resto inofensivo — convém removê-la, por arrumação.
- O anónimo não chama as funções sensíveis.

## Um apontamento encontrado e CORRIGIDO (risco baixo)

**`justificacao_cancelamento` devolve a justificação quando não há cliente na sessão.** O bloqueio é
`if cliente_actual() is not null and cliente_actual() <> dono then return null`. Quando
`cliente_actual()` é nulo — uma sessão autenticada **sem** perfil de cliente (um telemóvel acabado
de autenticar, ou um funcionário) — o bloqueio não dispara e a função devolve a justificação de
qualquer pedido (o nome do prato e se o saldo ou o pacote foram devolvidos).

- **Porque é baixo:** o id do pedido é um UUID aleatório (não se adivinha); o conteúdo é brando (sem
  valores, nomes, morada ou telefone); e um funcionário já vê os pedidos por outras vias.
- **Um cliente autenticado a sério não consegue** ler a justificação de outro: aí `cliente_actual()`
  é o próprio e o bloqueio dispara (verificado).
- **Corrigido** (migração `20261004123008_justificacao_so_dono.sql`, aplicada na produção e verificada): bloqueia-se qualquer sessão autenticada que não seja o dono, deixando passar
  só o envio das notificações (que corre como serviço, não como `authenticated`):
  ```sql
  if cliente_actual() is distinct from p.cliente_id
     and coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '') = 'authenticated'
  then return null; end if;
  ```

## O que não foi coberto

- Ataques à infraestrutura (a própria Supabase, a rede, a autenticação por SMS), que são da
  plataforma, não da base de dados.
- As apps em si (o teste é ao servidor, que é onde as regras de acesso decidem tudo).
