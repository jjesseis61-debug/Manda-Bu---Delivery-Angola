/** 1300 -> "1.300 Kz" */
export function formatarKz(valor: number | null | undefined): string {
  const inteiro = Math.round(Number(valor ?? 0));
  const sinal = inteiro < 0 ? '−' : '';
  return `${sinal}${Math.abs(inteiro).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')} Kz`;
}

/** 12.345 -> "12,3 %" */
export function formatarPercentagem(parte: number, total: number): string {
  if (!total) return '—';
  return `${((100 * parte) / total).toFixed(1).replace('.', ',')} %`;
}

export function formatarData(iso: string | null | undefined, comHora = false): string {
  if (!iso) return '';
  const d = new Date(iso);
  return comHora
    ? d.toLocaleString('pt-PT', { dateStyle: 'short', timeStyle: 'short' })
    : d.toLocaleDateString('pt-PT');
}

/** "2026-10-01" -> "01/10/2026" (sem fuso horário) */
export function formatarDia(dia: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(dia ?? '');
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}

/** Data de hoje em Luanda (UTC+1) no formato AAAA-MM-DD, com um desvio em dias */
export function diaLuanda(desvioDias = 0, agora: Date = new Date()): string {
  const luanda = new Date(agora.getTime() + 60 * 60 * 1000 + desvioDias * 86400000);
  return luanda.toISOString().slice(0, 10);
}

/** Segunda-feira da semana de um dia AAAA-MM-DD (com desvio em semanas) */
export function segundaFeira(dia: string, desvioSemanas = 0): string {
  const d = new Date(`${dia}T12:00:00Z`);
  const dow = (d.getUTCDay() + 6) % 7; // 0 = segunda
  d.setUTCDate(d.getUTCDate() - dow + 7 * desvioSemanas);
  return d.toISOString().slice(0, 10);
}

/** "12h30" (hora de Luanda, UTC+1) */
export function horaLuanda(iso: string): string {
  const d = new Date(new Date(iso).getTime() + 60 * 60 * 1000);
  return `${String(d.getUTCHours()).padStart(2, '0')}h${String(d.getUTCMinutes()).padStart(2, '0')}`;
}

export const nomeEstadoGrupo: Record<string, string> = {
  aberto: 'Aberto (aceita pedidos)',
  fechado: 'Fechado',
  em_preparacao: 'Em preparação',
  entregue: 'Entregue',
  cancelado: 'Cancelado',
};

export const nomePeriodo: Record<string, string> = { manha: 'Manhã', tarde: 'Tarde', noite: 'Noite' };

export const nomeTipoReconhecimento: Record<string, string> = {
  entregas_a_horas: 'Entregas a horas',
  menos_desperdicio: 'Menos desperdício',
  caixa_certa: 'Caixa certa',
  outro: 'Outro',
};

/** Primeiro dia do mês corrente em Luanda */
export function inicioMesLuanda(agora: Date = new Date()): string {
  return `${diaLuanda(0, agora).slice(0, 8)}01`;
}

/** "923 456 789" ou "+244923456789" -> "+244923456789"; null se não for um número angolano */
export function telefoneInternacional(texto: string): string | null {
  const digitos = texto.replace(/\D/g, '').replace(/^(00)?244/, '');
  return /^9\d{8}$/.test(digitos) ? `+244${digitos}` : null;
}

export const nomeMotivo: Record<string, string> = {
  limite_semanal: 'Limite semanal atingido',
  limite_local: 'Muitos amigos da mesma pessoa no mesmo local residencial',
  numero_pagamento_partilhado: 'Mesmo número de levantamento',
  mesmo_dispositivo: 'Mesmo dispositivo',
};

export const nomeMetodo: Record<string, string> = {
  multicaixa_express: 'Multicaixa Express',
  unitel_money: 'Unitel Money',
};

export const nomeEstadoPedido: Record<string, string> = {
  pendente: 'Novo',
  confirmado: 'Confirmado',
  em_preparacao: 'Em preparação',
  em_entrega: 'A caminho',
  entregue_pago: 'Entregue',
  cancelado: 'Cancelado',
  estornado: 'Estornado',
};

/** Leitura automática de um comprovativo, em palavras */
export function textoLeitura(estado: string | undefined, valor?: number | null, referencia?: string | null): { texto: string; alerta: boolean } {
  switch (estado) {
    case 'confere':
      return { texto: 'Leitura automática: valor e referência conferem.', alerta: false };
    case 'diverge':
      return {
        texto: `Leitura automática NÃO confere: leu ${valor != null ? formatarKz(valor) : 'outro valor'}${referencia ? `, ref. ${referencia}` : ''}.`,
        alerta: true,
      };
    case 'ilegivel':
      return { texto: 'Leitura automática: foto ilegível. Confere com atenção.', alerta: true };
    case 'indisponivel':
      return { texto: 'Leitura automática indisponível: confere à mão.', alerta: false };
    case 'pendente':
    case 'a_ler':
      return { texto: 'Leitura automática a decorrer…', alerta: false };
    default:
      return { texto: '', alerta: false };
  }
}

