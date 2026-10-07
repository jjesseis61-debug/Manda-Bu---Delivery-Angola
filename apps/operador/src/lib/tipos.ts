export type Funcionario = {
  funcionario_id: string;
  nome: string;
  cargo: string | null;
  administrador_principal: boolean;
  permissoes: string[];
  /** Cozinhas onde tem turnos (vê as métricas e os reconhecimentos da equipa, O8) */
  cozinhas_equipa: string[];
};

/** Linha do cadastro de pessoal (só o administrador principal) */
export type PessoalItem = {
  id: string;
  nome: string;
  cargo: string | null;
  telefone: string | null;
  administrador_principal: boolean;
  estafeta: boolean;
  activo: boolean;
};

/** Pedido agendado para mais tarde (fila do que vem, para a cozinha preparar na altura) */
export type PedidoAgendado = {
  pedido_id: string;
  agendado_para: string;
  cozinha_id: string;
  cliente_nome: string;
  itens: { nome: string; qtd: number }[];
  a_pagar: number;
  ponto_referencia: string | null;
  zona_nome: string | null;
};

/** Conta de empresa (B2B) */
export type Empresa = { id: string; nome: string; limite_refeicao: number; activa: boolean; membros: number };
export type EmpresaMembro = { cliente_id: string; nome: string; codigo: string | null };
export type RelatorioEmpresa = {
  empresa: string | null;
  mes: string;
  total: number;
  pedidos: { data: string; cliente: string; valor: number; itens: string | null }[];
};

/** Feira (consignação): o feirante leva pratos de preço fixo e acerta no regresso */
export type Feira = {
  id: string;
  nome: string;
  estado: 'aberta' | 'fechada';
  data_saida: string;
  vendedor: string | null;
  esperado: number;
};
export type FeiraItem = {
  item_id: string;
  nome: string;
  preco_unit: number;
  levada: number;
  vendida: number;
  devolvida: number;
  perda: number;
  restante: number;
};
export type FeiraResumo = {
  id: string;
  nome: string;
  estado: 'aberta' | 'fechada';
  cozinha_id: string;
  vendedor_id: string;
  data_saida: string;
  fechada_em: string | null;
  itens: FeiraItem[];
  esperado: number;
  recebido_dinheiro: number;
  recebido_transferencia: number;
  recebido: number;
  diferenca: number;
};

/** Sugestão de despacho: um pedido pronto a sair e o estafeta online mais perto */
export type SugestaoDespacho = {
  pedido_id: string;
  zona: string;
  referencia: string | null;
  itens: { nome: string; qtd: number }[];
  sugestao: { funcionario_id: string; nome: string; distancia_km: number; pedidos_a_levar: number } | null;
};

/** Posição de um estafeta de serviço, para o mapa de acompanhamento do despacho */
export type PosicaoEstafeta = {
  funcionario_id: string;
  nome: string;
  lat: number;
  lng: number;
  pedidos_a_levar: number;
  atualizado_em: string;
};

export type Permissao =
  | 'indicacoes.ver'
  | 'indicacoes.verificar'
  | 'indicacoes.aprovar_pagamentos'
  | 'plataforma.parametros'
  | 'cozinhas.gerir'
  | 'relatorios.exportar'
  | 'pedidos.gerir'
  | 'entregas.registar'
  | 'avaliacoes.moderar'
  | 'equipa.reconhecer'
  | 'pacotes.gerir'
  | 'vendas.registar'
  | 'financas.conferir'
  | 'clientes.gerir'
  | 'equipa.gerir'
  | 'analista.usar'
  | 'stock.gerir'
  | 'atendimento.responder'
  | 'feira.gerir';

export type Painel = {
  custo: number;
  ganhos: number;
  descontos: number;
  vendas_indicacao: number;
  clientes_novos: number;
  indicadores_activos: number;
  periodos_terminados: number;
  retidos: number;
  revistos: number;
  anulados_verificacao: number;
  em_verificacao: number;
  top: { indicador_id: string; nome: string; nivel: string | null; amigos: number; valor: number }[];
};

export type GanhoVerificacao = {
  ganho_id: string;
  criado_em: string;
  valor: number;
  motivo: string | null;
  indicador_id: string;
  indicador_nome: string;
  indicador_telefone: string | null;
  indicador_nivel: string | null;
  indicado_nome: string;
  pedido_id: string | null;
  pedido_dispositivo: string | null;
  pagador_distinto: boolean | null;
  ponto_tipo: string | null;
  ponto_lat: number | null;
  ponto_lng: number | null;
  ponto_referencia: string | null;
  numero_indicador: string | null;
  numero_indicado: string | null;
};

