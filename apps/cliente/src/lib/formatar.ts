import type { EstadoPedido, Parametros } from './tipos';

/** 1300 -> "1.300 Kz" (separador de milhares angolano) */
export function formatarKz(valor: number | null | undefined): string {
  const inteiro = Math.round(Number(valor ?? 0));
  const sinal = inteiro < 0 ? '−' : '';
  const digitos = Math.abs(inteiro).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${sinal}${digitos} Kz`;
}

/** "Ana · 23 dias", "Ana · último dia", "Ana · à espera do 1.º pedido", "Ana · terminou" */
export function formatarData(iso: string | null | undefined): string {
  return iso ? new Date(iso).toLocaleDateString('pt-PT') : '';
}

export const nomeEstadoGrupo: Record<string, string> = {
  aberto: 'Aberto',
  fechado: 'Fechado: já não se juntam pedidos',
  em_preparacao: 'Em preparação',
  entregue: 'Entregue',
  cancelado: 'Cancelado',
};

/** "12h30" (hora de Luanda, UTC+1) */
export function horaLuanda(iso: string): string {
  const d = new Date(new Date(iso).getTime() + 60 * 60 * 1000);
  return `${String(d.getUTCHours()).padStart(2, '0')}h${String(d.getUTCMinutes()).padStart(2, '0')}`;
}

/** Tempo que falta: "1 h 05 min", "12 min", "menos de 1 min"; null se já passou */
export function tempoEmFalta(iso: string, agora: Date = new Date()): string | null {
  const ms = new Date(iso).getTime() - agora.getTime();
  if (ms <= 0) return null;
  const min = Math.floor(ms / 60000);
  if (min < 1) return 'menos de 1 min';
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)} h ${String(min % 60).padStart(2, '0')} min`;
}

/** Mensagem de partilha do grupo (C12) */
export function mensagemGrupo(hora: string, local: string | null, link: string): string {
  return `Vamos pedir juntos o almoço no Manda Bué — Delivery Angola! Entrega às ${hora}${local ? ` em ${local}` : ''}. Junta o teu pedido: ${link}`;
}

/** "★ 4,5 · 12 avaliações" */
export function formatarMedia(media: number, total: number): string {
  return `★ ${media.toFixed(1).replace('.', ',')} · ${total} ${total === 1 ? 'avaliação' : 'avaliações'}`;
}

/** Valor na lista de destaques: exacto, em intervalo ("10.000–20.000 Kz") ou escondido (null) */
export function valorDestaque(valor: number | null, min: number | null, max: number | null): string | null {
  if (valor !== null) return formatarKz(valor);
  if (min !== null && max !== null) return `${formatarKz(min).replace(' Kz', '')}–${formatarKz(max)}`;
  return null;
}

/** "Faltam 3 amigos para entrares no top 10." */
export function textoAmigosEmFalta(emFalta: number, tamanhoTop: number): string {
  return `${emFalta === 1 ? 'Falta 1 amigo' : `Faltam ${emFalta} amigos`} para entrares no top ${tamanhoTop}.`;
}

export function textoAmigo(nome: string, estado: string, diasRestantes: number | null): string {
  if (estado === 'aguarda_primeiro_pedido') return `${nome} · à espera do 1.º pedido`;
  if (estado === 'expirado' || diasRestantes === null || diasRestantes <= 0) return `${nome} · terminou`;
  if (diasRestantes === 1) return `${nome} · último dia`;
  return `${nome} · ${diasRestantes} dias`;
}

/** N1: mensagem de partilha enviada pelo próprio cliente */
export function mensagemConvite(codigo: string, descontoIndicado: number, link: string): string {
  return (
    `Estou a pedir no Manda Bué — Delivery Angola e está bom! ` +
    `Usa o meu código ${codigo} e ganhas ${formatarKz(descontoIndicado)} de desconto no primeiro pedido. ${link}`
  );
}