export const nomeEstadoExtrato: Record<string, string> = {
  aguarda_ficheiro: 'À espera do ficheiro',
  por_ler: 'À espera da leitura automática',
  a_ler: 'A ler…',
  lido: 'Lido automaticamente',
  ilegivel: 'Ilegível: escreve as entradas à mão',
  indisponivel: 'Leitura automática indisponível: escreve as entradas à mão',
  manual: 'Entradas escritas à mão',
};

/** Um passo do histórico do pedido, em palavras */
export function descreverEvento(acao: string, d: Record<string, unknown> | null): string {
  const kz = (v: unknown) => formatarKz(Number(v));
  switch (acao) {
    case 'pedido_criado':
      return 'Fez o pedido';
    case 'pedido_estado':
      return `Mudou para «${nomeEstadoPedido[String(d?.para)] ?? String(d?.para)}»${d?.motivo ? ` (${String(d.motivo)})` : ''}`;
    case 'pedido_pagador_distinto':
      return 'Marcou "pago por outra pessoa"';
    case 'venda_gerada':
      return `Venda registada (${kz(d?.valor_final)}${d?.posto ? `, caixa ${String(d.posto)}` : ''})`;
    case 'comprovativo_registado':
      return `Registou o pagamento ${String(d?.metodo ?? '')} de ${kz(d?.valor)}, ref. ${String(d?.referencia ?? '')}`;
    case 'comprovativo_lido':
      return textoLeitura(String(d?.resultado), d?.valor as number | null, d?.referencia as string | null).texto;
    case 'comprovativo_conferido':
      return `Conferiu o pagamento ref. ${String(d?.referencia ?? '')}`;
    case 'comprovativo_rejeitado':
      return `Rejeitou o pagamento ref. ${String(d?.referencia ?? '')}: ${String(d?.nota ?? '')}`;
    case 'leitura_pedida':
      return 'Pediu outra leitura automática';
    case 'extrato_automatica':
    case 'extrato_manual':
    case 'extrato_ligado':
      return `Encontrado no extrato ${String(d?.conta ?? '')} (${formatarDia(String(d?.data ?? ''))}, ${kz(d?.valor)})`;
    case 'caixa_fechada':
      return `Fechou a caixa ${String(d?.posto ?? '')}`;
    default:
      return acao.replace(/_/g, ' ');
  }
}

