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
| `estoque_longo_prazo` — consumos de vendas `App cliente` | **Só o servidor** (`dispositivo_id = 'servidor'`, `venda_id` preenchido, único com `produto_id`); um consumo ou alteração vindo de um dispositivo para uma dessas vendas é descartado e registado na auditoria como bloqueado | A venda é gerada no servidor a partir do pedido e o servidor desconta o stock; um segundo desconto no dispositivo duplicaria o consumo |
| `auditoria` | **Append-only, imutável** | Nunca aceitar UPDATE nem DELETE vindo de nenhum dispositivo, nem do Administrador Principal |
| `distribuicoes` (stock → cozinha) | **Append-only para criação; last-write-wins só no campo de devolução/quebra** | A distribuição em si nunca muda; só o progresso de devolução é atualizado |
| `caixa` | **Last-write-wins por posto+data** | Só um dispositivo deve abrir/fechar o caixa de um posto por dia — improvável colisão real |
| `clientes` (nome, telefone, tipo) | **Last-write-wins** com `atualizado_em` | Dados cadastrais mudam raramente em simultâneo |
| `clientes.limite_credito` / `clientes.desconto` | **Last-write-wins, mas só o Administrador/Direção Financeira sincroniza este campo** | Evita que uma edição de outro posto sobrescreva sem intenção |
| `produtos` / `pratos_base` | **Last-write-wins** | Cadastro raramente editado em simultâneo por dois postos |
| `direcoes` / `funcionarios` (organograma) | **Last-write-wins, só sincronizado por Administrador Principal** | Organograma é gerido centralmente, não por posto |
| `pagamentos_credito` (incl. notas de crédito) | **Append-only** | Cada pagamento é um evento; saldo do cliente é sempre a soma de tudo |
| `pedidos` | **Criação pelo dispositivo (estado `pendente`); `estado` e campos de valor só no servidor** | O estado muda por `mudar_estado_pedido`/`cancelar_pedido`; a venda e os ganhos dependem dele |
| `pontos_entrega` / `enderecos_cliente` / `perfil_destaques` / `preferencias_notificacao` | **Last-write-wins** com `atualizado_em` (o servidor ignora escritas mais antigas) | Dados do próprio cliente, raramente editados em simultâneo |
| `codigos_indicacao` / `ligacoes_indicacao` / `ganhos_indicacao` / `pagamentos_indicacao` | **Só o servidor escreve** (funções); nunca entram na fila de saída do dispositivo | O servidor calcula todos os valores do programa |
| `parametros` / `funcionalidades` | **Só o servidor** (`alterar_parametros`, `alterar_funcionalidade`); o telemóvel só lê | Configuração central, auditada |
| `cozinhas` | **Last-write-wins**, escrita só com `cozinhas.gerir` | Cadastro central |
| `avaliacoes` / `avaliacoes_pratos` / `fotos_avaliacao` | **Append-only**; moderação só por funções | Uma avaliação por pedido |
| `palavras_filtradas` | **Last-write-wins**, só moderadores | Lista curta, gerida por uma pessoa |
| `reconhecimentos_turno` | **Append-only** | Cada reconhecimento é um evento |
| `pedidos_grupo` | **Append-only na criação; last-write-wins no estado** | Só o organizador ou o operador mudam o grupo |
| `notificacoes_fila` / `contadores_zona` | **Só servidor**, não sincronizam para o telemóvel | Fila interna e cache |
| `permissoes` | **Só servidor**; o telemóvel só lê | Catálogo central |
| `opcoes_grupos` / `opcoes` (I9) | **Last-write-wins**, escrita só com `cozinhas.gerir` | Opções dos pratos montáveis; o preço extra soma no servidor |
| `cozinhas_localizacao` (I10) | **Last-write-wins**, escrita só com `cozinhas.gerir` | Aos clientes só por `localizacao_cozinha()` e com autorização (`publica`) |
| `posicoes_entregadores` (I11) | **Só servidor**, não sincroniza | Última posição do estafeta, só durante entregas |

## Entidades (campos próprios, além dos campos de sincronização)

### `produtos`
`nome`, `categoria`, `tipo_estoque` (Diário/Longo Prazo), `categoria_medida` (Peso/Volume/Unidade),
`unidade_compra`, `custo`, `margem`, `iva_aplicavel`, `iva`