export type LevantamentoOperador = {
  pagamento_id: string;
  criado_em: string;
  indicador_id: string;
  indicador_nome: string;
  indicador_telefone: string | null;
  valor: number;
  metodo: string | null;
  numero_destino: string | null;
  lote_id: string | null;
  parcela: number | null;
  total_parcelas: number | null;
  estado: 'pedido' | 'aprovado' | 'pago' | 'rejeitado';
  referencia: string | null;
  motivo_rejeicao: string | null;
  pago_em: string | null;
  primeiro_levantamento: boolean;
  saldo_disponivel: number | null;
};

export type Embaixador = {
  cliente_id: string;
  nome: string;
  telefone: string | null;
  nivel: 'normal' | 'embaixador';
  indicados_activos: number;
  ganho_mes: number;
  elegivel: boolean;
};

export type PedidoOperador = {
  pedido_id: string;
  criado_em: string;
  estado: string;
  cozinha_id: string;
  cliente_nome: string;
  cliente_telefone: string | null;
  itens: { nome: string; qtd: number; preco_unitario: number }[];
  subtotal: number;
  taxa_entrega: number;
  desconto_indicacao: number;
  credito_indicacao_usado: number;
  a_pagar: number;
  observacoes: string | null;
  hora_prometida: string | null;
  pagador_distinto: boolean | null;
  ponto_entrega_id: string | null;
  ponto_tipo: string | null;
  ponto_lat: number | null;
  ponto_lng: number | null;
  ponto_referencia: string | null;
  zona_nome: string | null;
};

export type Caixa = { id: string; posto: string; data: string; cozinha_id: string };

export type FechoCaixa = {
  troco_inicial: number;
  dinheiro_vendas: number;
  dinheiro_pacotes: number;
  sangrias: number;
  esperado: number;
  contado: number;
  diferenca: number;
  /** Pagamentos electrónicos rejeitados na conferência (fechos a partir de 3/10/2026) */
  rejeitados?: number;
  valor_rejeitado?: number;
  fechado_em: string;
  funcionario_nome: string | null;
  observacao: string | null;
};

/** Caixa com o fecho (null enquanto está aberta) */
export type CaixaGestao = Caixa & { troco_inicial: number | null; funcionario_nome: string | null; fechamento: FechoCaixa | null };

export type Sangria = { valor: number; motivo: string; em: string; funcionario_nome: string | null };

/** Pagamento electrónico registado na entrega, à espera de ser conferido */
export type ComprovativoCaixa = {
  id: string;
  pedido_id: string;
  cliente_nome: string;
  metodo: string;
  valor: number;
  referencia: string;
  caminho: string;
  estado: 'por_conferir' | 'conferido' | 'rejeitado';
  nota: string | null;
  registado_por: string | null;
  criado_em: string;
  /** Leitura automática da foto (só um aviso: quem confere é o gerente) */
  ia_estado?: EstadoLeitura;
  ia_valor?: number | null;
  ia_referencia?: string | null;
  ia_nota?: string | null;
};

/** Alerta de um pedido em curso: por confirmar há muito tempo, ou atrasado (com o motivo dado ao cliente) */
export type AlertaPedido = {
  pedido_id: string;
  tipo: 'sem_confirmacao' | 'atraso';
  minutos: number;
  motivo: string | null;
  mais_minutos: number | null;
  criado_em: string;
  motivo_em: string | null;
};

export type EstadoLeitura = 'pendente' | 'a_ler' | 'confere' | 'diverge' | 'ilegivel' | 'indisponivel';

export type EstadoExtrato = 'aguarda_ficheiro' | 'por_ler' | 'a_ler' | 'lido' | 'ilegivel' | 'indisponivel' | 'manual';

export type Extrato = {
  id: string;
  conta: string;
  periodo_inicio: string;
  periodo_fim: string;
  caminho: string | null;
  tipo_ficheiro: 'pdf' | 'imagem' | null;
  estado: EstadoExtrato;
  ia_nota: string | null;
  criado_em: string;
};

export type MovimentoExtrato = {
  id: string;
  extrato_id: string;
  data: string;
  valor: number;
  referencia: string | null;
  descricao: string | null;
  origem: 'ia' | 'manual';
  comprovativo_id: string | null;
  ligacao: 'automatica' | 'manual' | null;
};

