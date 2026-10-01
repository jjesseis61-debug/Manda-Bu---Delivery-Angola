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
  | 'equipa.reconhecer';

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
