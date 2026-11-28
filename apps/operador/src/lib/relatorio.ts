// Relatório da cozinha detalhado: períodos, variação face ao período anterior e exportação
// (CSV e PDF). Puro, para se testar sem o servidor. Ver docs/plano-relatorio-cozinha.md.
import { escaparHtml } from './exportar';
import { diaLuanda, formatarDia, formatarKz } from './formatar';

export type ResumoCozinha = {
  pedidos: number;
  vendas_brutas: number;
  desconto_convite: number;
  saldo_convida: number;
  descontos: number;
  vendas_liquidas: number;
  pago_pacote: number;
  valor_empresa: number;
  taxas_entrega: number;
  ticket_medio: number | null;
  cancelados: number;
  cancelados_valor: number;
  cancelados_cliente: number;
  cancelados_cozinha: number;
  clientes: number;
  clientes_novos: number;
  avaliacao_media: number | null;
  avaliacoes: number;
  a_horas_pct: number | null;
  comissao_percent: number;
  comissao: number;
  /** Parte (%) do desconto de convite e do saldo Convida paga por esta cozinha (0 = plataforma) */
  convida_cozinha_percent?: number;
  /** Valor do Convida descontado à cozinha */
  convida_a_cargo_cozinha?: number;
  a_receber_cozinha: number;
};

/** Texto de quem paga o Convida, para o ecrã e o PDF */
export function quemPagaConvida(r: ResumoCozinha): string {
  const p = Number(r.convida_cozinha_percent ?? 0);
  if (p <= 0) return 'Descontos de convite e saldo Convida pagos pela plataforma (não saem do valor da cozinha).';
  if (p >= 100) return 'Descontos de convite e saldo Convida pagos pela cozinha (saem do valor a receber).';
  const t = String(p).replace('.', ',');
  return `Descontos de convite e saldo Convida: ${t}% pagos pela cozinha, o resto pela plataforma.`;
}

export type RelatorioDetalhado = {
  cozinha: string;
  inicio: string;
  fim: string;
  resumo: ResumoCozinha;
  anterior: ResumoCozinha;
  por_dia: { dia: string; pedidos: number; vendas: number }[];
  por_hora: { hora: number; pedidos: number; vendas: number }[];
  por_dia_semana: { dow: number; pedidos: number; vendas: number }[] | null;
  pratos: { cardapio_id: string | null; nome: string; qtd: number; receita: number; pct: number | null }[];
  opcoes_montados: { nome: string; qtd: number }[];
  montado_valor_medio: number | null;
  sem_vendas: string[];
  pagamentos: { metodo: string; pedidos: number; valor: number }[];
  tempo_medio_min: number | null;
  agendados: number;
  grupo_empresa: number;
  cancelamentos_motivos: { motivo: string; n: number }[];
  estafetas: { nome: string; entregas: number; a_horas_pct: number | null }[];
  preparadores: { nome: string; pedidos: number }[];
  zonas: { zona: string; pedidos: number; vendas: number }[];
  estrelas: Record<string, number>;
  reclamacoes: number;
  reclamacoes_abertas: number;
  convida: { pedidos_com_desconto: number; comissoes_geradas: number };
};

export type Rentabilidade = {
  vendas_comida: number;
  cmv: number;
  /** % das vendas com custo definido (o custo dos pratos só é fiável perto de 100%) */
  cobertura_pct: number | null;
  cmv_pct: number | null;
  margem_bruta: number | null;
  despesas: number;
  despesas_por_categoria: { categoria: string; valor: number }[];
  compras: number;
  a_receber_cozinha: number;
  /** a receber − custo dos pratos − despesas; null se faltar custo nalgum prato vendido */
  resultado: number | null;
  pratos: { nome: string; qtd: number; receita: number; custo: number | null; completo: boolean; margem: number | null; margem_pct: number | null }[];
  doses: {
    nome: string;
    dias: number;
    lancadas: number;
    vendidas: number;
    sobras: number;
    dias_esgotou: number;
    hora_media_esgotou: string | null;
    desperdicio: number;
  }[];
};

/** Margem de uma dose em % do preço (null sem custo ou preço) */
export function margemPct(preco: number, custo: number | null): number | null {
  if (custo == null || !preco) return null;
  return Math.round((1000 * (preco - custo)) / preco) / 10;
}

