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
  /** Minutos até à hora de entrega prometida (o servidor marca-a em cada pedido) */
  tempo_entrega_min?: number;
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
  | 'multi_cozinha'
  | 'pratos_montaveis'
  | 'como_chegar'
  | 'acompanhamento_entrega'
  | 'pacotes';

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
  /** Caminhos das fotos aprovadas (I7); vazio com avaliacoes_fotos desligado */
  fotos: string[];
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
  /** Subtotal mínimo para o desconto de convite (0 = sem mínimo) */
  desconto_subtotal_minimo?: number;
  total: number;
  /** Pedido de grupo: taxa por pessoa se o grupo fechasse agora (a taxa real é repartida no fecho) */
  taxa_grupo_estimada?: number | null;
};

export type EstadoGrupo = 'aberto' | 'fechado' | 'em_preparacao' | 'entregue' | 'cancelado';

/** C13: o grupo visto pelos colegas (primeiros nomes, sem ids de clientes) */
export type GrupoDetalhe = {
  grupo_id: string;
  codigo_convite: string;
  cozinha_id: string;
  cozinha_nome: string;
  hora_entrega: string;
  prazo_adesao: string;
  estado: EstadoGrupo;
  modo_pagamento: 'individual' | 'empresa';
  local: string | null;
  organizador: string;
  sou_organizador: boolean;
  taxa_estimada: number | null;
  participantes: { nome: string; estado: EstadoPedido; sou_eu: boolean }[];
};

export type MeuGrupo = {
  codigo_convite: string;
  hora_entrega: string;
  prazo_adesao: string;
  estado: EstadoGrupo;
  local: string | null;
  sou_organizador: boolean;
  participantes: number;
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
  /** I12: parte paga pelo pacote e refeições gastas */
  pago_pacote: number;
  refeicoes_pacote: number;
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

/** Cozinha que aceita pedidos (selector, I8). Foto e história só com perfil público */
export type CozinhaParaPedir = {
  cozinha_id: string;
  nome: string;
  publica: boolean;
  foto_url: string | null;
  historia: string | null;
  pratos: number;
};

// I9 · Pratos montáveis
export type Opcao = { id: string; nome: string; preco_extra: number; ordem: number };
export type GrupoOpcoes = {
  id: string;
  cardapio_id: string;
  nome: string;
  minimo: number;
  maximo: number;
  ordem: number;
  opcoes: Opcao[];
};
export type OpcaoEscolhida = { id: string; nome: string; preco_extra: number };

// I10 · Como chegar
export type LocalizacaoCozinha = {
  cozinha_id: string;
  nome: string;
  morada: string | null;
  horario: string | null;
  lat: number;
  lng: number;
};

// I11 · Acompanhamento da entrega
export type Ponto = { lat: number; lng: number };
export type PosicaoEntrega = {
  activo: boolean;
  estafeta?: (Ponto & { actualizado_em: string }) | null;
  destino?: Ponto | null;
  distancia_km?: number | null;
  minutos?: number | null;
};

// I12 · Pacotes pré-pagos
export type MetodoPacote = 'multicaixa_express' | 'unitel_money' | 'loja';
export type Pacote = {
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
};
export type MeuPacote = {
  adesao_id: string;
  pacote: string;
  estado: 'pendente' | 'activa';
  metodo: MetodoPacote;
  refeicoes_total: number;
  refeicoes_oferta: number;
  refeicoes_usadas: number;
  refeicoes_restantes: number;
  valor_refeicao: number;
  preco: number;
  entrega_gratis: boolean;
  inicio: string | null;
  fim: string | null;
  pausa_restante: number;
  em_vigor: boolean;
  poupanca: number;
};
export type PacotesAMinhaVolta = {
  no_meu_local: number | null;
  na_minha_zona: number | null;
  poupanca_media_mes: number | null;
};