export type ComprovativoSemExtrato = {
  comprovativo_id: string;
  pedido_id: string;
  cliente_nome: string;
  metodo: string;
  valor: number;
  referencia: string;
  dia: string;
  estado: 'por_conferir' | 'conferido' | 'rejeitado';
  ia_estado: EstadoLeitura;
  registado_por: string | null;
  conferido_por: string | null;
};

export type MovimentoSemComprovativo = {
  movimento_id: string;
  extrato_id: string;
  conta: string;
  data: string;
  valor: number;
  referencia: string | null;
  descricao: string | null;
  origem: 'ia' | 'manual';
};

export type Conciliacao = {
  inicio: string;
  fim: string;
  encontrados: { comprovativo_id: string; pedido_id: string; valor: number; referencia: string; dia: string; ligacao: string | null }[];
  comprovativos_sem_extrato: ComprovativoSemExtrato[];
  aguardam_extrato: number;
  movimentos_sem_comprovativo: MovimentoSemComprovativo[];
  totais: { comprovativos: number; encontrados: number; sem_extrato: number; movimentos: number; movimentos_sem_comprovativo: number };
};

export type AlertaFecho = {
  tipo: string;
  caixa_id?: string;
  posto?: string;
  comprovativo_id?: string;
  pedido_id?: string;
  metodo?: string;
  valor?: number;
  referencia?: string;
  ia_valor?: number | null;
  ia_referencia?: string | null;
  quem?: string | null;
};

export type FechoDiario = {
  dia: string;
  caixas: {
    caixa_id: string;
    posto: string;
    cozinha: string;
    aberta_por: string | null;
    fechada: boolean;
    fechada_por: string | null;
    esperado: number | null;
    contado: number | null;
    diferenca: number | null;
    electronico: number;
    por_conferir: number;
    rejeitados: number;
    ia_alertas: number;
  }[];
  pedidos_entregues: number;
  cancelados: number;
  vendido: number;
  electronico: number;
  diferenca_caixas: number;
  caixas_abertas: number;
  alertas: AlertaFecho[];
};

export type FechoMensal = {
  ano: number;
  mes: number;
  inicio: string;
  fim: string;
  dias: { dia: string; pedidos: number; vendido: number; dinheiro: number; electronico: number; diferenca_caixas: number }[];
  totais: { pedidos: number; vendido: number; dinheiro: number; electronico: number; diferenca_caixas: number; caixas_por_fechar: number };
  conciliacao: Conciliacao;
  por_funcionario: {
    funcionario_id: string;
    nome: string;
    comprovativos: number;
    rejeitados: number;
    ia_alertas: number;
    sem_extrato: number;
    valor_sem_extrato: number;
    conferiu: number;
    conferiu_sem_extrato: number;
    diferenca_caixas: number;
  }[];
};

export type EventoPedido = { em: string; acao: string; quem: string | null; detalhe: Record<string, unknown> | null };

export type HistoricoPedido = {
  pedido_id: string;
  estado: string;
  cliente: string | null;
  cozinha: string | null;
  entregador: string | null;
  caixa: string | null;
  valor: number;
  parcelas: { metodo: string; valor: number; referencia?: string }[];
  eventos: EventoPedido[];
};

export type ResumoCaixa = {
  caixa_id: string;
  posto: string;
  troco_inicial: number;
  dinheiro_vendas: number;
  pedidos: number;
  dinheiro_pacotes: number;
  pacotes: number;
  sangrias: number;
  lista_sangrias: Sangria[];
  esperado: number;
  aberta_por: string | null;
  electronico: number;
  comprovativos: ComprovativoCaixa[];
  por_conferir: number;
  rejeitados: number;
  valor_rejeitado: number;
};

export type Cozinha = {
  id: string;
  nome: string;
  responsavel: string | null;
  foto_url: string | null;
  historia: string | null;
  estado: 'activa' | 'pausada' | 'inactiva';
  consentimento_publico: boolean;
  /** Contactos mostrados aos clientes (Contactos e página da cozinha) */
  telefone_publico: string | null;
  whatsapp_publico: string | null;
  horario_publico: string | null;
};