/** Referência do sector: custo da comida entre 28% e 35% das vendas */
export function avaliarCmv(pct: number | null): 'bom' | 'atencao' | 'alto' | null {
  if (pct == null) return null;
  if (pct <= 35) return 'bom';
  if (pct <= 45) return 'atencao';
  return 'alto';
}

/** Tempo de cada etapa do pedido (mediana = o normal; p90 = os 10% piores), em minutos */
export type ChaveEtapa = 'confirmar' | 'comecar' | 'preparar' | 'esperar' | 'entregar' | 'total';
export type TemposEtapas = {
  pedidos: number;
  agendados_fora: number;
  /** Pedidos com "Pronto" marcado (só esses separam preparar de esperar o estafeta) */
  com_pronto?: number;
  etapas: { chave: ChaveEtapa; nome: string; n: number; mediana: number | null; p90: number | null }[];
  gargalo: Exclude<ChaveEtapa, 'total'> | null;
  pontualidade: { com_hora: number; a_tempo: number; atrasados: number; atraso_mediano: number | null };
  por_hora: { hora: string; pedidos: number; total_mediana: number | null; atrasados: number }[];
  estafetas: { nome: string; entregas: number; entrega_mediana: number | null; atrasados: number }[];
  mais_lentos: { pedido_id: string; criado_em: string; total: number; etapa: Exclude<ChaveEtapa, 'total'> | null }[];
};

/** "8 min", "1 h 05", "45 s" */
export function duracao(min: number | null | undefined): string {
  if (min === null || min === undefined) return '-';
  if (min < 1) return `${Math.round(min * 60)} s`;
  if (min < 60) return `${Math.round(min)} min`;
  const h = Math.floor(min / 60);
  return `${h} h ${String(Math.round(min - h * 60)).padStart(2, '0')}`;
}

const NOME_ETAPA: Record<Exclude<ChaveEtapa, 'total'>, string> = {
  confirmar: 'confirmar o pedido',
  comecar: 'começar a preparar',
  preparar: 'preparar',
  esperar: 'esperar o estafeta',
  entregar: 'caminho da entrega',
};
export const nomeEtapa = (c: Exclude<ChaveEtapa, 'total'> | null) => (c ? NOME_ETAPA[c] : '-');

/** O que fazer quando a etapa que mais pesa é esta */
export function conselhoEtapa(c: Exclude<ChaveEtapa, 'total'> | null): string | null {
  switch (c) {
    case 'confirmar':
      return 'Os pedidos ficam à espera de confirmação: alguém no balcão deve confirmar logo que o aviso toca.';
    case 'comecar':
      return 'Entre confirmar e começar há espera: começa a preparar logo após confirmar, ou adianta as bases antes do pico.';
    case 'preparar':
      return 'A preparação é o que mais demora: adianta as bases antes do pico e reserva o estafeta mais cedo.';
    case 'esperar':
      return 'Os pedidos ficam prontos à espera do estafeta: reserva o estafeta mais cedo (ele é avisado quando marcas Pronto).';
    case 'entregar':
      return 'O caminho é o que mais demora: agrupa entregas da mesma zona ou revê as zonas mais longe.';
    default:
      return null;
  }
}

/** Percentagem de cada etapa no tempo normal (para as barras) */
export function pesoEtapas(t: TemposEtapas): { chave: ChaveEtapa; pct: number }[] {
  const partes = t.etapas.filter((e) => e.chave !== 'total');
  const soma = partes.reduce((s, e) => s + (e.mediana ?? 0), 0);
  return partes.map((e) => ({ chave: e.chave, pct: soma > 0 ? Math.round(((e.mediana ?? 0) / soma) * 100) : 0 }));
}

export type PeriodoRel = 'hoje' | 'ontem' | '7' | 'mes' | 'mes_anterior' | 'datas';

/** Datas (de, até) de cada atalho no dia de Luanda; "datas" valida as escritas (máx. 366 dias) */
export function periodoRel(p: PeriodoRel, agora: Date, de?: string, ate?: string): [string, string] | null {
  const hoje = diaLuanda(0, agora);
  if (p === 'hoje') return [hoje, hoje];
  if (p === 'ontem') return [diaLuanda(-1, agora), diaLuanda(-1, agora)];
  if (p === '7') return [diaLuanda(-6, agora), hoje];
  if (p === 'mes') return [`${hoje.slice(0, 8)}01`, hoje];
  if (p === 'mes_anterior') {
    const d = new Date(`${hoje.slice(0, 8)}01T00:00:00Z`);
    d.setUTCDate(0); // último dia do mês anterior
    const fim = d.toISOString().slice(0, 10);
    return [`${fim.slice(0, 8)}01`, fim];
  }
  const ok = (s?: string) => !!s && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));
  if (!ok(de)) return null;
  const f = ok(ate) ? (ate as string) : (de as string);
  if (f < (de as string)) return null;
  const dias = (Date.parse(`${f}T00:00:00Z`) - Date.parse(`${de}T00:00:00Z`)) / 86400000 + 1;
  return dias > 366 ? null : [de as string, f];
}