### `pratos_base`
`nome`, `componentes` (lista de `{produto_id, quantidade, unidade}`)

### `vendas`
`pedido_id`, `linha_pedido` (quando a venda resulta de um pedido da app; único com `origem`), `caixa_id`,
`movimenta_stock` (false nas vendas de compensação), `stock_consumido_por` (`dispositivo` por defeito; `servidor` nas vendas geradas de pedidos — quem desconta o stock), `cozinha_id`, `produto`, `qtd`, `valor_total`, `valor_antes_desconto`, `desconto_aplicado`, `local`, `parcelas`
(lista de `{metodo, valor, cliente_id, titular}`), `credito`, `cliente_id`, `entrega`, `zona_nome`,
`tipo_entrega`, `taxa_entrega`, `prato_base_id`, `componentes_excluidos`, `componentes_ajustados`,
`registado_por`, `aprovado_por`, `entregue_por`, `origem` (Venda direta / Pré-encomenda / Pedido especial)

### `estoque_diario` (movimentos)
`produto`, `qtd_comprada`, `custo_total`, `data`

### `estoque_longo_prazo` (movimentos)
`produto_id`, `tipo` (Entrada/Consumo), `quantidade` (sempre em unidade base — grama/ml/unidade),
`custo_total`, `fornecedor`, `validade`, `venda_id` (venda que originou o consumo; único com `produto_id` quando preenchido)

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
`nome` — ponto de venda / posto (não confundir com `pontos_entrega`)

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

### `permissoes` (catálogo, só o servidor escreve)
`chave` (única), `grupo`, `descricao`. Lista as permissões que podem ser atribuídas em `direcoes.permissoes` e
`funcionarios.permissoes_extra`: `indicacoes.ver`, `indicacoes.verificar`, `indicacoes.aprovar_pagamentos`,
`plataforma.parametros`, `avaliacoes.moderar`, `cozinhas.gerir`, `equipa.reconhecer`, `relatorios.exportar`,
`pedidos.gerir`, `entregas.registar`, `vendas.registar`, `stock.gerir`, `financas.gerir`, `clientes.gerir`,
`equipa.gerir`, `auditoria.ver`.

### `refeicoes_funcionarios`
`funcionario_id`, `prato`, `valor_custo`, `valor_desconto`

### `turnos`
`funcionario_id`, `funcionario_nome`, `cargo`, `data`, `hora_inicio`, `hora_fim`, `cozinha_id`,
`periodo` (manha/tarde/noite — turno de cozinha, usado no reconhecimento de equipa)

### `distribuicoes`
`produto_id`, `quantidade`, `unidade`, `descricao`, `origem`, `destino`, `entregue_por`, `status`,
`recebido_por`, `hora_recebimento`, `quantidade_devolvida`, `historico_devolucoes`,
`quantidade_quebra`, `historico_quebras`

### Programa de indicação antigo — substituído
`indicacoes`, `recompensas_indicacao` e `config_indicacao` foram **substituídas** pelo Programa de Crescimento
(`codigos_indicacao`, `ligacoes_indicacao`, `ganhos_indicacao`, …) e não são criadas.

### `auditoria`
`funcionario_id`, `funcionario_nome`, `acao`, `detalhe`, `ref_id` (liga ao registo a que se refere),
`ref_tipo`, `bloqueado` (booleano — tentativa bloqueada)

## Programa de Crescimento (fase I1)

Especificação completa em `PROJECTO_CRESCIMENTO_MANDA_BUE.md`; SQL em `supabase/migrations/`
(`…_crescimento_i1.sql`, `…_crescimento_i1_ajustes.sql`, `…_crescimento_i1_endurecimento.sql`).
Todas as tabelas abaixo têm os 6 campos de sincronização comuns — incluindo `parametros` e
`funcionalidades` — e a estratégia de conflito da tabela no início deste documento (também registada em
cada tabela com `comment on table`). Valores monetários em kwanzas inteiros.

**Tabelas existentes que passam a ter `cozinha_id`** (preenchido com a Cozinha da Alexandra,
obrigatório, por defeito `cozinha_padrao()`): `pratos_base`, `turnos`, `caixa`,
`estoque_diario`, `estoque_longo_prazo`, `distribuicoes`, `vendas`, `pre_encomendas`,
`pedidos_especiais`.

