export type Perfil = {
  cliente_id: string;
  nome: string;
  primeiro_nome: string;
  tipo: 'Particular' | 'Empresa';
  telefone: string | null;
  codigo: string | null;
  pseudonimo: string | null;
  tem_ligacao: boolean;
  cliente_novo: boolean;
};

export type Parametros = {
  ganho_por_pedido: number;
  duracao_dias: number;
  desconto_indicado: number;
  limite_verificacao_semanal: number;
  levantamento_minimo: number;
  limite_parcelamento: number;
  contador_minimo: number;
  tamanho_top: number;
};

export type ChaveFuncionalidade =
  | 'indicacao'
  | 'destaques'
  | 'pessoas_como_tu'
  | 'contadores_zona'
  | 'perfil_cozinha'
  | 'avaliacoes'
  | 'avaliacoes_fotos'
  | 'reconhecimento_equipa'
  | 'pedidos_grupo'
  | 'multi_cozinha';

export type Funcionalidades = Partial<Record<ChaveFuncionalidade, boolean>>;

export type ItemCardapio = {
  id: string;
  nome: string;
  descricao: string | null;
  categoria: string | null;
  preco: number;
  foto_url: string | null;
  do_dia: boolean;
  cozinha_id: string;
  prato_base_id: string | null;
};

export type ItemOrcamento = {
  cardapio_id: string;
  nome: string;
  qtd: number;
  preco_unitario: number;
  prato_base_id?: string | null;
};

/** Avaliação na lista pública (C10): sem ids */
export type AvaliacaoPublica = {
  criado_em: string;
  estrelas: number;
  comentario: string | null;
  autor: string;
  pratos: { nome: string; estrelas: number }[];
};

export type Media = { media: number; total: number };
export type MediasAvaliacoes = { cozinha: Media | null; pratos: (Media & { prato_base_id: string })[] };

export type Orcamento = {
  itens: ItemOrcamento[];
  subtotal: number;
  zona_id: string | null;
  zona_nome: string | null;
  taxa_entrega: number;
  desconto: number;
  motivo_desconto: string | null;
  total: number;
};

export type EstadoPedido =
  | 'pendente'
  | 'confirmado'
  | 'em_preparacao'
  | 'em_entrega'
  | 'entregue_pago'
  | 'cancelado'
  | 'estornado';

export type Pedido = {
  id: string;
  criado_em: string;
  estado: EstadoPedido;
  itens: ItemOrcamento[];
  subtotal: number;
  taxa_entrega: number;
  desconto_indicacao: number;
  credito_indicacao_usado: number;
  observacoes: string | null;
  motivo_cancelamento: string | null;
  hora_prometida: string | null;
  entregue_em: string | null;
};

export type Zona = { id: string; nome: string; taxa: number | null };

export type Endereco = {
  id: string;
  nome: string | null;
  principal: boolean;
  ponto_entrega_id: string;
  pontos_entrega: {
    id: string;
    tipo: 'residencial' | 'empresa';
    referencia: string | null;
    zona_id: string | null;
    zonas: { nome: string } | null;
  } | null;
};

export type Saldo = {
  saldo_disponivel: number;
  em_verificacao: number;
  ganho_hoje: number;
  ganho_semana: number;
  total_recebido: number;
};

export type Amigo = {
  primeiro_nome: string;
  ligado_em: string;
  expira_em: string | null;
  dias_restantes: number | null;
  estado: 'aguarda_primeiro_pedido' | 'activo' | 'expirado';
  pedidos_com_ganho: number;
  ganho_total: number;
};

export type PessoaComoTu = { nome_exibido: string; amigos: number; valor: number };

/** Linha da lista de destaques (C3). Valor exacto ou intervalo; ambos vazios se a pessoa escondeu os ganhos */
export type Destaque = {
  posicao: number;
  nome_exibido: string;
  amigos: number;
  valor: number | null;
  valor_min: number | null;
  valor_max: number | null;
  sou_eu: boolean;
};

export type MinhaPosicao = {
  posicao: number | null;
  nome_exibido: string;
  amigos: number;
  valor: number;
  amigos_em_falta: number;
  no_top: boolean;
};

export type PreferenciasNotificacao = { lembrete_almoco: boolean; destaques: boolean };

export type PerfilDestaques = {
  pseudonimo: string;
  mostrar_nome_real: boolean;
  ocultar_ganhos: boolean;
  sair_da_lista: boolean;
};

export type Levantamento = {
  id: string;
  criado_em: string;
  valor: number;
  metodo: string | null;
  numero_destino: string | null;
  lote_id: string | null;
  parcela: number | null;
  total_parcelas: number | null;
  estado: 'pedido' | 'aprovado' | 'pago' | 'rejeitado';
  referencia: string | null;
  motivo_rejeicao: string | null;
};
