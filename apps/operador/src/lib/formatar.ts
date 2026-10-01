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
  limite_local: 'Muitos indicados no mesmo local residencial',
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
  sem_sessao: 'Entra na tua conta para continuar.',
  motivo_obrigatorio: 'Escreve o motivo.',
  referencia_obrigatoria: 'Escreve a referência do pagamento.',
  estado_invalido: 'O estado mudou entretanto. Actualiza a lista.',
  transicao_invalida: 'Esta mudança de estado não é possível.',
  caixa_obrigatoria: 'Escolhe a caixa onde o dinheiro entrou.',
  caixa_invalida: 'A caixa escolhida já não está aberta.',
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
