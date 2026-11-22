import type { Amigo, EstadoPedido, MetodoAntes, ModoGrupo, Parametros, Saldo, TipoGrupo } from './tipos';

/** 125 -> "2:05" (contagem decrescente, minutos:segundos) */
export function minutosSegundos(segundos: number): string {
  const s = Math.max(0, Math.round(segundos));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

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

/** Onde se junta o grupo: o rótulo e a frase do convite (Cialdini: unidade — «a nossa família») */
export const TIPOS_GRUPO: { valor: TipoGrupo; rotulo: string; convite: string }[] = [
  { valor: 'trabalho', rotulo: '💼 Trabalho', convite: 'Vamos pedir juntos o almoço na Cozinha da Alexandra!' },
  { valor: 'familia', rotulo: '👨‍👩‍👧 Família', convite: 'Almoço de família na Cozinha da Alexandra! Cada um escolhe o seu prato.' },
  { valor: 'vizinhos', rotulo: '🏘️ Vizinhos', convite: 'Vizinhos, vamos pedir juntos na Cozinha da Alexandra e dividir a entrega!' },
  { valor: 'igreja', rotulo: '⛪ Igreja', convite: 'Almoço do nosso grupo da igreja na Cozinha da Alexandra! Cada um escolhe o seu prato.' },
];

/** Mensagem de partilha do grupo (C12) */
export function mensagemGrupo(hora: string, local: string | null, link: string, tipo: TipoGrupo = 'trabalho'): string {
  const abertura = (TIPOS_GRUPO.find((t) => t.valor === tipo) ?? TIPOS_GRUPO[0]).convite;
  return `${abertura} Entrega às ${hora}${local ? ` em ${local}` : ''}. Junta o teu pedido: ${link}`;
}

/** Quem paga no grupo, em poucas palavras */
export const nomeModoGrupo: Record<ModoGrupo, string> = {
  individual: 'cada um paga a sua parte',
  quem_recebe: 'quem recebe paga tudo na entrega',
  empresa: 'a empresa paga tudo',
};

export const nomeMetodoAntes: Record<MetodoAntes, string> = {
  multicaixa_express: 'Multicaixa Express',
  unitel_money: 'Unitel Money',
};

/** "★ 4,5 · 12 avaliações" */
/** Texto da média de avaliações (sem a estrela — essa é um ícone dourado, ver MediaAvaliacao) */
export function formatarMedia(media: number, total: number): string {
  return `${media.toFixed(1).replace('.', ',')} · ${total} ${total === 1 ? 'avaliação' : 'avaliações'}`;
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
export function mensagemConvite(codigo: string, descontoIndicado: number, link: string, minimo = 0): string {
  const condicao = minimo > 0 ? ` (em pedidos acima de ${formatarKz(minimo)})` : '';
  return (
    `🍲 Peço na Cozinha da Alexandra e recomendo! ` +
    `Usa o meu código ${codigo} e ganhas ${formatarKz(descontoIndicado)} de desconto no teu 1.º pedido${condicao}. ` +
    `👉 ${link}`
  );
}

/** Texto das regras (secção 4.13, "Como funciona"), com os valores de `parametros` */
/** Campos dos parâmetros que as regras do Convida usam (o visitante recebe só estes) */
export type RegrasConvida = Pick<
  Parametros,
  | 'ganho_por_pedido'
  | 'duracao_dias'
  | 'comissao_primeiro_pedido'
  | 'desconto_indicado'
  | 'desconto_subtotal_minimo'
  | 'levantamento_minimo'
  | 'validade_saldo_meses'
  | 'limite_verificacao_semanal'
  | 'bonus_boas_vindas'
  | 'limiar_embaixador'
  | 'limiar_ouro'
  | 'ganho_por_pedido_embaixador'
  | 'ganho_por_pedido_ouro'
>;

export function textoRegras(p: RegrasConvida): string[] {
  const minimo = p.desconto_subtotal_minimo ?? 0;
  return [
    p.comissao_primeiro_pedido
      ? `Ganhas ${formatarKz(p.ganho_por_pedido)} por cada pedido entregue e pago dos amigos que convidares, durante ${p.duracao_dias} dias a contar do primeiro pedido deles. Não há limite de ganhos.`
      : `Ganhas ${formatarKz(p.ganho_por_pedido)} por cada pedido entregue e pago dos amigos que convidares, a partir do 2.º pedido deles, durante ${p.duracao_dias} dias a contar do primeiro. Não há limite de ganhos.`,
    `O teu amigo também ganha: ${formatarKz(p.desconto_indicado)} de desconto no primeiro pedido, válido apenas para contas novas${
      minimo > 0 ? ` e pedidos a partir de ${formatarKz(minimo)}` : ''
    }.`,
    `Usa ou levanta. Podes usar o saldo em refeições a qualquer momento, ou levantá-lo por Multicaixa Express ou Unitel Money a partir de ${formatarKz(p.levantamento_minimo)}, sem taxas.${
      p.validade_saldo_meses ? ` O saldo é válido durante ${p.validade_saldo_meses} meses.` : ''
    }`,
    `Verificação. Se ganhares mais de ${formatarKz(p.limite_verificacao_semanal)} numa semana, confirmamos os pedidos antes de pagar. Isto demora até 6 horas.`,
    'Lista de destaques. Se aceitares, os teus ganhos reais podem aparecer na lista com um pseudónimo. Podes sair quando quiseres.',
    'Para ser justo para todos, não contam os ganhos de contas falsas nem de pedidos cancelados, reembolsados ou não pagos. Se um pedido for reembolsado depois, o valor correspondente é retirado do saldo.',
  ];
}

/**
 * "mb-4821 ", "MB 4821", "MB4821" ou só "4821" -> "MB4821" (o formato da plataforma, sem hífen;
 * os links antigos com "MB-4821" continuam a valer). null se não tiver o formato do código.
 */
export function normalizarCodigo(texto: string | null | undefined): string | null {
  const limpo = (texto ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (/^\d{4,6}$/.test(limpo)) return `MB${limpo}`;
  return /^MB\d{4,6}$/.test(limpo) ? limpo : null;
}

/** Só os dígitos do código (para o campo com o «MB» fixo): "MB-4821" -> "4821" */
export function digitosCodigo(texto: string | null | undefined): string {
  return (texto ?? '').toUpperCase().replace(/^\s*MB/, '').replace(/\D/g, '').slice(0, 6);
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

/** Cor de cada estado, para um sinal visual na lista e no detalhe (sempre a par do texto, nunca só a cor) */
export const corEstadoPedido: Record<EstadoPedido, string> = {
  pendente: '#1565C0', // Recebido — azul
  confirmado: '#00695C', // Confirmado — verde-azulado
  em_preparacao: '#8A5A00', // Em preparação — âmbar
  em_entrega: '#6A1B9A', // A caminho — roxo
  entregue_pago: '#1E7D32', // Entregue — verde
  cancelado: '#5F6368', // Cancelado — cinzento
  estornado: '#5F6368', // Estornado — cinzento
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
  pedido_minimo: 'O desconto de convite é para pedidos a partir do valor mínimo.',
  // registo
  nome_invalido: 'Escreve o teu nome.',
  nif_obrigatorio: 'Para empresas, o NIF é obrigatório.',
  telefone_nao_confirmado: 'Confirma o teu número de telefone primeiro.',
  telefone_ja_associado: 'Este número já está associado a outra conta. Fala connosco.',
  // pedidos
  pedido_vazio: 'O carrinho está vazio.',
  item_indisponivel: 'Um dos pratos já não está disponível. Actualiza o carrinho.',
  opcao_invalida: 'Uma das opções escolhidas já não está disponível. Volta a montar o prato.',
  doses_esgotadas: 'Já não há doses suficientes de um dos pratos. Reduz a quantidade ou escolhe outro prato.',
  item_sem_preco: 'Um dos pratos tem de ser montado (escolhe as opções) antes de o pedires.',
  componentes_todos_excluidos: 'Não podes tirar todos os ingredientes de um prato.',
  componentes_invalidos: 'Um dos ingredientes que tiraste já não faz parte do prato. Volta a montá-lo.',
  opcoes_em_falta: 'Falta escolher uma opção obrigatória de um prato montado, ou já não há nenhuma disponível. Volta a montar o prato.',
  opcoes_a_mais: 'Escolheste opções a mais para um dos pratos.',
  posicao_invalida: 'Localização inválida.',
  pacotes_inactivos: 'Os pacotes não estão disponíveis neste momento.',
  pacote_indisponivel: 'Este pacote já não está disponível.',
  adesao_pendente: 'Já tens uma adesão à espera de pagamento.',
  adesao_inexistente: 'Adesão não encontrada.',
  sem_pacote: 'Não tens um pacote activo com refeições disponíveis.',
  pausa_invalida: 'Não podes pausar tantos dias.',
  quantidade_invalida: 'Quantidade inválida.',
  abaixo_do_minimo: 'Um dos pratos montados ainda não chega ao valor mínimo para servir. Volta a montá-lo e acrescenta opções.',
  cozinha_indisponivel: 'Esta cozinha não está a aceitar pedidos neste momento. Tenta mais tarde ou escolhe outra cozinha.',
  so_membros_condominio: 'Esta cozinha é só para os moradores da lista do condomínio.',
  fora_do_condominio: 'A cozinha do condomínio só entrega dentro do condomínio. Escolhe o endereço da tua casa lá.',
  condominio_sem_grupos: 'A cozinha do condomínio não aceita pedidos de grupo.',
  lista_fechada: 'A lista deste condomínio está fechada (completa ou fora do prazo).',
  casa_obrigatoria: 'Indica o bloco ou o número da casa.',
  condominio_inexistente: 'Este link de condomínio já não é válido.',
  itens_a_mais: 'O pedido tem pratos a mais. Divide-o em dois pedidos.',
  itens_invalidos: 'O carrinho tem um prato inválido. Esvazia o carrinho e volta a escolher.',
  prato_invalido: 'Um dos pratos já não existe. Esvazia o carrinho e volta a escolher.',
  componentes_sem_prato: 'Um dos pratos já não permite tirar ingredientes. Volta a montá-lo.',
  agendamento_invalido: 'A hora de entrega tem de ser entre 20 minutos e 14 dias a partir de agora. Escolhe outra hora.',
  utilizador_bloqueado: 'Esta conta está bloqueada. Fala connosco pelos contactos da app.',
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
  sem_compra_propria: 'Para levantar o saldo, faz primeiro um pedido teu (entregue e pago).',
  prazo_terminado: 'Já passaram mais de 7 dias desde o pedido.',
  texto_curto: 'Conta-nos um pouco mais sobre o que aconteceu.',
  reclamacao_existente: 'Já enviaste uma reclamação sobre este pedido.',
  metodo_invalido: 'Escolhe Multicaixa Express ou Unitel Money.',
  numero_invalido: 'Número de telefone inválido.',
  token_invalido: 'Não foi possível activar as notificações.',
  // avaliações (C9)
  prato_fora_do_pedido: 'Só podes avaliar os pratos deste pedido.',
  limite_fotos: 'Podes juntar no máximo 2 fotos.',
  // pedidos de grupo (C12, C13)
  grupo_ponto_invalido: 'Escolhe um dos teus endereços. Para a empresa pagar, tem de ser um endereço do tipo Trabalho.',
  pagar_antes_indisponivel: 'Neste grupo paga-se na entrega.',
  encomendas_inactivas: 'As encomendas ainda não estão abertas.',
  encomenda_data: 'Escolhe um dia e hora com pelo menos 24 horas de antecedência (e até 30 dias).',
  encomenda_pessoas: 'Há um mínimo de pessoas para encomendar: aumenta o número de pessoas.',
  encomendas_a_mais: 'Já tens 3 encomendas à espera de resposta. Espera por elas ou cancela uma.',
  encomenda_nao_aguarda_resposta: 'Esta encomenda já não está à espera da tua resposta.',
  encomenda_nao_confirmada: 'Confirma primeiro a encomenda.',
  encomenda_nao_cancelavel: 'Esta encomenda já não se pode cancelar aqui. Fala connosco.',
  sinal_ja_pago: 'O sinal já está pago.',
  pedido_ja_nao_aceita_pagamento: 'Este pedido já saiu para entrega: paga ao estafeta.',
  pedido_ja_pago: 'Este pedido já está pago.',
  pagamento_ja_enviado: 'Já enviaste um pagamento: está a ser confirmado.',
  referencia_invalida: 'Escreve a referência da transferência (pelo menos 4 letras ou algarismos).',
  referencia_ja_usada: 'Esta referência já foi usada noutro pagamento. Confirma-a no teu comprovativo.',
  grupo_horas_invalidas: 'O prazo para aderir tem de ser no futuro e pelo menos 15 minutos antes da entrega.',
  grupo_empresa_invalida: 'Só uma conta Empresa pode pagar o pedido de todo o grupo.',
  grupo_fechado: 'Este grupo já fechou. Já não é possível juntar pedidos.',
  grupo_em_preparacao: 'O grupo já está a ser preparado e não pode ser cancelado.',
  funcionalidade_inactiva: 'Esta funcionalidade não está disponível.',
  // atendimento
  texto_invalido: 'Escreve a mensagem (até 1000 caracteres).',
  limite_diario: 'Chegaste ao limite de mensagens de hoje. Tenta amanhã.',
  sem_conversa: 'Escreve primeiro a tua pergunta.',
  sem_permissao: 'Esta opção não está disponível na tua conta.',
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

/**
 * Mensagem para partilhar um prato no WhatsApp (I-partilha). Nome + preço + marca + link para
 * instalar/abrir a app. O precoLabel já vem formatado ("2.500 Kz" ou "desde 2.500 Kz").
 */
export function mensagemPartilhaPrato(
  nome: string,
  marca: string,
  link: string,
  convite?: { codigo: string; desconto: number; minimo?: number } | null,
): string {
  // Enxuta: o cartão de pré-visualização do link já mostra foto + nome + preço. O texto fica com
  // o nome (rede de segurança, se a pré-visualização não aparecer) e a chamada à acção; com
  // código de convite, o benefício do amigo vem primeiro (negrito do WhatsApp).
  // Sem espaços nas pontas: "*Bitoque *" não é negrito no WhatsApp e estraga o resto da frase.
  nome = nome.trim();
  if (convite && convite.desconto > 0) {
    const cond = convite.minimo && convite.minimo > 0 ? ` (pedidos a partir de ${formatarKz(convite.minimo)})` : '';
    return (
      `🍲 Experimenta o *${nome}* da ${marca}! ` +
      `Com o meu código *${convite.codigo}* ganhas *${formatarKz(convite.desconto)} de desconto* no teu 1.º pedido${cond} 👇\n${link}`
    );
  }
  return `🍲 ${nome} — ${marca}\nInstala a app e faz o teu pedido 👇\n${link}`;
}

/** Prova social: "X pessoas pediram este mês" (singular quando é 1) */
export function textoPediram(n: number): string {
  return n === 1 ? '1 pessoa pediu este mês' : `${n} pessoas pediram este mês`;
}

/** Mostra um número angolano agrupado e com indicativo: "958077592" -> "+244 958 077 592" */
export function formatarTelefone(t: string): string {
  const d = t.replace(/\D/g, '');
  const n = d.startsWith('244') ? d.slice(3) : d;
  if (n.length === 9) return `+244 ${n.slice(0, 3)} ${n.slice(3, 6)} ${n.slice(6)}`;
  return t;
}

/** Aviso no carrinho sobre a entrega grátis (null = não mostrar nada) */
export function textoEntregaGratis(o: {
  entrega_gratis?: boolean;
  entrega_gratis_acima?: number | null;
  falta_entrega_gratis?: number | null;
}): string | null {
  if (o.entrega_gratis) return '🎉 Entrega grátis neste pedido!';
  if (o.falta_entrega_gratis && o.falta_entrega_gratis > 0 && o.entrega_gratis_acima)
    return `Junta mais ${formatarKz(o.falta_entrega_gratis)} e a entrega fica grátis (pedidos a partir de ${formatarKz(o.entrega_gratis_acima)}, depois dos descontos).`;
  return null;
}

/** Promoção no carrinho: o desconto já está nos preços; com convite, explica que este fica guardado */
export function textoCampanha(c: { nome: string; poupanca: number }, motivoDesconto?: string | null): string {
  return (
    `🏷️ Promoção «${c.nome}»: já poupas ${formatarKz(c.poupanca)} neste pedido.` +
    (motivoDesconto === 'campanha' ? ' O teu desconto de convite fica guardado para outro pedido (a promoção vale mais).' : '')
  );
}

/** Cartaz de promoção no início */
/** Abaixo disto o «pedido mínimo» de uma campanha não diz nada ao cliente e parece um preço errado (ex.: «2 Kz») */
export const MINIMO_CAMPANHA_VISIVEL = 500;

export function textoPromocao(p: { nome: string; descricao: string | null; tipo: string; valor: number; cozinha: string | null; minimo_pedido: number }): string {
  const oferta = p.descricao ?? (p.tipo === 'percentagem' ? `${p.valor}% de desconto nos pratos` : `Preço especial: ${formatarKz(p.valor)}`);
  // «pedidos a partir de»: é o mínimo do pedido, não o preço de um prato
  const minimo = p.minimo_pedido >= MINIMO_CAMPANHA_VISIVEL ? ` · pedidos a partir de ${formatarKz(p.minimo_pedido)}` : '';
  return `${oferta}${p.cozinha ? ` · ${p.cozinha}` : ''}${minimo}`;
}

/** Percentagem de desconto arredondada (ex.: 4.000 → 3.200 = 20) */
export function percentagemDesconto(preco: number, promo: number): number {
  if (!(preco > 0) || !(promo < preco)) return 0;
  return Math.round(((preco - promo) / preco) * 100);
}

/** Ainda não ganhou nada (nem está nada em verificação ou já recebido) */
export const semGanhos = (s: Saldo) =>
  s.saldo_disponivel <= 0 && s.ganho_semana <= 0 && s.ganho_hoje <= 0 && s.em_verificacao <= 0 && s.total_recebido <= 0;

/** O passo que falta para o primeiro ganho, com o nome do amigo que está mais perto dele */
export function textoPrimeiroGanho(activos: Pick<Amigo, 'primeiro_nome' | 'estado'>[], comissaoPrimeiroPedido: boolean): string {
  // Quem já fez o 1.º pedido está mais perto: o próximo pedido dele já dá ganho
  const jaPediu = activos.find((a) => a.estado === 'activo');
  if (jaPediu) return `O primeiro chega quando ${jaPediu.primeiro_nome} fizer o próximo pedido.`;
  const aEspera = activos[0];
  if (aEspera) return `O primeiro chega quando ${aEspera.primeiro_nome} fizer ${comissaoPrimeiroPedido ? 'o 1.º pedido' : 'o 2.º pedido'}.`;
  return 'O primeiro chega quando um amigo teu usar o teu código e pedir. Partilha-o acima.';
}