/** Texto das regras (secção 4.13), com os valores de `parametros` */
export function textoRegras(p: Parametros): string[] {
  return [
    `Ganhas ${formatarKz(p.ganho_por_pedido)} por cada pedido dos amigos que convidares, durante ${p.duracao_dias} dias a contar do primeiro pedido deles. Não há limite de ganhos.`,
    `O teu amigo ganha ${formatarKz(p.desconto_indicado)} de desconto no primeiro pedido.`,
    `Levantas o saldo a partir de ${formatarKz(p.levantamento_minimo)} ou usas em refeições. Acima de ${formatarKz(p.limite_verificacao_semanal)} por semana, confirmamos os pedidos antes de pagar.`,
    'Ganhos de contas falsas ou pedidos não pagos são anulados.',
    'Os teus ganhos podem aparecer na lista de destaques com um nome fictício. Podes sair da lista quando quiseres.',
  ];
}

/** "mb-4821 " -> "MB-4821"; devolve null se não tiver o formato do código */
export function normalizarCodigo(texto: string | null | undefined): string | null {
  const limpo = (texto ?? '').trim().toUpperCase().replace(/\s+/g, '');
  const comPrefixo = /^\d{4,5}$/.test(limpo) ? `MB-${limpo}` : limpo.replace(/^MB(?=\d)/, 'MB-');
  return /^MB-\d{4,5}$/.test(comPrefixo) ? comPrefixo : null;
}

/** "923 456 789" ou "+244923456789" -> "+244923456789"; null se não for um número angolano */
export function telefoneInternacional(texto: string): string | null {
  const digitos = texto.replace(/\D/g, '').replace(/^(00)?244/, '');
  return /^9\d{8}$/.test(digitos) ? `+244${digitos}` : null;
}

export const nomeEstadoPedido: Record<EstadoPedido, string> = {
  pendente: 'Recebido',
  confirmado: 'Confirmado',
  em_preparacao: 'Em preparação',
  em_entrega: 'A caminho',
  entregue_pago: 'Entregue',
  cancelado: 'Cancelado',
  estornado: 'Estornado',
};

export const nomeMetodo: Record<string, string> = {
  multicaixa_express: 'Multicaixa Express',
  unitel_money: 'Unitel Money',
};

/** Mensagens para os códigos de erro e de resultado devolvidos pelo servidor */
const mensagens: Record<string, string> = {
  // ligar_indicacao (6.3)
  programa_inactivo: 'O programa de convites não está disponível neste momento.',
  sem_sessao: 'Entra na tua conta para continuar.',
  // apagar_conta
  pedido_em_curso: 'Tens um pedido a meio. Espera pela entrega (ou cancela-o) e depois apaga a conta.',
  levantamento_em_curso: 'Tens um levantamento de saldo por pagar. Espera que seja pago e depois apaga a conta.',
  grupo_em_curso: 'Organizas um pedido de grupo que ainda não terminou. Espera pelo fim (ou cancela-o) e depois apaga a conta.',
  codigo_inexistente: 'Este código não existe. Confirma as letras e os números.',
  proprio_codigo: 'Não podes usar o teu próprio código.',
  ja_ligado: 'Já usaste um código de convite nesta conta.',
  cliente_nao_novo: 'O código de convite é só para clientes que ainda não fizeram nenhum pedido.',
  // desconto (6.4)
  limite_local: 'Este convite já foi usado o número máximo de vezes nesta morada.',
  desconto_em_curso: 'O desconto já está num pedido em curso.',
  desconto_usado: 'O desconto de convite já foi usado.',
  // registo
  nome_invalido: 'Escreve o teu nome.',
  nif_obrigatorio: 'Para empresas, o NIF é obrigatório.',
  telefone_nao_confirmado: 'Confirma o teu número de telefone primeiro.',
  telefone_ja_associado: 'Este número já está associado a outra conta. Fala connosco.',
  // pedidos
  pedido_vazio: 'O carrinho está vazio.',
  item_indisponivel: 'Um dos pratos já não está disponível. Actualiza o carrinho.',
  opcao_invalida: 'Uma das opções escolhidas já não está disponível. Volta a montar o prato.',
  opcoes_em_falta: 'Falta escolher uma opção obrigatória do prato.',
  opcoes_a_mais: 'Escolheste opções a mais para um dos pratos.',
  posicao_invalida: 'Localização inválida.',
  pacotes_inactivos: 'Os pacotes não estão disponíveis neste momento.',
  pacote_indisponivel: 'Este pacote já não está disponível.',
  adesao_pendente: 'Já tens uma adesão à espera de pagamento.',
  adesao_inexistente: 'Adesão não encontrada.',
  sem_pacote: 'Não tens um pacote activo com refeições disponíveis.',
  pausa_invalida: 'Não podes pausar tantos dias.',
  quantidade_invalida: 'Quantidade inválida.',
  ponto_obrigatorio: 'Escolhe o endereço de entrega.',
  ponto_invalido: 'Este endereço não é teu. Escolhe outro.',
  ponto_sem_zona: 'Este endereço não tem zona de entrega. Edita o endereço e escolhe o bairro.',
  estado_invalido: 'O pedido já não está no estado certo para isto.',
  pedido_inexistente: 'Pedido não encontrado.',
  acima_do_valor_do_pedido: 'O saldo usado não pode passar o valor do pedido.',
  valor_invalido: 'Valor inválido.',
  // levantamentos (6.7)
  abaixo_minimo: 'O valor está abaixo do mínimo para levantar.',
  saldo_insuficiente: 'Não tens saldo suficiente.',
  metodo_invalido: 'Escolhe Multicaixa Express ou Unitel Money.',
  numero_invalido: 'Número de telefone inválido.',
  token_invalido: 'Não foi possível activar as notificações.',
  // avaliações (C9)
  prato_fora_do_pedido: 'Só podes avaliar os pratos deste pedido.',
  limite_fotos: 'Podes juntar no máximo 2 fotos.',
  // pedidos de grupo (C12, C13)
  grupo_ponto_invalido: 'O grupo é entregue num dos teus endereços de trabalho. Escolhe um endereço do tipo Trabalho.',
  grupo_horas_invalidas: 'O prazo para aderir tem de ser no futuro e pelo menos 15 minutos antes da entrega.',
  grupo_empresa_invalida: 'Só uma conta Empresa pode pagar o pedido de todo o grupo.',
  grupo_fechado: 'Este grupo já fechou. Já não é possível juntar pedidos.',
  grupo_em_preparacao: 'O grupo já está a ser preparado e não pode ser cancelado.',
  funcionalidade_inactiva: 'Esta funcionalidade não está disponível.',
  sem_permissao: 'Não tens permissão para isto.',
};

