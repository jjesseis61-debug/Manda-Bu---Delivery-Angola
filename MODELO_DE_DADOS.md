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
| `pedidos` | **Criação pelo cliente (estado `pendente`); estado validado pelo servidor** | O ciclo de estados só avança; ganhos e descontos dependem dele |
| `locais_entrega` / `enderecos_cliente` / `perfil_destaques` / `preferencias_notificacao` | **Last-write-wins** com `atualizado_em` (o servidor ignora escritas mais antigas) | Dados do próprio cliente, raramente editados em simultâneo |
| `codigos_indicacao` / `ligacoes_indicacao` / `ganhos_indicacao` / `pagamentos_indicacao` | **Só o servidor escreve** (funções); o telemóvel só lê | O servidor calcula todos os valores do programa |
| `parametros` / `funcionalidades` / `cozinhas` | **Só o servidor / operador com permissão**; o telemóvel só lê | Configuração central, auditada |
| `avaliacoes` / `avaliacoes_pratos` / `fotos_avaliacao` | **Append-only**; moderação só por funções | Uma avaliação por pedido |
| `notificacoes_fila` / `contadores_zona` | **Só servidor**, não sincronizam para o telemóvel | Fila interna e cache |

## Entidades (campos próprios, além dos campos de sincronização)

### `produtos`
`nome`, `categoria`, `tipo_estoque` (Diário/Longo Prazo), `categoria_medida` (Peso/Volume/Unidade),
`unidade_compra`, `custo`, `margem`, `iva_aplicavel`, `iva`

### `pratos_base`
`nome`, `componentes` (lista de `{produto_id, quantidade, unidade}`)

### `vendas`
`pedido_id` (quando a venda resulta de um pedido da app), `cozinha_id`, `produto`, `qtd`, `valor_total`, `valor_antes_desconto`, `desconto_aplicado`, `local`, `parcelas`
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
`tipo` (Particular/Empresa), `nome`, `telefone`, `nif`, `pessoa_contacto`, `limite_credito`, `desconto`,
`auth_user_id` (utilizador autenticado do Supabase; usado por `cliente_actual()`)

### `pagamentos_credito`
`cliente_id`, `valor`, `origem` (pagamento normal / nota de crédito)

### `locais`
`nome` — ponto de venda / posto (não confundir com `locais_entrega`)

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
`nome`, `cargo`, `direcao_id`, `administrador_principal` (booleano), `permissoes_extra` (mapa de permissão → sim/não),
`auth_user_id` (utilizador autenticado; usado por `funcionario_actual()` e `tem_permissao()`)

### `direcoes`
`nome`, `permissoes` (mapa de permissão → sim/não)

### `refeicoes_funcionarios`
`funcionario_id`, `prato`, `valor_custo`, `valor_desconto`

### `turnos`
`funcionario_id`, `funcionario_nome`, `cargo`, `data`, `hora_inicio`, `hora_fim`, `cozinha_id`,
`periodo` (manha/tarde/noite — turno de cozinha, usado no reconhecimento de equipa)

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

## Programa de Crescimento (fase I1)

Especificação completa em `PROJECTO_CRESCIMENTO_MANDA_BUE.md`; SQL em
`supabase/migrations/20260930120100_crescimento_i1.sql`. Todas as tabelas abaixo têm os
campos de sincronização comuns. Valores monetários em kwanzas inteiros.

**Tabelas existentes que passam a ter `cozinha_id`** (preenchido com a Cozinha da Alexandra,
obrigatório, por defeito `cozinha_padrao()`): `pratos_base`, `turnos`, `caixa`,
`estoque_diario`, `estoque_longo_prazo`, `distribuicoes`, `vendas`, `pre_encomendas`,
`pedidos_especiais`.

**Programa antigo** (`indicacoes`, `recompensas_indicacao`, `config_indicacao`): mantido
intacto como legado; não é usado pelo Programa de Crescimento.

### `parametros` (registo único, `id = 1`)
Todos os valores do programa: ganhos, prazos, limites, anti-fraude, prova social, avaliações,
grupos e equipa. Nenhum valor fica fixo no código.

