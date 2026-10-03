# Base de dados — Manda Bué — Delivery Angola

## Migrações

Aplicadas por esta ordem. **Uma migração já aplicada nunca se edita:** qualquer alteração é uma migração nova.

| Ficheiro | Conteúdo | Projecto de desenvolvimento `laruvuambdovnkojwrzp` |
|---|---|---|
| `20260930165537_modelo_base.sql` | Tabelas do `MODELO_DE_DADOS.md`, incluindo `pedidos` (pedidos da app). 6 campos de sincronização, índices recomendados, RLS activo e fechado por defeito. Não cria o programa de indicação antigo. | aplicada |
| `20260930173725_crescimento_i1.sql` | Programa de Crescimento, fase I1: modelo (secção 5), Cozinha da Alexandra, funções e triggers (6), vistas (7), RLS e permissões (8), fila de notificações, jobs. | aplicada |
| `20260930173922_crescimento_i1_ajustes.sql` | `pontos_entrega`/`ponto_entrega_id`; estado do pedido só no servidor; venda gerada em `entregue_pago`; 6 campos de sincronização em `parametros` e `funcionalidades`; escrita só pelo servidor; valores garantidos na ligação. | aplicada |
| `20260930183237_crescimento_i1_decisoes.sql` | `duracao_dias_garantida`; uma venda por item (taxa na 1.ª, desconto e parcelas proporcionais, soma = valor final — regra 7); caixa obrigatória em `entregue_pago` e registada na venda (regra 8); estorno sem reposição de stock (regra 3); catálogo `permissoes`. | aplicada |
| `20261001040216_crescimento_i1_endurecimento.sql` | Correcções aos avisos do Supabase: `search_path` fixo, funções de trigger não expostas, índices nas chaves estrangeiras, nome do índice de `vendas.local`. | aplicada |
| `20261001041532_crescimento_i1_consumo_stock.sql` | Regra 3 (consumo): o servidor desconta o stock só das vendas que gera de pedidos (`vendas.stock_consumido_por`); itens do pedido validados (`prato_base_id` existente); componentes excluídos/ajustados; conversão para a unidade base; só produtos `Longo Prazo`; índice único `estoque_longo_prazo (venda_id, produto_id) where venda_id is not null`; guarda (regra 10): consumo de dispositivo para venda `App cliente` descartado e auditado como bloqueado; avisos `stock_consumo_pendente`. | aplicada |
| `20261001043509_crescimento_i1_privilegios.sql` | Guarda do consumo de stock passa a SECURITY DEFINER (um trigger SECURITY INVOKER anterior marca as sessões do telemóvel); `origem_venda`, `auditar_consumo_bloqueado` e `gerar_codigo_grupo` deixam de ser chamáveis pelas apps. | aplicada |
| `20261001052041_crescimento_i2_app_cliente.sql` | I2: `registar_cliente`/`meu_perfil` (registo pelo telefone confirmado por SMS; liga clientes do balcão); `cardapio` (preço, disponível, prato do dia) e preço dos pedidos da app calculado no servidor (`orcamento_pedido`, `trg_pedidos_00_cardapio`); `meus_amigos`; `dispositivos_push` e tokens Expo; textos N2/N3/N4/N8 e funções do serviço de envio (só `service_role`). | aplicada |
| `20261001052738_crescimento_i2_desconto_limite.sql` | O desconto de indicação nunca passa o valor do pedido (subtotal + taxa): valor final nunca negativo, no pedido e no orçamento. Uso único (o que sobra não passa para o pedido seguinte). | aplicada |
| `20261001091617_crescimento_i3_app_operador.sql` | I3: `funcionarios.telefone` e entrada por SMS (`definir_telefone_funcionario`, `ligar_funcionario`, `meu_funcionario`); leituras do operador com permissão do organograma: `painel_programa` (O1), `ganhos_em_verificacao` e `confirmar_ganhos_indicador` (O2), `levantamentos_operador` (O3), `embaixadores` (O4), `pedidos_operador` (E1); RLS de leitura em `caixa`; N3 vinda da verificação com o nome do amigo e o saldo da semana; auditoria das escritas em `cozinhas` e `cardapio` (O6). | aplicada |
| `20261001144534_crescimento_i4_lancamento.sql` | I4: C5 "Não mostrar os meus ganhos" (`perfil_destaques.ocultar_ganhos`; valores escondidos para os outros em `destaques_mes`); N5 com o prato do dia; textos de N5, N6 e N7 e envio pela Edge Function, respeitando no envio as preferências do cliente. Não liga interruptores. | aplicada |
| `20261001155248_crescimento_i5_avaliacoes_equipa.sql` | I5: avaliações lidas pelos clientes só pelas suas linhas; lista pública e médias por funções sem ids (`avaliacoes_publicas`, `medias_avaliacoes`); estrelas por prato só de pratos do pedido; O7 (`avaliacoes_moderacao`); N9 (`job_n9_avaliacao`, de 15 em 15 minutos); N12 e push para funcionários (`notificacoes_fila.funcionario_id`, `dispositivos_push.funcionario_id`, `registar_token_push_funcionario`, nova `notificacoes_por_enviar` com o destino, usada pela Edge Function; `notificacoes_pendentes` fica sem uso); `meu_funcionario().cozinhas_equipa`. Sem `drop`: a política muda com `alter policy`. | aplicada |
| `20261001161430_crescimento_i6_pedidos_grupo.sql` | I6: criar grupo validado no servidor (local de trabalho do próprio cliente, prazo e hora, modo empresa só para clientes Empresa; a app não altera grupos); pedido no grupo com o ponto e a zona do grupo e a taxa a 0 até ao fecho (`orcamento_pedido` devolve a estimativa); fecho pelo prazo (`job_grupos`, de 5 em 5 minutos), pelo organizador ou pelo operador, com a taxa da zona repartida (`regra_taxa_grupo`) ou toda no pedido da empresa; `cancelar_grupo`; N10 com hora e código, N11; `grupo_detalhe`, `meus_grupos`; O10 (`grupos_operador`, `mudar_estado_grupo`); o grupo acompanha o estado dos pedidos. | aplicada |
| `20261001162633_crescimento_i7_fotos_avaliacoes.sql` | I7: bucket privado `fotos-avaliacoes` (só JPEG, até 5 MB); o servidor define o caminho de cada foto (`<id>.jpg`); políticas do storage: envia só o autor, para uma foto sua pendente, com `avaliacoes_fotos` ligado; lê quem pode ver a foto (aprovada e avaliação visível, o próprio, moderadores); até 2 fotos por avaliação; `lista_avaliacoes` (lista pública com as fotos aprovadas) e `fotos_pendentes` (O7). | aplicada |
| `20261001165139_crescimento_i8_rede_cozinhas.sql` | I8: `cozinhas_para_pedir` (selector do cliente: cozinhas activas, a por defeito primeiro; perfil só com consentimento); o pedido é da cozinha escolhida ou da do grupo e tem de ser de uma cozinha activa (`cozinha_aceita_pedidos`, erro `cozinha_indisponivel`); grupo pode ser criado noutra cozinha; `relatorio_comparativo` (pedidos, vendas, ticket médio, cancelados, clientes, novos, por indicação, entregas a horas, avaliações por cozinha); O10 e `grupo_detalhe` com a cozinha. | aplicada |
| `20261001184650_crescimento_rls_tabelas_base.sql` | Políticas RLS das 16 tabelas base (vendas, stock, caixa, clientes, custos, organograma, turnos, …) por permissão do organograma e por cozinha (`pode_na_cozinha`: permissão + turno na cozinha, ou `cozinhas.gerir`); 6 permissões novas no catálogo (`vendas.registar`, `stock.gerir`, `financas.gerir`, `clientes.gerir`, `equipa.gerir`, `auditoria.ver`); append-only sem UPDATE; vendas `App cliente` só do servidor; distribuições só mudam recebimento/devolução/quebra; limite de crédito e desconto dos clientes só com `financas.gerir` e ligação à conta só pelo servidor (`clientes_proteger_campos`); organograma escrito só pelo administrador principal (`e_administrador`). Clientes continuam sem acesso directo. | aplicada |
| `20261002054644_notificacoes_validade.sql` | Validade das notificações (`notificacao_valida`): N5 2 horas, N10/N11 3 horas, N7/N9 24 horas, N6 48 horas, as outras 7 dias. `notificacoes_por_enviar` ignora as expiradas e `descartar_notificacoes_expiradas` tira-as da fila; `agendar_jobs()` passa a agendar essa limpeza (03h30 UTC). | aplicada |
| `20261002055313_apagar_conta.sql` | `apagar_conta()` para a app do cliente: apaga nome, telefone, NIF, contacto, endereços, telemóveis de push, notificações por enviar e o utilizador da Auth; pedidos, vendas e pagamentos ficam com "Cliente removido". Recusa com pedido, levantamento ou grupo a meio. | aplicada |
| `20261002064709_crescimento_i9_pratos_montaveis.sql` | I9: pratos montáveis. `opcoes_grupos` (mínimo e máximo por grupo) e `opcoes` (preço extra, disponível); `opcoes_do_item` valida as escolhas; `orcamento_pedido` soma os extras e põe as opções no nome do item (a cozinha, a entrega e a venda mostram-nas). Interruptor `pratos_montaveis`. As opções ainda não descontam stock. | aplicada |
| `20261002064729_crescimento_i10_como_chegar.sql` | I10: `cozinhas_localizacao` (morada, horário, ponto, `publica`), lida pela equipa e escrita com `cozinhas.gerir`; `localizacao_cozinha()` para o cliente, só pública, com a cozinha activa e o interruptor `como_chegar`. | aplicada |
| `20261002064759_crescimento_i11_acompanhamento_entrega.sql` | I11: `pedidos.entregador_id` (quem marca a caminho); `posicoes_entregadores` (só servidor, última posição, apagada quando o estafeta já não tem pedidos a caminho); `registar_posicao_entrega` (estafeta) e `posicao_entrega` (cliente, só o seu pedido, posição com menos de 10 minutos, distância e tempo estimado). Interruptor `acompanhamento_entrega`. | aplicada |
| `20261002074833_crescimento_i12_pacotes.sql` | I12: pacotes mensais pré-pagos. `pacotes` (catálogo, escrita com `pacotes.gerir`) e `adesoes_pacote` (só servidor, condições copiadas na adesão); `pedidos.pago_pacote`/`refeicoes_pacote`; `aderir_pacote`, `cancelar_adesao_pacote`, `usar_pacote`, `pausar_pacote`, `meu_pacote`, `pacotes_a_minha_volta` (prova social a partir de `contador_minimo`); `confirmar_pagamento_pacote`, `reembolsar_pacote`, `adesoes_operador`. Parcela "Pacote" nas vendas; as refeições voltam ao pacote se o pedido for cancelado; o saldo do Convida e Ganha não passa o que falta pagar depois do pacote. Interruptor `pacotes`. | aplicada |
| `20261002081819_crescimento_i12_avisos_pacotes.sql` | I12: avisos dos pacotes. N13 (pagamento confirmado), N14 (restam 3 refeições ou menos; e 3 dias antes do fim, pelo job diário `job_n14_pacotes`, agendado em `agendar_jobs` às 8h UTC) e N15 (nova adesão, à equipa com `pacotes.gerir`, via `funcionarios_com_permissao`). Só com o interruptor `pacotes`. | aplicada |
| `20261002083722_crescimento_i9_opcoes_stock.sql` | I9: `opcoes.componentes` (ingredientes de cada opção, por unidade do prato); `consumir_stock_venda` junta-os à receita do prato na venda gerada do pedido (o mesmo produto soma-se; mesmas regras de conversão e de avisos; um ingrediente mal escrito não trava a entrega). | aplicada |
| `20261002165956_fotos_pratos.sql` | Fotos dos pratos e das cozinhas: bucket público `fotos-pratos` (até 5 MB, JPEG/PNG/WebP); só `cozinhas.gerir` envia, troca ou apaga, e só em `pratos/<id do prato>/…` ou `cozinhas/<id da cozinha>/…`. O endereço público fica em `cardapio.foto_url` / `cozinhas.foto_url`. | aplicada |
| `20261003060218_zonas_gestao.sql` | Zonas de entrega geridas pela app do operador: `plataforma.parametros` cria, edita e apaga zonas (com auditoria); um ponto de entrega criado pelo cliente tem de ter zona. Sem zonas, nenhum cliente conseguia guardar endereços. | aplicada |
| `20261003104438_caixa_gestao.sql` | Caixa na app do operador: `abrir_caixa`, `registar_sangria`, `resumo_caixa` e `fechar_caixa` (com `vendas.registar` na cozinha). Uma caixa aberta por posto; o esperado soma a parcela Dinheiro das vendas e os pacotes pagos na loja, menos as sangrias; o fecho guarda o contado e a diferença e a caixa fechada não muda. | aplicada |
| `20261003110912_avisos_pedidos_envio.sql` | N16 (estado do pedido ao cliente: confirmado, saiu, entregue, cancelado pela cozinha) e N17 (pedido novo à equipa da cozinha). Liga `pg_cron` e `pg_net`, guarda o segredo do envio em `segredos_servidor` (só o servidor) e `agendar_envio(url)` agenda a função `enviar-notificacoes` de minuto a minuto. Fecha `rls_auto_enable` à API. | aplicada; `agendar_jobs()` e `agendar_envio(...)` corridos |
| `20261003122759_relatorios_semana.sql` | Encontrado na simulação de uma semana: o "prato mais pedido" agrupava tudo quando os pratos não têm ficha técnica (agora agrupa pelo prato do cardápio); as métricas por turno só contavam entregas com hora prometida (agora contam todas; "a horas" continua só sobre as que a têm). | aplicada |
| `20261003123551_hora_entrega_estimada.sql` | Cada pedido fica com `hora_prometida` definida pelo servidor: pedido normal = hora do pedido + `parametros.tempo_entrega_min` (45 min, ajustável de 10 a 240); pedido de grupo = hora de entrega do grupo. O cliente vê "Entrega prevista" e as entregas a horas passam a ser medidas. | aplicada |
| `20261003143204_indicacao_mesmo_local_rapido.sql` | Encontrado no teste de 6 meses: o limite "indicados no mesmo local" percorria todos os ganhos de indicação e calculava a distância a cada um, por isso cada entrega de um amigo indicado ficava mais lenta à medida que o programa crescia (o mesmo no limite de descontos por local). Agora usa `pontos_entrega_proximos(ponto)`: caixa de coordenadas com índice e depois a distância exacta — o mesmo resultado que `mesmo_ponto_entrega`. O semestre simulado passou de mais de 60 s para 29 s no Supabase. | aplicada |
| `20261003152851_seguranca_pagamentos.sql` | Análise de fraude: (1) o limite "mesmo local" conta só os amigos **da mesma pessoa** (vizinhos de prédio convidados por pessoas diferentes já não se bloqueiam); (2) levantar o dinheiro das indicações exige um pedido próprio entregue e pago (`sem_compra_propria`); (3) desconto de convite só a partir de `parametros.desconto_subtotal_minimo` (2 000 Kz; 0 desliga; o orçamento devolve `pedido_minimo`); (4) pagamentos electrónicos na entrega (Multicaixa Express, TPA, Unitel Money, Transferência) exigem referência e foto do comprovativo (bucket privado `comprovativos`, tabela `comprovativos_pagamento`, referência única por método), e o gerente confere ou rejeita cada um (`conferir_comprovativo`) antes de `fechar_caixa`; formas de pagamento fora da lista são recusadas. | aplicada |
| `20261003170433_conferencia_ia.sql` | Conferência financeira: leitura automática (Claude) da foto de cada comprovativo (`ia_estado`: confere / diverge / ilegível / indisponível — só um aviso; o gerente confere sempre); extratos do banco, Multicaixa ou Unitel Money (bucket privado `extratos`, tabelas `extratos` e `extrato_movimentos`) lidos automaticamente ou escritos à mão; conciliação (referência, ou valor e data ±2 dias) com comprovativos sem extrato e entradas sem comprovativo; `fecho_diario`, `fecho_mensal` (com sinais por funcionário) e `historico_pedido` (quem fez cada passo). Permissão nova `financas.conferir`. | aplicada |
| `20261003172236_alertas_pedidos.sql` | Alertas dos pedidos (job `mb_alertas_pedidos`, de minuto a minuto): por confirmar há mais de `alerta_confirmacao_min` (7) → N18 aos gerentes da cozinha e ao administrador principal; passou a hora prometida há mais de `alerta_atraso_min` (5) → N19 aos gerentes e ao estafeta e N20 ao cliente. `informar_atraso` (gerente da cozinha ou estafeta que leva o pedido) diz ao cliente o motivo e a nova estimativa; `alertas_abertos` para o ecrã das entregas. Tabela `alertas_pedido` (um por pedido e tipo), tudo na auditoria. | aplicada |
| `20261003201550_reclamacoes.sql` | Reclamações: avaliação com até `reclamacao_estrelas_max` (2) estrelas ou o botão "Tenho uma reclamação" no pedido (`fazer_reclamacao`, até 7 dias, uma por pedido). N21 aos gerentes; `factos_reclamacao` junta horas, atraso real, alertas, itens e histórico do cliente (sem nomes) para a análise automática; `reclamacoes_lista`, `decidir_reclamacao` (resposta N22 e compensação) e `relatorio_reclamacoes` (por motivo, cozinha, estafeta e acerto da análise). O cliente só vê texto, estado e resposta (`minhas_reclamacoes`). | aplicada |
| `20261003201735_estimulos_mensais.sql` | Estímulos mensais (Albert Bandura): `metricas_funcionario` (entregas, % a horas, estrelas, vendas ao balcão, confirmações, reclamações com razão, comprovativos rejeitados) e `metricas_cliente`; `gerar_estimulos` compara cada pessoa consigo própria, dá uma meta próxima, o melhor registo da equipa como modelo e o bónus sugerido só se a meta anterior foi atingida (`estimulo_bonus_meta`, `estimulo_premio_cliente`, `estimulo_top_clientes`). `decidir_estimulo` (o administrador aprova, edita bónus e mensagem) → N23. `reservar_analises` / `registar_analise_reclamacao` / `registar_mensagem_estimulo` para a Edge Function `analisar-ia`; `agendar_analises(url)`. | aplicada; `agendar_analises(...)` corrido |
| `20261003201823_avisos_reclamacoes_estimulos.sql` | Textos e validade de N21 a N23; job `mb_estimulos_mensais` (dia 1, 07:00 de Luanda) gera as propostas do mês que acabou. | aplicada |
| `20261003204853_investigacoes.sql` | Agente investigador financeiro: `sinais_financeiros` (rejeitados, fotos que não conferem, pagamentos sem extrato, caixas com diferença → pontos), `abrir_investigacoes` (quem tem `financas.conferir`; job no dia 3 para o mês anterior), `casos_investigacao_lista`, `decidir_caso` e `investigar_de_novo` (nunca sobre o próprio caso). Ferramentas do agente só de leitura e só do serviço (`agente_comprovativos`, `agente_caixas`, `agente_historico_pedido` sem nome do cliente, `agente_entradas_parecidas`, `agente_referencia`, `agente_equipa`); `registar_investigacao` guarda o dossiê e os passos, com auditoria como "Agente Claude". `historico_pedido` passa a usar `historico_pedido_dados`. Interruptor `agente_investigador` (desligado). | aplicada; `agendar_investigacoes(...)` corrido |
| `20261003204944_avisos_investigacoes.sql` | N24 (risco alto) a quem confere as finanças, nunca ao investigado; job `mb_investigacoes` (dia 3, 07:00 de Luanda). | aplicada |
| `20261003210258_analista.sql` | Analista do administrador: permissão `analista.usar`; `perguntar_analista` (limite `analista_perguntas_dia`, 30), `pedir_relatorio_analista` (um por mês; job no dia 2), `perguntas_analista_lista` (cada um vê as suas e os relatórios). Ferramentas agregadas, só de leitura, só do serviço e sem nomes de clientes: `analista_vendas` (agrupadas por dia, semana, mês, cozinha, zona, hora ou dia da semana), `analista_pratos`, `analista_clientes`, `analista_operacao`, `analista_satisfacao`, `analista_equipa`, `analista_financas`. `metricas_funcionario` passa a usar `metricas_funcionario_periodo`. Interruptor `agente_analista` (desligado). | aplicada; `agendar_analista(...)` corrido |
| `20261003210348_avisos_analista.sql` | N25 (relatório do mês pronto) a quem usa o analista; job `mb_relatorio_analista` (dia 2, 07:00 de Luanda). | aplicada |
| `20261003212809_vigilancia_convida.sql` | Vigilante do Convida e Ganha: `aparelhos_contas` (histórico, só com o hash do token, de que contas usaram cada telemóvel; trigger em `dispositivos_push`); `sinais_convida` (mesmo telemóvel em várias contas, levantamento para o número de um indicado, só o pedido do desconto, muitos no mesmo dia, mesmo local, ganhos anulados → pontos; `vigilancia_pontuacao_min` 4); `abrir_vigilancia` (quem tem `indicacoes.verificar`; job à segunda-feira para as últimas 4 semanas), `casos_convida_lista`, `decidir_caso_convida`, `vigiar_de_novo`. Ferramentas só de leitura e do serviço, sem nomes nem telefones (`vig_indicados`, `vig_pedidos_indicado`, `vig_levantamentos`, `vig_rede`, `vig_comparar`). Interruptor `agente_vigilante` (desligado). | aplicada; `agendar_vigilancia(...)` corrido |
| `20261003213144_avisos_vigilancia.sql` | N26 (risco alto) a quem verifica os ganhos, com o código do indicador; job `mb_vigilancia` (segunda-feira, 06:30 de Luanda). | aplicada |
| `20261003215915_gerente_turno.sql` | Gerente de turno: `propostas_turno` (avisar o cliente de um atraso, confirmar, pausar um prato, reforço de estafetas, nota; caducam em 30 minutos; não se repetem enquanto pendentes) e `turno_analises`; `situacao_turno` (fila, atrasos, estafetas de turno, pratos e vendas do dia, sem nomes de clientes) e `turno_precisa_atencao` (só então se chama o Claude); `reservar_turno` (nas horas `turno_hora_inicio`–`turno_hora_fim`, cada cozinha no máximo de 5 em 5 minutos), `registar_propostas_turno` (valida cada proposta), `propostas_turno_lista` e `decidir_proposta_turno` (ao aceitar, a acção corre com as permissões do gerente: `informar_atraso`, `mudar_estado_pedido` ou pausa do prato com auditoria). Interruptor `agente_turno` (desligado). | aplicada; `agendar_turno(...)` corrido |
| `20261003223842_avisos_turno.sql` | N27 (sugestões do gerente de turno) aos gerentes da cozinha; caduca em 30 minutos. | aplicada |