/** Linhas CSV (separador ";" e vírgula decimal, como o Excel em português) */
export function paraCsv(linhas: (string | number | null | undefined)[][]): string {
  return linhas
    .map((l) =>
      l
        .map((c) => {
          const t = c === null || c === undefined ? '' : typeof c === 'number' ? String(c).replace('.', ',') : c;
          return /[";\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
        })
        .join(';'),
    )
    .join('\n');
}

const mensagens: Record<string, string> = {
  sem_permissao: 'Não tens permissão para esta acção.',
  permissao_fotos: 'Autoriza o acesso à câmara ou às fotos nas definições do telemóvel.',
  sem_sessao: 'Entra na tua conta para continuar.',
  motivo_obrigatorio: 'Escreve o motivo.',
  referencia_obrigatoria: 'Escreve a referência do pagamento.',
  estado_invalido: 'O estado mudou entretanto. Actualiza a lista.',
  transicao_invalida: 'Esta mudança de estado não é possível.',
  caixa_obrigatoria: 'Escolhe a caixa onde o dinheiro entrou.',
  caixa_invalida: 'A caixa escolhida já não está aberta.',
  caixa_ja_aberta: 'Este posto já tem uma caixa aberta. Fecha-a antes de abrir outra.',
  caixa_fechada: 'Esta caixa já foi fechada.',
  caixa_inexistente: 'Caixa não encontrada.',
  conta_invalida: 'Escreve o nome da conta (ex.: Multicaixa Express BAI).',
  extrato_inexistente: 'Extrato não encontrado.',
  ficheiro_inexistente: 'O ficheiro do extrato não chegou. Tenta enviar outra vez.',
  movimento_inexistente: 'Entrada do extrato não encontrada.',
  comprovativo_ja_ligado: 'Esse comprovativo já está ligado a outra entrada do extrato.',
  data_fora_do_periodo: 'A data está fora do período do extrato.',
  tipo_invalido: 'Pedido inválido.',
  comprovativo_obrigatorio: 'Tira a foto do comprovativo de cada pagamento electrónico.',
  referencia_repetida: 'Esta referência já foi usada noutro pedido. Confirma o comprovativo.',
  metodo_invalido: 'Forma de pagamento inválida.',
  comprovativos_por_conferir: 'Confere os pagamentos electrónicos antes de fechar a caixa.',
  comprovativo_inexistente: 'Comprovativo não encontrado.',
  nota_obrigatoria: 'Escreve uma nota a explicar a decisão.',
  posto_invalido: 'Escreve o nome do posto (ex.: Balcão).',
  valor_invalido: 'Valor inválido.',
  cozinha_inexistente: 'Cozinha não encontrada.',
  observacao_longa: 'A observação é demasiado longa.',
  adesao_inexistente: 'Adesão não encontrada.',
  pedido_em_curso: 'O cliente tem um pedido a meio pago com o pacote. Reembolsa depois da entrega.',
  parcelas_nao_somam_valor_final: 'Os pagamentos não somam o valor a receber.',
  parametro_invalido: 'Valor de parâmetro inválido.',
  numero_invalido: 'Número de telefone inválido.',
  periodo_invalido: 'Período inválido.',
  nivel_invalido: 'Nível inválido.',
  avaliacao_inexistente: 'A avaliação já não existe.',
  foto_inexistente: 'A foto já não existe.',
  decisao_invalida: 'Decisão inválida.',
  grupo_inexistente: 'O grupo já não existe.',
  grupo_em_preparacao: 'O grupo já está em preparação e não pode ser cancelado.',
  pedido_inexistente: 'O pedido já não existe.',
  funcionalidade_inexistente: 'Funcionalidade desconhecida.',
  reclamacao_inexistente: 'A reclamação já não existe.',
  reclamacao_decidida: 'Esta reclamação já foi respondida.',
  resposta_obrigatoria: 'Escreve a resposta ao cliente.',
  estimulo_inexistente: 'O estímulo já não existe.',
  estimulo_decidido: 'Este estímulo já foi decidido.',
  caso_inexistente: 'O caso já não existe.',
  caso_decidido: 'Este caso já foi decidido.',
  limite_diario: 'Chegaste ao limite de perguntas de hoje. Tenta amanhã.',
  texto_curto: 'Escreve a pergunta com um pouco mais de detalhe.',
  funcionalidade_inactiva: 'Esta funcionalidade está desligada. Liga-a em Parâmetros e interruptores.',
};

export function mensagemErro(erro: unknown): string {
  const texto =
    typeof erro === 'string'
      ? erro
      : erro && typeof erro === 'object' && 'message' in erro
        ? String((erro as { message: unknown }).message)
        : '';
  return mensagens[texto.trim()] ?? 'Não foi possível concluir. Verifica a ligação e tenta outra vez.';
}

/** I9: unidade sugerida para um ingrediente, pela medida do produto */
export function unidadePorDefeito(medida: string | null | undefined): string {
  return medida === 'Volume' ? 'ml' : medida === 'Unidade' ? 'un' : 'g';
}

/** I9: ingredientes editados (quantidade em texto, vírgula decimal) para guardar; ignora linhas vazias ou a zero */
export function componentesParaGuardar(
  linhas: { produto_id: string; quantidade: string; unidade: string }[],
): { produto_id: string; quantidade: number; unidade: string }[] {
  return linhas
    .map((l) => ({ produto_id: l.produto_id, quantidade: Number(l.quantidade.replace(',', '.')), unidade: l.unidade.trim() }))
    .filter((l) => l.produto_id && Number.isFinite(l.quantidade) && l.quantidade > 0);
}

export const nomeCategoria: Record<string, string> = {
  atraso: 'Atraso',
  qualidade: 'Qualidade da comida',
  quantidade: 'Faltou alguma coisa',
  pedido_errado: 'Pedido errado',
  estafeta: 'Estafeta',
  pagamento: 'Pagamento',
  app: 'App',
  outro: 'Outro',
};

export const nomeCompensacao: Record<string, string> = {
  nenhuma: 'Nenhuma',
  pedido_desculpa: 'Pedido de desculpa',
  desconto: 'Desconto no próximo',
  reembolso_parcial: 'Reembolso parcial',
  reembolso_total: 'Reembolso total',
};

/** O que a análise automática achou da reclamação, numa linha */
export function textoAnalise(r: { ia_estado: string; ia_procedente: string | null; ia_gravidade: string | null; ia_nota: string | null }): string {
  if (r.ia_estado === 'pendente' || r.ia_estado === 'a_analisar') return 'Análise automática: a analisar…';
  if (r.ia_estado === 'indisponivel') return `Análise automática indisponível${r.ia_nota ? ` (${r.ia_nota})` : ''}: decide pelos factos.`;
  const razao = r.ia_procedente === 'sim' ? 'os factos dão razão ao cliente' : r.ia_procedente === 'nao' ? 'os factos não dão razão ao cliente' : 'os factos não chegam para saber';
  return `Análise automática: ${razao}${r.ia_gravidade ? ` · gravidade ${r.ia_gravidade === 'media' ? 'média' : r.ia_gravidade}` : ''}.`;
}

/** Nome da métrica dos estímulos */
export const nomeMetrica: Record<string, string> = {
  pct_a_horas: '% a horas',
  entregas: 'entregas',
  vendas_balcao: 'vendas ao balcão',
  confirmados: 'pedidos confirmados',
  pedidos: 'pedidos',
};