export type PratoCardapio = {
  id: string;
  cozinha_id: string;
  nome: string;
  descricao: string | null;
  categoria: string | null;
  preco: number;
  disponivel: boolean;
  do_dia: boolean;
  ordem: number;
  foto_url?: string | null;
  /** Doses lançadas para hoje (null = sem limite) */
  doses_dia?: number | null;
  /** false = prato só de feira (consignação), não aparece aos clientes online */
  visivel_online?: boolean;
};

/** Doses que restam hoje de um prato com limite */
export type DosesPrato = { cardapio_id: string; restantes: number; lancadas: number };

export type Relatorio = {
  pedidos_por_dia: { dia: string; pedidos: number }[];
  clientes_novos: number;
  clientes_indicacao: number;
  retencao: Record<string, number | null>;
  media_avaliacao: number | null;
  prato_mais_pedido: { nome: string; quantidade: number } | null;
};

export type ComentarioModeracao = {
  avaliacao_id: string;
  criado_em: string;
  cozinha_nome: string;
  estrelas: number;
  comentario: string;
  oculta: boolean;
  autor_nome: string;
  autor_publico: string;
};

export type PalavraFiltrada = { id: string; palavra: string };

export type Periodo = 'manha' | 'tarde' | 'noite';

export type MetricaTurno = {
  periodo: Periodo;
  quebras: number;
  quantidade_quebra: number;
  entregas: number;
  entregas_a_horas: number;
  pct_a_horas: number | null;
  diferenca_caixa: number;
};

export type TipoReconhecimento = 'menos_desperdicio' | 'entregas_a_horas' | 'caixa_certa' | 'outro';

export type Reconhecimento = {
  id: string;
  criado_em: string;
  cozinha_id: string;
  semana: string;
  periodo: Periodo;
  tipo: TipoReconhecimento;
  nota: string | null;
};

/** O10: um grupo do dia com todos os pedidos juntos */
export type GrupoOperador = {
  grupo_id: string;
  cozinha_id: string;
  cozinha_nome: string;
  hora_entrega: string;
  prazo_adesao: string;
  estado: 'aberto' | 'fechado' | 'em_preparacao' | 'entregue' | 'cancelado';
  modo_pagamento: 'individual' | 'empresa';
  organizador: string;
  organizador_telefone: string | null;
  local: { referencia: string | null; lat: number | null; lng: number | null; zona: string | null };
  pedidos: {
    pedido_id: string;
    cliente_nome: string;
    estado: string;
    itens: { nome: string; qtd: number }[];
    a_pagar: number;
    observacoes: string | null;
  }[];
  resumo: { nome: string; qtd: number }[];
  total_a_pagar: number;
};

/** O7: foto à espera de moderação (o ficheiro já foi enviado) */
export type FotoPendente = {
  foto_id: string;
  caminho: string;
  criado_em: string;
  cozinha_nome: string;
  estrelas: number;
  comentario: string | null;
  autor_nome: string;
};

/** Relatório comparativo das cozinhas (I8), pedidos da app no período */
export type LinhaComparativo = {
  cozinha_id: string;
  nome: string;
  estado: string;
  pedidos: number;
  vendas: number;
  ticket_medio: number | null;
  cancelados: number;
  clientes: number;
  clientes_novos: number;
  clientes_indicacao: number;
  pct_a_horas: number | null;
  media_avaliacao: number | null;
  avaliacoes: number;
};

// I9 · Pratos montáveis
/** Ingrediente de uma opção, por unidade do prato (desconta stock na venda) */
export type ComponenteOpcao = { produto_id: string; quantidade: number; unidade: string };
export type OpcaoPrato = {
  id: string;
  grupo_id: string;
  nome: string;
  preco_extra: number;
  disponivel: boolean;
  ordem: number;
  componentes: ComponenteOpcao[];
};
export type ProdutoStock = { id: string; nome: string; categoria_medida: 'Peso' | 'Volume' | 'Unidade' | null; tipo_estoque: string | null };
export type GrupoOpcoesPrato = {
  id: string;
  cardapio_id: string;
  nome: string;
  minimo: number;
  maximo: number;
  ordem: number;
  opcoes: OpcaoPrato[];
};

// I10 · Localização da cozinha
export type LocalizacaoCozinha = {
  id?: string;
  cozinha_id: string;
  morada: string | null;
  horario: string | null;
  lat: number;
  lng: number;
  publica: boolean;
};