Os números de versão dos ficheiros são os que o Supabase registou ao aplicar, para `supabase migration list` e
`supabase db push` não voltarem a aplicá-las.

No fim das migrações **todos os interruptores ficam desligados**.

### Jobs agendados

`agendar_jobs()` agenda os jobs com `pg_cron` **se a extensão já estiver activa** (as migrações não a activam).
Depois de activar o `pg_cron` no painel do Supabase, correr `select agendar_jobs();`.
Os jobs respeitam os interruptores: com tudo desligado não enfileiram nada.

| Job | Quando (Luanda) | Função |
|---|---|---|
| Contadores por zona | de hora a hora | `job_contadores_zona()` |
| N6 — indicado expira em 5 dias | diariamente às 08h | `job_n6_expiracao()` |
| N5 — lembrete do almoço | dias úteis às 11h | `job_n5_lembrete()` |
| N7 — perto do top | segundas às 08h | `job_n7_destaques()` |

## Edge Functions

| Função | O que faz | Configuração |
|---|---|---|
| `functions/enviar-notificacoes` | Envia a fila (clientes N2–N11; equipa N12) pelo push da Expo, um pedido por app (a Expo recusa tokens de projectos diferentes no mesmo pedido); desactiva tokens rejeitados; marca como enviadas | Publicada sem verificação de JWT, com autenticação própria: segredo `ENVIO_SEGREDO` (obrigatório) no cabeçalho `x-envio-segredo`. Agendar com `select agendar_envio_notificacoes('<url da função>', '<segredo>');` depois de activar `pg_cron` e `pg_net`. |
| `functions/vigiar` | Vigilante do Convida e Ganha: o Claude investiga um indicador com sinais (indicados, pedidos, levantamentos, rede, comparação) e entrega um dossiê | Publicada sem verificação de JWT, com o mesmo segredo do envio. Usa o `ANTHROPIC_API_KEY`. Agendada com `select agendar_vigilancia('<url da função>');` (de 5 em 5 minutos). Só trabalha com o interruptor `agente_vigilante` ligado |
| `functions/turno` | Gerente de turno: de 5 em 5 minutos, quando uma cozinha tem algo a pedir atenção, o Claude (modelo mais leve) lê a situação, pode abrir o histórico de um pedido e propõe acções ao gerente | Publicada sem verificação de JWT, com o mesmo segredo do envio. Usa o `ANTHROPIC_API_KEY`. Agendada com `select agendar_turno('<url da função>');` (de 5 em 5 minutos). Só trabalha com o interruptor `agente_turno` ligado e nas horas de serviço |
| `functions/analista` | Analista do administrador: responde às perguntas da app e faz o relatório mensal, escolhendo as ferramentas de números agregados | Publicada sem verificação de JWT: pelo pg_cron (segredo) responde à mais antiga; pela app só à pergunta indicada (`pergunta_id`). Usa o `ANTHROPIC_API_KEY`. Agendada com `select agendar_analista('<url da função>');` (de minuto a minuto). Só trabalha com o interruptor `agente_analista` ligado |
| `functions/investigar` | Agente investigador financeiro: o Claude usa ferramentas só de leitura em vários passos e entrega um dossiê (risco, factos, explicações possíveis, perguntas) | Publicada sem verificação de JWT, com o mesmo segredo do envio. Usa o `ANTHROPIC_API_KEY`. Agendada com `select agendar_investigacoes('<url da função>');` (de 5 em 5 minutos, um caso por execução). Só trabalha com o interruptor `agente_investigador` ligado |
| `functions/analisar-ia` | Analisa com o Claude as reclamações (categoria, gravidade, se os factos dão razão, resposta sugerida) e escreve a mensagem pessoal dos estímulos (Bandura) | Publicada sem verificação de JWT, com o mesmo segredo do envio. Usa o mesmo `ANTHROPIC_API_KEY`; sem ele o gerente decide sem análise e usa-se o texto base. Agendada com `select agendar_analises('<url da função>');` (de 2 em 2 minutos) |
| `functions/ler-documentos` | Lê com o Claude as fotos dos comprovativos (valor, referência, data) e os extratos (entradas do período); o servidor compara e concilia | Publicada sem verificação de JWT, com o mesmo segredo do envio (`x-envio-segredo`). Segredo `ANTHROPIC_API_KEY` nas Edge Functions; sem ele fica tudo para a conferência à mão. Agendada com `select agendar_leitura('<url da função>');` |