**Programa antigo** (`indicacoes`, `recompensas_indicacao`, `config_indicacao`): substituído; não é criado.

**Esquema base.** `supabase/migrations/20260930165537_modelo_base.sql` cria todas as tabelas acima, com os 6 campos
de sincronização, os índices recomendados e RLS activo (fechado por defeito).

### `parametros` (registo único: `unico = true`)
Todos os valores do programa: ganhos, prazos, limites, anti-fraude, prova social, avaliações,
grupos e equipa. Nenhum valor fica fixo no código.

### `funcionalidades` (`chave` única → `activa`)
Interruptores: `indicacao`, `destaques`, `pessoas_como_tu`, `contadores_zona`, `perfil_cozinha`,
`avaliacoes`, `avaliacoes_fotos`, `reconhecimento_equipa`, `pedidos_grupo`, `multi_cozinha`.
Todos desligados no fim de I1.

### `cozinhas`
`nome`, `responsavel`, `foto_url`, `historia`, `estado` (activa/pausada/inactiva), `consentimento_publico`

### `pontos_entrega`
`tipo` (residencial/empresa), `lat`, `lng`, `zona_id` → `zonas`, `referencia`, `criado_por_cliente`

### `enderecos_cliente`
`cliente_id`, `ponto_entrega_id` → `pontos_entrega`, `nome` (Casa/Trabalho), `principal`

### `pedidos` (pedidos da app do cliente; tabela do esquema base)
`cliente_id`, `zona_id`, `estado` (pendente → confirmado → em_preparacao → em_entrega → entregue_pago; cancelado;
estornado), `itens`, `subtotal`, `taxa_entrega`, `parcelas`, `observacoes`, `motivo_cancelamento`, `hora_prometida`,
`entregue_em`*; do programa: `cozinha_id`, `ponto_entrega_id`, `desconto_indicacao`*, `credito_indicacao_usado`*,
`grupo_id`, `pagador_distinto`*, `caixa_id`* (caixa onde o dinheiro entrou; obrigatória em `entregue_pago`).
*só o servidor escreve; o `estado` também.
Ao chegar a `entregue_pago`, o servidor gera **uma venda por item** (origem `App cliente`, `pedido_id`,
`linha_pedido`); a taxa fica na primeira venda, desconto e parcelas repartidos proporcionalmente (arredondamento na
última), soma = valor final. Um estorno gera, por venda, a compensação `App cliente (estorno)` com valores negativos,
`qtd = 0` e `movimenta_stock = false` (não repõe stock).

### `codigos_indicacao`
`cliente_id` (único), `codigo` (`MB-` + 4 dígitos), `nivel` (normal/embaixador), `ultima_partilha_em`

### `ligacoes_indicacao`
`indicado_id` (único), `indicador_id`, `ligado_em`, `primeiro_pedido_id`, `expira_em`, `desconto_usado`,
`ganho_por_pedido_garantido`, `desconto_garantido`, `duracao_dias_garantida` (copiados de `parametros` na ligação;
mudar os parâmetros só afecta novas ligações)

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
`organizador_id`, `empresa_id`, `ponto_entrega_id`, `cozinha_id`, `hora_entrega`, `prazo_adesao`, `modo_pagamento`,
`codigo_convite`, `estado`

### `notificacoes_fila` / `contadores_zona`
Fila de notificações push (lida por uma Edge Function) e cache horária de pedidos por zona.

## Índices recomendados (para consultas rápidas offline)

- `vendas(data)`, `vendas(cliente_id)`, `vendas(local)`
- `estoque_longo_prazo(produto_id, tipo, data)`
- `auditoria(data)`, `auditoria(ref_id)`
- `caixa(posto, data)`
- `pedidos(cliente_id, estado)`, `pedidos(ponto_entrega_id)`, `pedidos(estado, entregue_em)`, `pedidos(dispositivo_id)`
- `ganhos_indicacao(indicador_id, estado)`, `ganhos_indicacao(confirmado_em)`
- `pagamentos_indicacao(indicador_id, estado)`, `pagamentos_indicacao(numero_destino)`
- `ligacoes_indicacao(indicador_id)`, `pontos_entrega(zona_id)`, `pontos_entrega(lat, lng)`
- Todas as chaves estrangeiras têm índice (migração de endurecimento)