// I12 · Pacotes pré-pagos
export type PacoteCatalogo = {
  id: string;
  nome: string;
  descricao: string | null;
  refeicoes: number;
  refeicoes_oferta: number;
  valor_refeicao: number;
  preco: number;
  validade_dias: number;
  pausa_max_dias: number;
  entrega_gratis: boolean;
  activo: boolean;
  ordem: number;
};
export type AdesaoOperador = {
  adesao_id: string;
  estado: 'pendente' | 'activa' | 'cancelada' | 'reembolsada';
  metodo: 'multicaixa_express' | 'unitel_money' | 'loja';
  pacote: string;
  cliente_nome: string;
  cliente_telefone: string | null;
  preco: number;
  refeicoes_total: number;
  refeicoes_usadas: number;
  inicio: string | null;
  fim: string | null;
  referencia: string | null;
  criado_em: string;
  reembolso_previsto: number;
  valor_reembolso: number | null;
};

/** Zona de entrega (bairro): a taxa aplica-se aos pedidos com pontos nesta zona */
export type ZonaEntrega = { id: string; nome: string; taxa: number; tipo: 'Própria' | 'Terceirizada' | null };

export type FactosReclamacao = {
  pedido: {
    feito_as: string;
    estado: string;
    itens: { nome: string; qtd: number }[];
    total_kz: number;
    hora_prometida: string | null;
    confirmado_as: string | null;
    saiu_as: string | null;
    entregue_as: string | null;
    minutos_de_atraso_na_entrega: number | null;
    minutos_ate_entregar: number | null;
    motivo_cancelamento: string | null;
  } | null;
  alertas: { tipo: string; minutos: number; motivo_dado: string | null }[];
  comprovativo_rejeitado: boolean;
  cliente: { pedidos_90_dias: number; reclamacoes_90_dias: number; reclamacoes_com_razao_90_dias: number } | null;
};

export type Reclamacao = {
  id: string;
  pedido_id: string;
  criado_em: string;
  origem: 'avaliacao' | 'cliente';
  estrelas: number | null;
  texto: string | null;
  cliente_nome: string;
  cozinha: string | null;
  estafeta: string | null;
  estado: 'aberta' | 'resolvida';
  ia_estado: 'pendente' | 'a_analisar' | 'analisada' | 'indisponivel';
  ia_categoria: string | null;
  ia_gravidade: string | null;
  ia_procedente: 'sim' | 'nao' | 'incerto' | null;
  ia_fundamento: string | null;
  ia_resumo: string | null;
  ia_accao: string | null;
  ia_resposta: string | null;
  ia_compensacao: string | null;
  ia_nota: string | null;
  procedente: boolean | null;
  categoria: string | null;
  resposta: string | null;
  compensacao: string | null;
  compensacao_valor: number | null;
  decidido_por: string | null;
  decidido_em: string | null;
  factos: FactosReclamacao;
};

export type RelatorioReclamacoes = {
  total: number;
  abertas: number;
  procedentes: number;
  horas_ate_responder: number | null;
  compensacoes_kz: number;
  ia_concordou: number;
  ia_com_opiniao: number;
  por_categoria: { categoria: string; total: number; procedentes: number }[];
  por_cozinha: { cozinha: string | null; total: number; procedentes: number }[];
  por_estafeta: { estafeta: string; total: number; procedentes: number }[];
};

export type MetricasEstimulo = Record<string, number | null>;

export type Estimulo = {
  id: string;
  tipo: 'funcionario' | 'cliente';
  nome: string;
  cargo: string | null;
  metricas: { mes: MetricasEstimulo; anterior: MetricasEstimulo };
  foco: string | null;
  conquista: string | null;
  modelo: string | null;
  meta: { metrica: string; valor: number } | null;
  meta_anterior: { metrica: string; valor: number; atingida: boolean } | null;
  mensagem: string;
  ia_estado: 'pendente' | 'a_analisar' | 'analisada' | 'indisponivel';
  ia_mensagem: string | null;
  ia_nota: string | null;
  bonus_sugerido: number;
  bonus: number | null;
  mensagem_final: string | null;
  estado: 'proposto' | 'aprovado' | 'descartado';
  decidido_por: string | null;
  decidido_em: string | null;
};