## Testes

Testes pgTAP em `tests/`. Cada ficheiro corre numa transacção e desfaz tudo no fim: nenhum dado de teste fica na
base de dados.

| Ficheiro | Cobre |
|---|---|
| `00_estrutura.test.sql` | Interruptores desligados, parâmetros, Cozinha da Alexandra, `cozinha_id`, registo de cliente, auditoria imutável, RLS |
| `01_ligacao.test.sql` | Secção 13, testes 1–4 |
| `02_desconto.test.sql` | Testes 5–8 |
| `03_ganho.test.sql` | Testes 9–21 e revisão de ganhos |
| `04_pagamentos.test.sql` | Testes 22–25 e crédito em refeições |
| `05_destaques.test.sql` | Testes 26–30 |
| `06_rls.test.sql` | Testes 31–32 (com o papel `authenticated`), estado só no servidor, escrita só pelo servidor |
| `07_funcoes_apoio.test.sql` | Jobs, avaliações, grupos, pontos de entrega, métricas de turno, relatório |
| `08_ajustes_i1.test.sql` | Testes 33–45: nomes, sincronização, valores garantidos, venda gerada |
| `09_endurecimento.test.sql` | Teste 46: `search_path`, funções de trigger, índices (precisa da migração de endurecimento) |
| `10_decisoes_i1.test.sql` | Testes 47–51: duração garantida, vendas por item, caixa, estorno sem stock, permissões |
| `11_consumo_stock.test.sql` | Consumo de stock das vendas de pedidos: validação dos itens, conversão de unidades, excluídos/ajustados, diários, consumo uma só vez (incl. segunda tentativa do servidor), estorno, vendas do operador, guarda contra consumo de dispositivo (auditado como bloqueado), avisos |
| `12_privilegios.test.sql` | Funções SECURITY DEFINER chamáveis pelas apps (lista fechada), nenhuma para `anon`; grupo criado pela app; guarda do consumo com sessão do telemóvel |
| `13_app_cliente.test.sql` | I2: registo e ligação ao cliente do balcão, cardápio e preço no servidor, ponto/zona, desconto no orçamento, amigos, tokens de push, textos e fila de notificações |
| `14_desconto_limite.test.sql` | Desconto limitado ao valor do pedido (com e sem taxa), orçamento, entrega com valor final 0, uso único |
| `18_avaliacoes_equipa.test.sql` | I5: avaliar pelo telemóvel (C9), lista pública sem ids e médias (C10), moderação e palavras filtradas (O7), N9, reconhecimentos e N12 com push da equipa (O8) |
| `16_lancamento.test.sql` | I4: esconder ganhos na lista (C5), textos N5–N7, N5 com prato do dia, envio com preferências e interruptor |
| `17_preferencias_notificacao.test.sql` | C14: o cliente desliga N5 e N7 pela app, só no seu perfil e só essas colunas; N5 não é enfileirada |
| `19_pedidos_grupo.test.sql` | I6: criar grupo (C12) e validações, aderir (C13) com desconto, N10/N11, fecho e repartição da taxa, modo empresa, cancelar, O10 |
| `20_fotos_avaliacoes.test.sql` | I7: envio para o bucket privado (caminho do servidor, só o autor, limite de 2), privacidade das pendentes, fila e decisão de moderação (O7), visibilidade depois de aprovada e com a avaliação oculta |
| `21_rede_cozinhas.test.sql` | I8: selector com e sem `multi_cozinha`, pedido na cozinha escolhida, pratos de outra cozinha recusados, cozinha pausada, grupo noutra cozinha, relatório comparativo, O10 com a cozinha |
| `22_rls_tabelas_base.test.sql` | Políticas das tabelas base: cliente sem acesso, vendas e stock por cozinha, append-only, vendas da app só do servidor, distribuições, campos de crédito dos clientes, organograma e auditoria |
| `23_notificacoes_validade.test.sql` | Validade das notificações por código e limpeza da fila |
| `24_apagar_conta.test.sql` | Apagar a conta: recusa com pedido a meio, dados pessoais e utilizador da Auth apagados, venda mantida, auditoria, novo registo com o mesmo telefone |
| `25_pratos_montaveis.test.sql` | I9: interruptor, preço com extras, nome com opções, mínimo/máximo, opção de outro prato, repetida, indisponível, preço da app ignorado, venda, permissões |
| `26_como_chegar.test.sql` | I10: gravar com `cozinhas.gerir`, cliente sem acesso à tabela, interruptor, autorização pública, cozinha pausada |
| `27_acompanhamento_entrega.test.sql` | I11: entregador, interruptor, posição inválida, tabela fechada, posição e tempo estimado para o cliente, outro cliente, sem permissão, posição antiga, apagada na entrega |
| `28_pacotes.test.sql` | I12: interruptor, adesão pendente e única, cliente sem escrita, permissão, referência, validade, valor pago (até ao valor da refeição + entrega), idempotência, a pagar na entrega, parcela Pacote, soma das parcelas, devolução no cancelamento, poupança, pausa, prova social, reembolso, pagamento na loja com caixa |
| `29_avisos_pacotes.test.sql` | I12: N15 só a quem tem `pacotes.gerir`, N13 no pagamento, N14 ao ficar com 3 refeições (uma vez) e a 3 dias do fim (uma vez), textos, envio só com o interruptor ligado, funções internas fechadas |
| `30_opcoes_stock.test.sql` | I9: receita + opções (o mesmo produto soma-se), stock diário sem movimento, só receita sem opções, prato sem receita só com opções, unidade desconhecida pendente, ingrediente mal escrito não trava a entrega, formato da lista |
| `31_fotos_pratos.test.sql` | Bucket público de 5 MB; `cozinhas.gerir` envia fotos de pratos e cozinhas e apaga; prato inexistente, pasta ou extensão errada recusados; sem permissão não envia nem apaga; o cliente vê mas não envia |
| `32_zonas_gestao.test.sql` | `plataforma.parametros` cria e altera zonas (auditadas); sem a permissão, nem o caixa nem o cliente criam; ponto do cliente sem zona recusado, com zona aceite; zona apagada deixa de aparecer |
| `34_avisos_pedidos.test.sql` | N17 só à equipa da cozinha do pedido, com pratos, bairro e total; N16 em confirmado, saiu e entregue (não em preparação); a cliente que cancela não é avisada, a cozinha que cancela avisa com o motivo; seguem sem interruptor e caducam em 2 h; pedidos de grupo não geram N17; o segredo do envio só o service_role confirma |
| `35_relatorios_semana.test.sql` | Prato mais pedido sem ficha técnica = o prato do cardápio com mais unidades; métricas de turno contam todas as entregas e a percentagem a horas só sobre as que tinham hora prometida |
| `36_hora_entrega_estimada.test.sql` | 45 min por defeito; pedido normal + 45 min (a hora mandada pelo telemóvel é ignorada); pedido de grupo = hora do grupo; a direcção ajusta; fora de 10–240 recusado |
| `37_indicacao_mesmo_local.test.sql` | pontos próximos = exactamente os de `mesmo_ponto_entrega` (400 pontos ao acaso); 24 m conta e 26 m não; outro tipo de local não conta; o raio segue o parâmetro; a função não está na API |
| `38_seguranca_pagamentos.test.sql` | quem envia a foto do comprovativo; sem referência, sem foto ou com a foto de outro pedido → recusado; método inventado recusado; referência repetida recusada; resumo da caixa com os comprovativos; fecho bloqueado até conferir; rejeitar exige nota; levantamento sem compra própria recusado; desconto abaixo do mínimo; limite por morada contado por quem convida |
| `39_conferencia_ia.test.sql` | reserva da leitura (sem ler duas vezes); confere / diverge / 3 falhas → indisponível; só o serviço regista leituras; extrato: permissões, ficheiro uma vez, leitura e conciliação por referência e por valor; entradas à mão, ligação única, apagar com motivo; fecho do dia (avisos com quem registou) e do mês (por funcionário); histórico do pedido e quem o pode ver |
| `40_alertas_pedidos.test.sql` | job dá cada alerta uma vez; N18 só aos gerentes da cozinha do pedido, com quem, o quê e há quanto tempo; N19 ao gerente e ao estafeta, N20 à cliente; pedido entregue ou no prazo sem alerta; motivo pelo gerente ou pelo estafeta do pedido (não por outra cozinha); quem vê os alertas; auditoria |
| `41_reclamacoes_estimulos.test.sql` | avaliação de 1★ vira reclamação e a de 4★ não; botão do pedido (uma vez, só do próprio cliente); N21 só à cozinha do pedido; factos com o atraso real e sem nomes; reserva e falhas da análise; decisão do gerente (só na sua cozinha, uma vez) com N22; relatório do mês; estímulos: mestria, meta atingida e bónus, modelo, meta próxima, clientes que mais compraram; aprovação só pelo administrador, N23, descartado sem aviso, gerar de novo não mexe no aprovado |
| `42_investigacoes.test.sql` | sinais e pontos (o rejeitado não conta duas vezes); só quem confere abre casos, um por período; reserva única; ferramentas (comprovativos, entradas parecidas, referência, histórico sem nome do cliente, caixas, equipa) só do serviço; dossiê, passos, N24 e auditoria "Agente Claude"; o investigado não vê nem decide o seu caso; interruptor desligado = agente parado |
| `43_analista.test.sql` | só quem tem `analista.usar` pergunta; limite diário; um relatório por mês; ferramentas (vendas por zona, pratos, clientes, operação, satisfação, finanças) certas e sem nomes de clientes, só do serviço; estímulos com a mesma conta da equipa; reserva única; resposta e N25; cada um vê as suas perguntas e todos os relatórios; interruptor desligado = parado |
| `44_vigilancia_convida.test.sql` | histórico do mesmo telemóvel em duas contas; sinais e pontos de uma rede (mesmo local, telemóvel, levantamento para um indicado, só o pedido do desconto, muitos no mesmo dia) e de um indicador normal (0); só quem verifica abre casos; ferramentas certas, sem nomes nem telefones e só do serviço; dossiê, N26 com o código; decisão uma vez; interruptor desligado = parado |
| `45_gerente_turno.test.sql` | escolha da cozinha a analisar (uma vez de 5 em 5 minutos); situação com os pedidos em curso e o atraso, estafetas e pratos, sem nomes de clientes; propostas validadas e sem repetir; N27 só aos gerentes da cozinha; cada gerente decide só as da sua cozinha; aceitar avisa o cliente com o motivo editado, confirma o pedido ou pausa o prato (auditoria); decide-se uma vez; caducam em 30 minutos; interruptor desligado = parado |
| `33_caixa_gestao.test.sql` | Abre a caixa (uma por posto), quem tem `vendas.registar` vê-a; fora da cozinha ou sem a permissão recusa; o esperado só soma a parcela Dinheiro e os pacotes na loja menos as sangrias; o fecho guarda a diferença; caixa fechada não aceita sangrias, novo fecho nem escrita directa; tudo na auditoria |
| `15_app_operador.test.sql` | I3: telefone e ligação dos funcionários, painel (O1), verificação e "Confirmar todos" com N3 (O2), levantamentos (O3), embaixadores (O4), fila de entregas e caixas (E1), auditoria de cozinhas e cardápio (O6) |

