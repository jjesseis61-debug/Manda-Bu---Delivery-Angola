export type Funcionario = {
  funcionario_id: string;
  nome: string;
  cargo: string | null;
  administrador_principal: boolean;
  permissoes: string[];
  /** Cozinhas onde tem turnos (vê as métricas e os reconhecimentos da equipa, O8) */
  cozinhas_equipa: string[];
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
  | 'vendas.registar';

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
};

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