/** Extrai o código de um erro do Supabase (mensagem = código) e devolve o texto para o cliente */
export function mensagemErro(erro: unknown): string {
  const texto =
    typeof erro === 'string'
      ? erro
      : erro && typeof erro === 'object' && 'message' in erro
        ? String((erro as { message: unknown }).message)
        : '';
  const codigo = texto.trim();
  return mensagens[codigo] ?? 'Não foi possível concluir. Verifica a ligação e tenta outra vez.';
}

export function mensagemCodigo(codigo: string): string {
  return mensagens[codigo] ?? mensagemErro(codigo);
}

export const nomeMetodoPacote: Record<string, string> = {
  multicaixa_express: 'Multicaixa Express',
  unitel_money: 'Unitel Money',
  loja: 'Na loja',
};

/** I12: benefícios de um pacote, por esta ordem, para o cartão do catálogo */
export function beneficiosPacote(p: {
  refeicoes: number;
  refeicoes_oferta: number;
  valor_refeicao: number;
  preco: number;
  validade_dias: number;
  pausa_max_dias: number;
  entrega_gratis: boolean;
}): string[] {
  const total = p.refeicoes + p.refeicoes_oferta;
  const poupanca = total * p.valor_refeicao - p.preco;
  const linhas = [
    p.refeicoes_oferta > 0
      ? `${total} refeições: ${p.refeicoes} + ${p.refeicoes_oferta} de oferta`
      : `${total} refeições`,
  ];
  if (poupanca > 0) linhas.push(`Poupas ${formatarKz(poupanca)} no mês`);
  if (p.entrega_gratis) linhas.push('Entrega grátis em todos os pedidos pagos com o pacote');
  linhas.push(`Válido por ${p.validade_dias} dias`);
  if (p.pausa_max_dias > 0) linhas.push(`Pausa até ${p.pausa_max_dias} dias (férias, doença)`);
  linhas.push('Reembolso das refeições que não usares');
  return linhas;
}