### Como correr

- **Supabase CLI (local):** `supabase test db`.
- **Postgres local sem Docker** (precisa de `psql`, `pg_prove` e `pgtap`): `scripts/testar_bd.sh` — cria a base
  `mandabue_teste`, aplica `local/supabase_shim.sql` (papéis, `auth.uid()` e privilégios por defeito do Supabase),
  as migrações e corre os testes.
- **Projecto Supabase remoto (SQL editor, API ou MCP):** `scripts/bundle_testes.py <pasta>` gera um script por
  teste, sem comandos do `psql`. Cada script termina com um erro intencional cuja mensagem é o relatório TAP
  (`ok 1 - …`); o erro desfaz a transacção inteira.

### Resultados (1 de Outubro de 2026)

| Teste | Postgres 16 local, 22 migrações | Supabase `laruvuambdovnkojwrzp` |
|---|---|---|
| 00 estrutura | 19/19 | 19/19 |
| 01 ligação | 9/9 | 9/9 |
| 02 desconto | 12/12 | 12/12 |
| 03 ganho | 30/30 | 30/30 |
| 04 pagamentos | 22/22 | 22/22 |
| 05 destaques | 16/16 | 16/16 |
| 06 RLS | 29/29 | 29/29 |
| 07 funções de apoio | 19/19 | 19/19 |
| 08 ajustes I1 | 32/32 | 32/32 (a verificação alterada na I2 voltou a correr) |
| 09 endurecimento | 5/5 | 5/5 |
| 10 decisões I1 | 29/29 | 29/29 |
| 11 consumo de stock | 35/35 | 35/35 |
| 12 privilégios | 8/8 | 8/8 |
| 13 app do cliente | 37/37 | 37/37 |
| 14 desconto limitado | 11/11 | 11/11 |
| 15 app do operador | 28/28 | 28/28 (em partes, ver abaixo) |
| 16 lançamento (I4) | 16/16 | 16/16 |
| 17 preferências de notificação (C14) | 6/6 | 6/6 |
| 18 avaliações e equipa (I5) | 30/30 | 30/30 |
| 19 pedidos de grupo (I6) | 33/33 | 33/33 |
| 20 fotos nas avaliações (I7) | 19/19 | 19/19 |
| 21 rede de cozinhas (I8) | 17/17 | 17/17 |
| 22 RLS das tabelas base | 26/26 | 26/26 |
| 23 validade das notificações | 7/7 | 7/7 |
| 24 apagar a conta | 11/11 | 11/11 |
| 25 pratos montáveis (I9) | 14/14 | 14/14 |
| 26 como chegar (I10) | 9/9 | 9/9 |
| 27 acompanhamento da entrega (I11) | 14/14 | 14/14 |
| 28 pacotes (I12) | 25/25 | 25/25 |
| 29 avisos dos pacotes (I12) | 14/14 | 14/14 |
| 30 opções descontam stock (I9) | 9/9 | 9/9 |
| 31 fotos dos pratos | 9/9 | 8/8 (apagar só pela API de Storage) |
| 32 zonas de entrega | 8/8 | fluxo completo simulado (operador cria a zona, cliente guarda o endereço, orçamento com a taxa) |
| 33 caixa | 17/17 | 17/17 |
| 34 avisos dos pedidos | 13/13 | 13/13 |
| 35 relatórios da semana | 5/5 | 5/5 |
| 36 hora de entrega estimada | 5/5 | 5/5 |
| 37 indicados no mesmo local (rápido) | 6/6 | 6/6 |
| 38 segurança dos pagamentos e do Convida e Ganha | 27/27 | 27/27 |
| 39 conferência (leitura automática, extratos, fechos, histórico) | 27/27 | 27/27 |
| 40 alertas dos pedidos | 18/18 | 17/18 (o n.º 3 difere por desenho: na produção o administrador principal também recebe o N18) |
| 41 reclamações e estímulos | 34/34 | 34/34 |
| 42 agente investigador | 21/21 | 20/21 (o n.º 16 difere por desenho: na produção o administrador principal também recebe o N24) |
| 43 analista do administrador | 20/20 | 19/20 (o n.º 17 difere por desenho: na produção o administrador principal também recebe o N25) |
| 44 vigilante do Convida e Ganha | 17/17 | 17/17 (o n.º 12 corrigido: procurava "923", que também aparece em identificadores) |
| 45 gerente de turno | 15/15 | 15/15 (o n.º 4 corrigido: assumia que o prato do teste era o primeiro do cardápio) |
| **Total** | **834/834** | |

