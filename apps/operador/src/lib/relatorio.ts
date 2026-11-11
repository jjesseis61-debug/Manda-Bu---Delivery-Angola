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
  a_receber_cozinha: number;
};

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

const pct = (v: number | null | undefined) => (v == null ? '—' : `${String(v).replace('.', ',')}%`);

/** Indicadores principais (secção A), com o valor anterior para a variação */
export function indicadores(r: RelatorioDetalhado): { rotulo: string; valor: string; variacao: string }[] {
  const a = r.resumo;
  const b = r.anterior;
  return [
    { rotulo: 'Vendas brutas (comida)', valor: formatarKz(a.vendas_brutas), variacao: variacao(a.vendas_brutas, b.vendas_brutas) },
    { rotulo: 'Pedidos entregues', valor: String(a.pedidos), variacao: variacao(a.pedidos, b.pedidos) },
    { rotulo: 'Ticket médio', valor: a.ticket_medio == null ? '—' : formatarKz(a.ticket_medio), variacao: variacao(a.ticket_medio, b.ticket_medio) },
    { rotulo: 'Descontos (pagos pela plataforma)', valor: formatarKz(a.descontos), variacao: '' },
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
      valor: a.avaliacao_media == null ? `— (${a.avaliacoes})` : `★ ${String(a.avaliacao_media).replace('.', ',')} (${a.avaliacoes})`,
      variacao: '',
    },
    { rotulo: 'Entregas a horas', valor: pct(a.a_horas_pct), variacao: '' },
  ];
}

type Celula = string | number | null;

/** Linhas do CSV (Excel): resumo, por dia, por prato, pagamentos, zonas */
export function linhasCsvRelatorio(r: RelatorioDetalhado): Celula[][] {
  const a = r.resumo;
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
  ];
}

function tabela(cab: string[], linhas: Celula[][]): string {
  if (linhas.length === 0) return '<p class="suave">Sem dados.</p>';
  const th = cab.map((c) => `<th>${escaparHtml(c)}</th>`).join('');
  const tr = linhas.map((l) => `<tr>${l.map((c) => `<td>${escaparHtml(String(c ?? '—'))}</td>`).join('')}</tr>`).join('');
  return `<table><tr>${th}</tr>${tr}</table>`;
}

/** PDF pronto a imprimir ou enviar: só as secções com dados, sem telefones de clientes */
export function htmlRelatorio(r: RelatorioDetalhado, geradoPor: string, agora: Date): string {
  const ind = indicadores(r).map((i) => [i.rotulo, i.valor, i.variacao]);
  const sec = (titulo: string, corpo: string) => `<h2>${escaparHtml(titulo)}</h2>${corpo}`;
  const partes = [
    sec('Resumo', tabela(['Indicador', 'Valor', 'vs anterior'], ind)),
    r.por_dia.length > 1 ? sec('Vendas por dia', tabela(['Dia', 'Pedidos', 'Vendas'], r.por_dia.map((d) => [formatarDia(d.dia), d.pedidos, formatarKz(d.vendas)]))) : '',
    r.por_hora.length ? sec('Por hora', tabela(['Hora', 'Pedidos', 'Vendas'], r.por_hora.map((h) => [`${h.hora}h`, h.pedidos, formatarKz(h.vendas)]))) : '',
    r.pratos.length ? sec('Pratos', tabela(['Prato', 'Qtd', 'Receita', '%'], r.pratos.map((p) => [p.nome, p.qtd, formatarKz(p.receita), pct(p.pct)]))) : '',
    r.opcoes_montados.length ? sec('Opções mais escolhidas (montados)', tabela(['Opção', 'Qtd'], r.opcoes_montados.map((o) => [o.nome, o.qtd]))) : '',
    r.pagamentos.length ? sec('Pagamentos', tabela(['Forma', 'Pedidos', 'Valor'], r.pagamentos.map((p) => [p.metodo, p.pedidos, formatarKz(p.valor)]))) : '',
    r.cancelamentos_motivos.length ? sec('Cancelamentos', tabela(['Motivo', 'N.º'], r.cancelamentos_motivos.map((c) => [c.motivo, c.n]))) : '',
    r.estafetas.length ? sec('Estafetas', tabela(['Estafeta', 'Entregas', 'A horas'], r.estafetas.map((e) => [e.nome, e.entregas, pct(e.a_horas_pct)]))) : '',
    r.zonas.length ? sec('Zonas', tabela(['Zona', 'Pedidos', 'Vendas'], r.zonas.map((z) => [z.zona, z.pedidos, formatarKz(z.vendas)]))) : '',
  ].join('');
  return `<html><head><meta charset="utf-8"><style>
    body{font-family:sans-serif;padding:20px;color:#1A1A1A} h1{color:#B5121B;margin:0} h2{font-size:15px;margin:18px 0 6px;color:#B5121B}
    table{border-collapse:collapse;width:100%} td,th{padding:4px 8px;border-bottom:1px solid #eee;font-size:12px;text-align:left}
    .suave{color:#5F6368;font-size:12px}
  </style></head><body>
    <h1>Manda Bué · Relatório da cozinha</h1>
    <p><b>${escaparHtml(r.cozinha)}</b> · ${escaparHtml(formatarDia(r.inicio))} a ${escaparHtml(formatarDia(r.fim))}</p>
    <p class="suave">Gerado por ${escaparHtml(geradoPor)} em ${escaparHtml(agora.toLocaleString('pt-PT'))}. Descontos de convite e saldo Convida pagos pela plataforma.</p>
    ${partes}
  </body></html>`;
}