### `funcionalidades` (chave → `activa`)
Interruptores: `indicacao`, `destaques`, `pessoas_como_tu`, `contadores_zona`, `perfil_cozinha`,
`avaliacoes`, `avaliacoes_fotos`, `reconhecimento_equipa`, `pedidos_grupo`, `multi_cozinha`.
Todos desligados no fim de I1.

### `cozinhas`
`nome`, `responsavel`, `foto_url`, `historia`, `estado` (activa/pausada/inactiva), `consentimento_publico`

### `locais_entrega`
`tipo` (residencial/empresa), `lat`, `lng`, `zona_id` → `zonas`, `referencia`, `criado_por_cliente`

### `enderecos_cliente`
`cliente_id`, `local_id` → `locais_entrega`, `nome` (Casa/Trabalho), `principal`

### `pedidos`
`cliente_id`, `cozinha_id`, `local_id`, `estado` (pendente → confirmado → em_preparacao → em_entrega →
entregue_pago; cancelado; estornado), `itens`, `subtotal`, `taxa_entrega`, `desconto_indicacao`*,
`credito_indicacao_usado`*, `parcelas`, `observacoes`, `motivo_cancelamento`, `grupo_id`,
`hora_prometida`, `entregue_em`*, `pagador_distinto` (só entregador). *só o servidor escreve.

### `codigos_indicacao`
`cliente_id` (único), `codigo` (`MB-` + 4 dígitos), `nivel` (normal/embaixador), `ultima_partilha_em`

### `ligacoes_indicacao`
`indicado_id` (único), `indicador_id`, `ligado_em`, `primeiro_pedido_id`, `expira_em`, `desconto_usado`

### `ganhos_indicacao`
`pedido_id` (único), `indicador_id`, `indicado_id`, `valor`, `estado` (em_verificacao/confirmado/pago/anulado),
`motivo`, `nota_revisao`, `revisto_por`, `revisto_em`, `pagamento_id`, `confirmado_em`

### `pagamentos_indicacao`
`indicador_id`, `valor`, `tipo` (credito/levantamento), `metodo`, `numero_destino`, `pedido_id`,
`lote_id` (parcelas do mesmo levantamento), `parcela`, `total_parcelas`, `estado` (pedido/aprovado/pago/rejeitado),
`referencia`, `motivo_rejeicao`, `aprovado_por`, `pago_em`

### `perfil_destaques`
`cliente_id` (único), `pseudonimo`, `mostrar_nome_real`, `sair_da_lista`

### `preferencias_notificacao`
`cliente_id` (único), `lembrete_almoco` (N5), `destaques` (N7)

### `avaliacoes` / `avaliacoes_pratos` / `fotos_avaliacao` / `palavras_filtradas`
Avaliação por pedido (estrelas, comentário ≤ 200, `oculta`), estrelas por prato, fotos com moderação,
lista de palavras do filtro de comentários.

### `reconhecimentos_turno`
`cozinha_id`, `semana` (segunda-feira), `periodo`, `tipo`, `nota`, `criado_por` — sempre por turno, nunca por pessoa.

### `pedidos_grupo`
`organizador_id`, `empresa_id`, `local_id`, `cozinha_id`, `hora_entrega`, `prazo_adesao`, `modo_pagamento`,
`codigo_convite`, `estado`

### `notificacoes_fila` / `contadores_zona`
Fila de notificações push (lida por uma Edge Function) e cache horária de pedidos por zona.

## Índices recomendados (para consultas rápidas offline)

- `vendas(data)`, `vendas(cliente_id)`, `vendas(local)`
- `estoque_longo_prazo(produto_id, tipo, data)`
- `auditoria(data)`, `auditoria(ref_id)`
- `caixa(posto, data)`
- `pedidos(cliente_id, estado)`, `pedidos(local_id)`, `pedidos(estado, entregue_em)`, `pedidos(dispositivo_id)`
- `ganhos_indicacao(indicador_id, estado)`, `ganhos_indicacao(confirmado_em)`
- `pagamentos_indicacao(indicador_id, estado)`, `pagamentos_indicacao(numero_destino)`
- `ligacoes_indicacao(indicador_id)`, `locais_entrega(zona_id)`, `locais_entrega(lat, lng)`