Na I2 voltaram a correr no Supabase os testes afectados por cada migração (app do cliente: 06, 08, 09, 12 e 13;
desconto limitado: 02, 09 e 14); os restantes não dependem delas (e todos passam localmente).

Na I3 correram no Supabase, depois da migração da app do operador: 09 (5/5), as 3 verificações de catálogo do 12
(funções chamáveis pelas apps e por `anon`) e o 15 inteiro, dividido em partes. Nas partes remotas do 15 as situações
que o teste local cria alterando `parametros` (limite semanal 0, levantamento mínimo 100, limiar de Embaixador 1)
foram criadas com dados de teste, sem tocar na linha de `parametros` de produção. O 03 e o resto do 12 não voltaram a
correr remotamente (o ambiente bloqueou as escritas em massa); passam localmente.

Na I4 correram no Supabase o 16 (16/16), o 05 (15/15: sem a verificação que altera `limiar_intervalos` em
`parametros`) e as verificações de `search_path`, `anon` e privilégios das funções alteradas.

Na I5 correram no Supabase o 18 (30/30) e as verificações de catálogo do 09 e do 12 (funções chamáveis pelas apps,
`anon`, `search_path`, funções de trigger, índices das chaves estrangeiras). A Edge Function `enviar-notificacoes`
foi publicada de novo (versão 2), sem verificação de JWT e com o segredo próprio, como antes.