/** "▲ 12%" / "▼ 5%" / "=" face ao período anterior; vazio se não houver base de comparação */
export function variacao(actual: number | null | undefined, anterior: number | null | undefined): string {
  if (actual == null || anterior == null || anterior === 0) return '';
  const pct = Math.round((100 * (actual - anterior)) / Math.abs(anterior));
  if (pct === 0) return '=';
  return `${pct > 0 ? '▲' : '▼'} ${Math.abs(pct)}%`;
}

const DIAS_SEMANA = ['', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
export const nomeDiaSemana = (dow: number) => DIAS_SEMANA[dow] ?? String(dow);

const pct = (v: number | null | undefined) => (v == null ? '-' : `${String(v).replace('.', ',')}%`);

/** Indicadores principais (secção A), com o valor anterior para a variação */
export function indicadores(r: RelatorioDetalhado): { rotulo: string; valor: string; variacao: string }[] {
  const a = r.resumo;
  const b = r.anterior;
  return [
    { rotulo: 'Vendas brutas (comida)', valor: formatarKz(a.vendas_brutas), variacao: variacao(a.vendas_brutas, b.vendas_brutas) },
    { rotulo: 'Pedidos entregues', valor: String(a.pedidos), variacao: variacao(a.pedidos, b.pedidos) },
    { rotulo: 'Ticket médio', valor: a.ticket_medio == null ? '-' : formatarKz(a.ticket_medio), variacao: variacao(a.ticket_medio, b.ticket_medio) },
    {
      rotulo: `Descontos Convida (${Number(a.convida_cozinha_percent ?? 0) > 0 ? `cozinha paga ${formatarKz(a.convida_a_cargo_cozinha ?? 0)}` : 'pagos pela plataforma'})`,
      valor: formatarKz(a.descontos),
      variacao: '',
    },
    { rotulo: `Comissão da plataforma (${String(a.comissao_percent).replace('.', ',')}%)`, valor: formatarKz(a.comissao), variacao: '' },
    { rotulo: 'A receber pela cozinha', valor: formatarKz(a.a_receber_cozinha), variacao: variacao(a.a_receber_cozinha, b.a_receber_cozinha) },
    { rotulo: 'Taxas de entrega', valor: formatarKz(a.taxas_entrega), variacao: '' },
    {
      rotulo: 'Cancelados (cliente / cozinha)',
      valor: `${a.cancelados} (${a.cancelados_cliente} / ${a.cancelados_cozinha}) · ${formatarKz(a.cancelados_valor)}`,
      variacao: variacao(a.cancelados, b.cancelados),
    },
    { rotulo: 'Clientes · novos', valor: `${a.clientes} · ${a.clientes_novos}`, variacao: variacao(a.clientes, b.clientes) },
    {
      rotulo: 'Avaliação média',
      valor: a.avaliacao_media == null ? `- (${a.avaliacoes})` : `★ ${String(a.avaliacao_media).replace('.', ',')} (${a.avaliacoes})`,
      variacao: '',
    },
    { rotulo: 'Entregas a horas', valor: pct(a.a_horas_pct), variacao: '' },
  ];
}

type Celula = string | number | null;

/** Linhas do CSV (Excel): resumo, por dia, por prato, pagamentos, zonas (+ rentabilidade e doses) */
export function linhasCsvRelatorio(
  r: RelatorioDetalhado,
  rent?: Rentabilidade | null,
  tempos?: TemposEtapas | null,
  zonas?: import('./api').ZonaVendas[] | null,
): Celula[][] {
  const a = r.resumo;
  const extraTempos: Celula[][] = tempos
    ? [
        [],
        ['Etapa', 'Normal (min)', 'Os 10% piores (min)', 'Pedidos'],
        ...tempos.etapas.map((e) => [e.nome, e.mediana, e.p90, e.n]),
        ['Entregues a tempo', tempos.pontualidade.a_tempo, '', tempos.pontualidade.com_hora],
        ['Atraso normal (min)', tempos.pontualidade.atraso_mediano],
      ]
    : [];
  const extra: Celula[][] = rent
    ? [
        [],
        ['Rentabilidade', 'Valor'],
        ['Custo dos pratos (Kz)', rent.cmv],
        ['Custo em % das vendas', rent.cmv_pct],
        ['Vendas com custo definido (%)', rent.cobertura_pct],
        ['Margem bruta (Kz)', rent.margem_bruta],
        ['Despesas (Kz)', rent.despesas],
        ['Compras registadas (Kz)', rent.compras],
        ['Resultado aproximado (Kz)', rent.resultado],
        [],
        ['Prato', 'Qtd', 'Receita (Kz)', 'Custo (Kz)', 'Margem (Kz)', 'Margem (%)'],
        ...rent.pratos.map((p) => [p.nome, p.qtd, p.receita, p.custo, p.margem, p.margem_pct]),
        [],
        ['Doses: prato', 'Dias', 'Lançadas', 'Vendidas', 'Sobras', 'Dias esgotado', 'Esgota em média às', 'Desperdício (Kz)'],
        ...rent.doses.map((d) => [d.nome, d.dias, d.lancadas, d.vendidas, d.sobras, d.dias_esgotou, d.hora_media_esgotou, d.desperdicio]),
      ]
    : [];
  return [
    ['Cozinha', r.cozinha],
    ['Período', `${r.inicio} a ${r.fim}`],
    [],
    ['Indicador', 'Valor', 'Período anterior'],
    ['Pedidos entregues', a.pedidos, r.anterior.pedidos],
    ['Vendas brutas (Kz)', a.vendas_brutas, r.anterior.vendas_brutas],
    ['Desconto de convite (Kz)', a.desconto_convite, r.anterior.desconto_convite],
    ['Saldo Convida usado (Kz)', a.saldo_convida, r.anterior.saldo_convida],
    ['Ticket médio (Kz)', a.ticket_medio, r.anterior.ticket_medio],
    ['Comissão (%)', a.comissao_percent, r.anterior.comissao_percent],
    ['Comissão (Kz)', a.comissao, r.anterior.comissao],
    ['Convida pago pela cozinha (%)', a.convida_cozinha_percent ?? 0, r.anterior.convida_cozinha_percent ?? 0],
    ['Convida a cargo da cozinha (Kz)', a.convida_a_cargo_cozinha ?? 0, r.anterior.convida_a_cargo_cozinha ?? 0],
    ['A receber pela cozinha (Kz)', a.a_receber_cozinha, r.anterior.a_receber_cozinha],
    ['Taxas de entrega (Kz)', a.taxas_entrega, r.anterior.taxas_entrega],
    ['Cancelados', a.cancelados, r.anterior.cancelados],
    ['Clientes', a.clientes, r.anterior.clientes],
    ['Clientes novos', a.clientes_novos, r.anterior.clientes_novos],
    ['Avaliação média', a.avaliacao_media, r.anterior.avaliacao_media],
    ['Entregas a horas (%)', a.a_horas_pct, r.anterior.a_horas_pct],
    [],
    ['Dia', 'Pedidos', 'Vendas (Kz)'],
    ...r.por_dia.map((d) => [d.dia, d.pedidos, d.vendas]),
    [],
    ['Prato', 'Quantidade', 'Receita (Kz)', '% das vendas'],
    ...r.pratos.map((p) => [p.nome, p.qtd, p.receita, p.pct]),
    [],
    ['Forma de pagamento', 'Pedidos', 'Valor (Kz)'],
    ...r.pagamentos.map((p) => [p.metodo, p.pedidos, p.valor]),
    [],
    ['Zona', 'Pedidos', 'Vendas (Kz)'],
    ...r.zonas.map((z) => [z.zona, z.pedidos, z.vendas]),
    ...extra,
    ...extraTempos,
    ...(zonas && zonas.length ? [[], ...linhasCsvZonas(zonas)] : []),
  ];
}

function tabela(cab: string[], linhas: Celula[][]): string {
  if (linhas.length === 0) return '<p class="suave">Sem dados.</p>';
  const th = cab.map((c) => `<th>${escaparHtml(c)}</th>`).join('');
  const tr = linhas.map((l) => `<tr>${l.map((c) => `<td>${escaparHtml(String(c ?? '-'))}</td>`).join('')}</tr>`).join('');
  return `<table><tr>${th}</tr>${tr}</table>`;
}

/** PDF pronto a imprimir ou enviar: só as secções com dados, sem telefones de clientes */
export function htmlRelatorio(
  r: RelatorioDetalhado,
  geradoPor: string,
  agora: Date,
  rent?: Rentabilidade | null,
  tempos?: TemposEtapas | null,
  zonas?: import('./api').ZonaVendas[] | null,
): string {
  const ind = indicadores(r).map((i) => [i.rotulo, i.valor, i.variacao]);
  const sec = (titulo: string, corpo: string) => `<h2>${escaparHtml(titulo)}</h2>${corpo}`;
  const partes = [
    sec('Resumo', tabela(['Indicador', 'Valor', 'vs anterior'], ind)),
    r.por_dia.length > 1 ? sec('Vendas por dia', tabela(['Dia', 'Pedidos', 'Vendas'], r.por_dia.map((d) => [formatarDia(d.dia), d.pedidos, formatarKz(d.vendas)]))) : '',
    r.por_hora.length ? sec('Por hora', tabela(['Hora', 'Pedidos', 'Vendas'], r.por_hora.map((h) => [`${h.hora}h`, h.pedidos, formatarKz(h.vendas)]))) : '',
    r.pratos.length ? sec('Pratos', tabela(['Prato', 'Qtd', 'Receita', '%'], r.pratos.map((p) => [p.nome, p.qtd, formatarKz(p.receita), pct(p.pct)]))) : '',
    r.opcoes_montados.length ? sec('Opções mais escolhidas (montados)', tabela(['Opção', 'Qtd'], r.opcoes_montados.map((o) => [o.nome, o.qtd]))) : '',
    r.pagamentos.length ? sec('Pagamentos', tabela(['Forma', 'Pedidos', 'Valor'], r.pagamentos.map((p) => [p.metodo, p.pedidos, formatarKz(p.valor)]))) : '',
    tempos && tempos.pedidos > 0
      ? sec(
          'Tempo de cada etapa',
          tabela(['Etapa', 'Normal', 'Os 10% piores'], tempos.etapas.map((e) => [e.nome, duracao(e.mediana), duracao(e.p90)])) +
            `<p class="suave">Onde se perde mais tempo: ${escaparHtml(nomeEtapa(tempos.gargalo))}. A tempo: ${tempos.pontualidade.a_tempo} de ${tempos.pontualidade.com_hora}.</p>`,
        )
      : '',
    r.cancelamentos_motivos.length ? sec('Cancelamentos', tabela(['Motivo', 'N.º'], r.cancelamentos_motivos.map((c) => [c.motivo, c.n]))) : '',
    r.estafetas.length ? sec('Estafetas', tabela(['Estafeta', 'Entregas', 'A horas'], r.estafetas.map((e) => [e.nome, e.entregas, pct(e.a_horas_pct)]))) : '',
    r.zonas.length ? sec('Zonas', tabela(['Zona', 'Pedidos', 'Vendas'], r.zonas.map((z) => [z.zona, z.pedidos, formatarKz(z.vendas)]))) : '',
    zonas && zonas.length
      ? sec('O que mais sai em cada zona', tabela(['Zona', 'Prato', 'Qtd', 'vs anterior'],
          zonas.flatMap((z) => z.pratos.map((p) => [z.zona, p.nome, p.qtd, tendencia(p.qtd, p.qtd_anterior)]))))
      : '',
    rent && rent.vendas_comida > 0
      ? sec(
          'Rentabilidade',
          tabela(['Indicador', 'Valor'], [
            ['Custo dos pratos', `${formatarKz(rent.cmv)} (${pct(rent.cmv_pct)} das vendas)`],
            ['Vendas com custo definido', pct(rent.cobertura_pct)],
            ['Margem bruta', rent.margem_bruta == null ? '-' : formatarKz(rent.margem_bruta)],
            ['Despesas', formatarKz(rent.despesas)],
            ['Resultado aproximado', rent.resultado == null ? '- (faltam custos)' : formatarKz(rent.resultado)],
          ]),
        )
      : '',
    rent?.doses.length
      ? sec('Doses: esgotados e sobras', tabela(['Prato', 'Esgotou', 'Às (média)', 'Sobras', 'Desperdício'],
          rent.doses.map((d) => [d.nome, `${d.dias_esgotou} de ${d.dias} dias`, d.hora_media_esgotou ?? '-', d.sobras, formatarKz(d.desperdicio)])))
      : '',
  ].join('');
  return `<html><head><meta charset="utf-8"><style>
    body{font-family:sans-serif;padding:20px;color:#1A1A1A} h1{color:#B5121B;margin:0} h2{font-size:15px;margin:18px 0 6px;color:#B5121B}
    table{border-collapse:collapse;width:100%} td,th{padding:4px 8px;border-bottom:1px solid #eee;font-size:12px;text-align:left}
    .suave{color:#5F6368;font-size:12px}
  </style></head><body>
    <h1>Manda Bué · Relatório da cozinha</h1>
    <p><b>${escaparHtml(r.cozinha)}</b> · ${escaparHtml(formatarDia(r.inicio))} a ${escaparHtml(formatarDia(r.fim))}</p>
    <p class="suave">Gerado por ${escaparHtml(geradoPor)} em ${escaparHtml(agora.toLocaleString('pt-PT'))}. ${escaparHtml(quemPagaConvida(r.resumo))}</p>
    ${partes}
  </body></html>`;
}

/** Linhas do CSV (Excel) do relatório de saldos expirados */
export function linhasCsvExpirados(r: import('./api').RelatorioExpirados): (string | number | null)[][] {
  return [
    ['Saldos expirados do Convida', `${r.periodo.inicio} a ${r.periodo.fim}`],
    ['Validade (meses)', r.validade_meses],
    ['Total expirado (Kz)', r.resumo.total],
    ['Clientes', r.resumo.clientes],
    ['Expirações', r.resumo.expiracoes],
    ['Avisados antes', r.resumo.avisados],
    ['Saldo activo de todos (Kz)', r.saldo_activo_total],
    ['A expirar em 30 / 60 / 90 dias (Kz)', `${r.a_expirar.d30} / ${r.a_expirar.d60} / ${r.a_expirar.d90}`],
    [],
    ['Mês', 'Valor (Kz)', 'Clientes'],
    ...r.por_mes.map((m) => [m.mes, m.valor, m.clientes]),
    [],
    ['Data', 'Cliente', 'Telefone', 'Código', 'Nível', 'Expirou (Kz)', 'Ganhos antigos (Kz)', 'Já usado (Kz)', 'Saldo antes (Kz)', 'Avisado'],
    ...r.lista.map((l) => [
      l.data.slice(0, 10), l.nome, l.telefone, l.codigo, l.nivel, l.valor, l.ganhos_antigos, l.usado, l.saldo_antes, l.avisado ? 'sim' : 'não',
    ]),
    [],
    ['A expirar: cliente', 'Telefone', 'Em 30 dias (Kz)', 'Em 90 dias (Kz)', 'Expira a partir de', 'Saldo actual (Kz)'],
    ...r.a_expirar_lista.map((a) => [a.nome, a.telefone, a.em_30_dias, a.valor, a.expira_em ? a.expira_em.slice(0, 10) : null, a.saldo]),
  ];
}

/** Variação de um prato face ao período anterior: "novo", "▲ 150%", "▼ 20%", "=" */
export function tendencia(qtd: number, anterior: number): string {
  if (anterior <= 0) return qtd > 0 ? 'novo' : '';
  if (qtd === anterior) return '=';
  const pct = Math.round(((qtd - anterior) / anterior) * 100);
  return pct > 0 ? `▲ ${pct}%` : `▼ ${Math.abs(pct)}%`;
}

/** Linhas do CSV: o que mais sai em cada zona */
export function linhasCsvZonas(zonas: import('./api').ZonaVendas[]): (string | number | null)[][] {
  return [
    ['Zona', 'Prato', 'Quantidade', 'Valor (Kz)', 'Período anterior', 'Cozinha que mais vende'],
    ...zonas.flatMap((z) => z.pratos.map((p) => [z.zona, p.nome, p.qtd, p.receita, p.qtd_anterior, p.cozinha_top ?? null])),
    [],
    ['Zona', 'Opção (montados)', 'Quantidade'],
    ...zonas.flatMap((z) => z.opcoes.map((o) => [z.zona, o.nome, o.qtd])),
  ];
}