/** O que os casos dos agentes (investigador, vigilante) têm em comum */
export type CasoAgente = {
  id: string;
  inicio: string;
  fim: string;
  pontuacao: number;
  estado: 'por_investigar' | 'a_investigar' | 'investigado' | 'indisponivel';
  ia_nota: string | null;
  risco: 'baixo' | 'medio' | 'alto' | null;
  resumo: string | null;
  conclusao: {
    factos: { texto: string; pedido_id: string | null }[];
    explicacoes_possiveis: string[];
    recomendacao: string;
    perguntas_ao_funcionario: string[];
  } | null;
  passos: { ferramenta: string; entrada: Record<string, unknown>; resultado?: string }[];
  investigado_em: string | null;
  decisao: 'sem_problema' | 'erro_operacional' | 'suspeita_confirmada' | null;
  decisao_nota: string | null;
  decidido_por: string | null;
  decidido_em: string | null;
  criado_em: string;
};

export type CasoInvestigacao = CasoAgente & {
  funcionario: string;
  cargo: string | null;
  sinais: {
    comprovativos: number;
    rejeitados: number;
    nao_conferem: number;
    ilegiveis: number;
    sem_extrato: number;
    valor_sem_extrato: number;
    caixas_com_diferenca: number;
    soma_diferencas: number;
  };
};

export type CasoConvida = CasoAgente & {
  indicador: string;
  codigo: string | null;
  sinais: {
    indicados: number;
    mesmo_local: number;
    telemovel_partilhado: number;
    levantamento_para_indicado: number;
    so_um_pedido: number;
    indicados_com_14_dias: number;
    maximo_num_dia: number;
    ganhos_anulados: number;
    ganhos_kz: number;
  };
};

export type PerguntaAnalista = {
  id: string;
  tipo: 'pergunta' | 'relatorio_mensal';
  pergunta: string;
  inicio: string | null;
  fim: string | null;
  estado: 'pendente' | 'a_responder' | 'respondida' | 'indisponivel';
  resposta: string | null;
  numeros: { rotulo: string; valor: string }[];
  sugestoes: string[];
  limitacoes: string | null;
  ia_nota: string | null;
  passos: number;
  criado_em: string;
  respondida_em: string | null;
  quem: string | null;
};

export type PropostaTurno = {
  id: string;
  cozinha: string;
  tipo: 'avisar_atraso' | 'confirmar' | 'pausar_prato' | 'reforco' | 'nota';
  pedido_id: string | null;
  prato: string | null;
  prioridade: 'alta' | 'media' | 'baixa';
  explicacao: string;
  motivo_cliente: string | null;
  mais_minutos: number | null;
  estado: 'pendente' | 'aceite' | 'recusada' | 'expirada';
  criado_em: string;
  expira_em: string;
  decidido_por: string | null;
  decidido_em: string | null;
  erro: string | null;
  cliente: string | null;
};

export type ItemCompra = {
  produto_id: string | null;
  produto: string;
  quantidade: number;
  unidade: string | null;
  urgencia: 'hoje' | 'esta_semana' | 'proxima_semana';
  custo_estimado: number | null;
  fornecedor: string | null;
  motivo: string;
  estado: 'pendente' | 'comprado' | 'ignorado';
  decidido_por?: string | null;
};

export type AlertaCompra = {
  tipo: 'validade' | 'desvio' | 'preco' | 'ruptura' | 'dados' | 'outro';
  gravidade: 'alta' | 'media' | 'baixa';
  produto: string | null;
  texto: string;
};

export type PlanoCompras = {
  id: string;
  cozinha_id: string;
  cozinha: string;
  dia: string;
  origem: 'automatico' | 'pedido';
  pedido_por: string | null;
  estado: 'pendente' | 'a_preparar' | 'pronto' | 'indisponivel';
  resumo: string | null;
  compras: ItemCompra[];
  alertas: AlertaCompra[];
  criado_em: string;
  pronto_em: string | null;
};

export type ConversaResumo = {
  id: string;
  cliente: string;
  estado: 'agente' | 'humano' | 'fechada';
  motivo: string | null;
  atendido_por: string | null;
  ultima_mensagem_em: string;
  ultima_mensagem: string | null;
  ultima_do_cliente: boolean | null;
};

export type ConversaDetalhe = {
  id: string;
  estado: 'agente' | 'humano' | 'fechada';
  motivo: string | null;
  cliente: string;
  telefone: string | null;
  mensagens: { id: string; autor: 'cliente' | 'agente' | 'funcionario' | 'sistema'; texto: string; criado_em: string; quem: string | null }[];
  pedidos: { pedido_id: string; feito_em: string; estado: string; itens: string | null; total_kz: number }[];
};