Na I6 correram no Supabase o 19 (33/33) e as verificações de catálogo (funções chamáveis pelas apps, `anon`,
`search_path`, funções de trigger, índices). A Edge Function foi publicada de novo (versão 3: envia o código do
grupo para a app abrir o grupo ao tocar em N10/N11).

Na I7 correram no Supabase o 20 (19/19, com o storage real) e as verificações de catálogo. Localmente,
`local/supabase_shim.sql` simula `storage.buckets` e `storage.objects` (com RLS) para os testes.

Na I8 correram no Supabase o 21 (17/17) e as verificações de catálogo.

Nas políticas das tabelas base correram no Supabase o 22 (26/26) e as verificações de catálogo do 12 (nenhuma
função SECURITY DEFINER para `anon`, trigger `clientes_proteger_campos` não exposto). O verificador do Supabase só
mostra sem políticas `notificacoes_fila`, `contadores_zona` e `dispositivos_push`, todas só do servidor.

Nas correcções de 2 de Outubro correram no Supabase o 23 (7/7) e o 24 (11/11, com o utilizador da Auth apagado de
facto). A Edge Function `enviar-notificacoes` passou à versão 4 (marca as notificações como enviadas lote a lote) e
tem testes próprios em Node, sem Deno: `node --experimental-strip-types supabase/functions/enviar-notificacoes/envio.test.mjs`.

