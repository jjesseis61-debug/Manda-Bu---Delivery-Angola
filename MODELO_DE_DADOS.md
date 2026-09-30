# Modelo de Dados — com Sincronização

## Campos de sincronização comuns a TODAS as tabelas

Além dos campos próprios de cada entidade (listados abaixo), toda tabela deve ter:

| Campo | Tipo | Função |
|---|---|---|
| `id` | UUID (gerado no dispositivo) | Identificador único global — nunca um número sequencial, para evitar colisão entre dispositivos offline |
| `dispositivo_id` | texto | Qual dispositivo criou este registo |
| `criado_em` | timestamp | Quando foi criado (hora do dispositivo) |
| `atualizado_em` | timestamp | Última alteração (hora do dispositivo) — usado para resolver conflitos |
| `sincronizado_em` | timestamp, nulo até sincronizar | Preenchido pelo servidor quando confirma receção |
| `deletado_em` | timestamp, nulo | Soft-delete — nunca apagar fisicamente um registo já sincronizado |

## Estratégia de conflito por entidade

| Entidade | Estratégia | Porquê |
|---|---|---|
| `vendas` | **Append-only** | Nunca se edita uma venda passada; cada venda é um evento novo, soma-se tudo depois |
| `estoque_diario` / `estoque_longo_prazo` (movimentos) | **Append-only** | Cada entrada/consumo é um evento; o saldo é sempre calculado, nunca guardado como valor fixo |
| `auditoria` | **Append-only, imutável** | Nunca aceitar UPDATE nem DELETE vindo de nenhum dispositivo, nem do Administrador Principal |
| `distribuicoes` (stock → cozinha) | **Append-only para criação; last-write-wins só no campo de devolução/quebra** | A distribuição em si nunca muda; só o progresso de devolução é atualizado |
| `caixa` | **Last-write-wins por posto+data** | Só um dispositivo deve abrir/fechar o caixa de um posto por dia — improvável colisão real |
| `clientes` (nome, telefone, tipo) | **Last-write-wins** com `atualizado_em` | Dados cadastrais mudam raramente em simultâneo |
| `clientes.limite_credito` / `clientes.desconto` | **Last-write-wins, mas só o Administrador/Direção Financeira sincroniza este campo** | Evita que uma edição de outro posto sobrescreva sem intenção |
| `produtos` / `pratos_base` | **Last-write-wins** | Cadastro raramente editado em simultâneo por dois postos |
| `direcoes` / `funcionarios` (organograma) | **Last-write-wins, só sincronizado por Administrador Principal** | Organograma é gerido centralmente, não por posto |
| `pagamentos_credito` (incl. notas de crédito) | **Append-only** | Cada pagamento é um evento; saldo do cliente é sempre a soma de tudo |
| `indicacoes` / `recompensas_indicacao` | **Append-only para criação; last-write-wins no campo `status`** | Confirmação de indicação é uma transição de estado, rara colisão |

## Entidades (campos próprios, além dos campos de sincronização)

### `produtos`
`nome`, `categoria`, `tipo_estoque` (Diário/Longo Prazo), `categoria_medida` (Peso/Volume/Unidade),
`unidade_compra`, `custo`, `margem`, `iva_aplicavel`, `iva`

### `pratos_base`
`nome`, `componentes` (lista de `{produto_id, quantidade, unidade}`)

### `vendas`
`produto`, `qtd`, `valor_total`, `valor_antes_desconto`, `desconto_aplicado`, `local`, `parcelas`
(lista de `{metodo, valor, cliente_id, titular}`), `credito`, `cliente_id`, `entrega`, `zona_nome`,
`tipo_entrega`, `taxa_entrega`, `prato_base_id`, `componentes_excluidos`, `componentes_ajustados`,
`registado_por`, `aprovado_por`, `entregue_por`, `origem` (Venda direta / Pré-encomenda / Pedido especial)

### `estoque_diario` (movimentos)
`produto`, `qtd_comprada`, `custo_total`, `data`

### `estoque_longo_prazo` (movimentos)
`produto_id`, `tipo` (Entrada/Consumo), `quantidade` (sempre em unidade base — grama/ml/unidade),
`custo_total`, `fornecedor`, `validade`

### `custos`
`categoria`, `descricao`, `valor`, `data`

### `caixa`
`posto`, `troco_inicial`, `fechamento`, `sangrias` (lista), `funcionario_id`, `funcionario_nome`

### `clientes`
`tipo` (Particular/Empresa), `nome`, `telefone`, `nif`, `pessoa_contacto`, `limite_credito`, `desconto`

### `pagamentos_credito`
`cliente_id`, `valor`, `origem` (pagamento normal / nota de crédito)

### `locais`
`nome`

### `zonas`
`nome`, `taxa`, `tipo` (Própria/Terceirizada), `modo_calculo` (Fixo/Distância — visível só a Administrador),
`tarifa_por_km`

### `pre_encomendas`
`cliente_id`, `produto`, `qtd`, `valor`, `hora_prevista`, `forma_pagamento`, `status`, `motivo`,
`registado_por`, `entregue_por`, `cancelado_por`

### `pedidos_especiais`
`cliente_id`, `cliente_nome`, `descricao`, `valor`, `forma_pagamento`, `status`, `motivo`,
`registado_por`, `aprovado_por`, `recusado_por`, `cancelado_por`, `entregue_por`

### `funcionarios`
`nome`, `cargo`, `direcao_id`, `administrador_principal` (booleano), `permissoes_extra` (mapa de permissão → sim/não)

### `direcoes`
`nome`, `permissoes` (mapa de permissão → sim/não)

### `refeicoes_funcionarios`
`funcionario_id`, `prato`, `valor_custo`, `valor_desconto`

### `turnos`
`funcionario_id`, `funcionario_nome`, `cargo`, `data`, `hora_inicio`, `hora_fim`

### `distribuicoes`
`produto_id`, `quantidade`, `unidade`, `descricao`, `origem`, `destino`, `entregue_por`, `status`,
`recebido_por`, `hora_recebimento`, `quantidade_devolvida`, `historico_devolucoes`,
`quantidade_quebra`, `historico_quebras`

### `indicacoes`
`cliente_indicador_id`, `nome_indicado`, `telefone_indicado`, `status`, `cliente_indicado_id`,
`confirmado_por`, `data_confirmacao`

### `recompensas_indicacao`
`cliente_id`, `tipo`, `descricao`, `valor_desconto`, `usado`

### `config_indicacao` (registo único, sem lista)
`numero_necessario`, `tipo_recompensa`, `descricao_recompensa`, `valor_desconto`

### `auditoria`
`funcionario_id`, `funcionario_nome`, `acao`, `detalhe`, `ref_id` (liga ao registo a que se refere),
`ref_tipo`, `bloqueado` (booleano — tentativa bloqueada)

## Índices recomendados (para consultas rápidas offline)

- `vendas(data)`, `vendas(cliente_id)`, `vendas(local)`
- `estoque_longo_prazo(produto_id, tipo, data)`
- `auditoria(data)`, `auditoria(ref_id)`
- `caixa(posto, data)`