### `ler-documentos` (leitura automática dos comprovativos e extratos)

Corre de minuto a minuto (`agendar_leitura(url)`, mesmo segredo do envio de avisos). Lê com o Claude
(`claude-opus-5-5`, saída estruturada) as fotos dos comprovativos e os extratos (PDF ou foto) e regista o
resultado no servidor, que compara e concilia. **Precisa do segredo `ANTHROPIC_API_KEY`** nas Edge
Functions (Supabase → Edge Functions → Secrets). Sem ele, os documentos ficam "leitura automática
indisponível" e a conferência faz-se à mão na app (Caixa e Conferência). Depois de configurar a chave,
"Ler de novo" pede outra leitura. Testes: `node --experimental-strip-types supabase/functions/ler-documentos/leitura.test.mjs`.

### `analisar-ia` (reclamações e estímulos)

Corre de 2 em 2 minutos (`agendar_analises(url)`). Para cada reclamação aberta envia ao Claude o texto do
cliente (como dado, nunca como instruções) e os factos registados pelo servidor, e guarda a sugestão; o
gerente decide sempre na app (Reclamações). Para cada estímulo proposto pede a mensagem pessoal seguindo
Bandura (mestria, meta próxima, modelo, elogio concreto, tom calmo), a partir do texto base; o administrador
aprova e pode editar na app (Estímulos do mês). Mesmo segredo `ANTHROPIC_API_KEY`.
Testes: `node --experimental-strip-types supabase/functions/analisar-ia/analisar.test.mjs`.

### `vigiar` (vigilante do Convida e Ganha)

Como o investigador, mas para o programa de indicações: cada caso é um indicador com sinais de rede de
contas (o mesmo telemóvel em várias contas, dinheiro levantado para o número de um indicado, indicados que só
fazem o pedido do desconto, muitos no mesmo dia ou no mesmo local). O Claude não vê nomes nem telefones e
está instruído a separar redes falsas de vizinhos, colegas e famílias. Quem verifica os ganhos lê o dossiê no
ecrã Vigilância do Convida e decide; anular ganhos continua a ser na Verificação. Ligar em Parâmetros →
`agente_vigilante`. Testes: `node --experimental-strip-types supabase/functions/vigiar/vigiar.test.mjs`.

### `turno` (gerente de turno)

Corre de 5 em 5 minutos nas horas de serviço, mas só chama o Claude quando uma cozinha tem algo a pedir
atenção (pedido por confirmar perto do limite, atraso sem motivo dado, pedido a chegar à hora prometida sem ter
saído, cancelamentos seguidos, fila grande para os estafetas). Propõe no máximo 4 acções; o gerente aceita ou
recusa no ecrã Gerente de turno (aviso N27) e, ao aceitar, a acção é feita em nome dele. Usa um modelo mais
leve por correr muitas vezes. Ligar em Parâmetros → `agente_turno`. Testes:
`node --experimental-strip-types supabase/functions/turno/turno.test.mjs`.

### `analista` (analista do administrador)

Quem tem `analista.usar` pergunta na app (ecrã Analista) em linguagem normal; a app chama logo a função e
o pg_cron apanha o que ficar por responder. O Claude escolhe as ferramentas (vendas, pratos, clientes,
operação, satisfação, equipa, finanças), compara períodos e responde com os números-chave, as limitações
e até 3 sugestões. No dia 2 de cada mês faz o relatório do mês anterior e avisa (N25). As ferramentas só
dão números agregados, sem nomes nem contactos de clientes. Ligar em Parâmetros → `agente_analista`.
Testes: `node --experimental-strip-types supabase/functions/analista/analista.test.mjs`.

### `investigar` (agente investigador financeiro)

Um agente, não uma chamada única: em cada execução pega num caso e o Claude decide que ferramentas usar
(comprovativos da pessoa, caixas, histórico de pedidos, entradas do extrato com o mesmo valor, referências
repetidas, comparação com a equipa), até 10 voltas; perto do limite de tempo da Edge Function pede-lhe a
conclusão. Todas as ferramentas são funções do servidor só de leitura e só do serviço; o agente não decide,
não bloqueia e não mexe em dinheiro. O dossiê aparece na app em Conferência → Investigações, com o que o
agente consultou; quem confere decide (nunca sobre o próprio caso). Ligar em Parâmetros → `agente_investigador`.
Testes: `node --experimental-strip-types supabase/functions/investigar/investigar.test.mjs`.

A CI (`.github/workflows/testes.yml`) corre em cada PR a base de dados, a Edge Function e as duas apps.

Nas fases I9–I11 correram no Supabase o 25 (14/14), o 26 (9/9) e o 27 (14/14). Os testes que contam interruptores
(00, 06) e tabelas com estratégia de sincronização (08) passaram a contar 13 interruptores e 27 tabelas.

Na I12 correram no Supabase o 28 (25/25) e o 29 (14/14), e depois do stock das opções o 30 (9/9) e de novo o 11 (35/35); os testes de contagem passaram a 14 interruptores, 29 tabelas e 17
permissões, e o 12 inclui as novas funções na lista das chamáveis pelas apps.

Nenhum dado de teste ficou na base (contagens de `funcionarios`, `clientes`, `pedidos`, `cardapio` e `caixa` a 0;
interruptores todos desligados). **Por remover:** o esquema `testes` e a extensão `pgtap` ficaram instalados no
Supabase porque o ambiente bloqueou o `drop`; correr no SQL editor
`drop schema if exists testes cascade; drop extension if exists pgtap;`.

A comparação do esquema (funções, colunas, restrições, índices, políticas, triggers, vistas, comentários e
privilégios) entre o Supabase e uma base local construída com as primeiras 4 migrações deu resultados idênticos (comparação feita antes do endurecimento e do consumo de stock).

### Dependências nas tabelas base

As funções dependem destas colunas do esquema base: `clientes(id, tipo, nome, telefone, auth_user_id)`,
`funcionarios(id, nome, direcao_id, administrador_principal, permissoes_extra jsonb, auth_user_id)`,
`direcoes(id, permissoes jsonb)`, `turnos(id, funcionario_id, data, hora_inicio, hora_fim, periodo)`,
`zonas(id, nome, tipo)`, `pratos_base(id)`, `vendas`, `caixa(data, funcionario_id, fechamento jsonb)`,
`distribuicoes(quantidade_quebra)` e `auditoria`.

## Notificações push: o que falta para chegarem aos telemóveis

O servidor já põe os avisos na fila e o `pg_cron` chama a função `enviar-notificacoes` todos os
minutos (ver `select * from cron.job_run_details order by start_time desc`). Falta a parte da Expo e
do Firebase, que só o dono das contas pode criar:

1. **Expo** (expo.dev, conta gratuita): criar dois projectos, `manda-bue-cliente` e
   `manda-bue-operador`, e copiar o *Project ID* de cada um para os segredos do repositório
   `EXPO_PROJECT_ID_CLIENTE` e `EXPO_PROJECT_ID_OPERADOR`.
2. **Firebase** (console.firebase.google.com): um projecto com duas apps Android,
   `ao.mandabue.cliente` e `ao.mandabue.operador`. Descarregar o `google-services.json` (serve às
   duas) e colar o conteúdo no segredo `GOOGLE_SERVICES_JSON`.
3. **Firebase → Expo**: em Firebase, *Definições do projecto → Contas de serviço → Gerar nova chave
   privada*; em expo.dev, em cada projecto, *Credentials → Android → FCM V1 service account key*,
   carregar esse ficheiro.
4. Gerar APKs novos (o workflow usa os segredos). Ao entrar, a app pede autorização e regista o
   telemóvel; a partir daí os avisos chegam.

Sem estes passos as apps funcionam normalmente, só não recebem push (os avisos saem da fila sem
telemóvel a quem entregar).

## Simulações de operação (`supabase/simulacoes/`)

`semana.sql` simula uma semana de segunda a sábado no Supabase, com as funcionalidades todas ligadas:
2 cozinhas com gerente e estafeta, 24 clientes registados pelo telemóvel (16 entram com código de
amigo), caixas abertas e fechadas todos os dias, cerca de 95 pedidos com cancelamentos, entregas em
dinheiro e Multicaixa, avaliações, um pacote do mês, levantamento do Convida e Ganha, relatórios,
métricas por turno, destaques, contadores e reconhecimento da equipa. Corre numa só transacção e
termina com uma excepção que devolve o relatório e **desfaz tudo** (nenhum dado fica). Usa o posto
"Posto Semana" para não colidir com caixas reais abertas.

`mes.sql` faz o mesmo durante um mês (30 clientes, cerca de 450 pedidos, posto "Posto Mes").

`semestre.sql` simula 6 meses (156 dias de trabalho, 50 clientes, cerca de 1 800 pedidos, posto
"Posto Semestre") com o que só acontece num semestre: aumento do preço dos Chocos no dia 60 (os
pedidos seguintes usam o preço novo), troca do estafeta, novo bairro Talatona no dia 90 com a sua
taxa, a Cozinha do Kilamba pausada uma semana (os pedidos são recusados e os clientes pedem à
Alexandra), uma "embaixadora" com 30 amigos, o pacote do mês renovado 7 vezes, levantamentos
mensais, retenção a 30/60/90 dias e o tempo dos relatórios com milhares de pedidos. Corre em cerca
de 30 s, abaixo do limite de 60 s do SQL do Supabase.

As três simulações registam os pagamentos electrónicos com referência e foto do comprovativo e conferem-nos antes de fechar cada caixa.

Limites conhecidos das simulações: o servidor não deixa recuar `criado_em`, por isso o que conta pela
data de criação (limite semanal do Convida e Ganha, validade dos pacotes, expiração das ligações aos
60 dias) vê o período inteiro como "agora".
