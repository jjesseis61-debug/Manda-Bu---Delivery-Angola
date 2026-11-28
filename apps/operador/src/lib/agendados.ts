// Pedidos agendados (ecrã próprio): períodos, agrupamento por dia/hora, lista de produção e
// estado do alerta. Tudo puro (sem rede), para se testar sem o servidor.
import { detalharItem } from './talao';
import type { AgendadoOperador, PedidoOperador } from './tipos';

/** Luanda está sempre em UTC+1 (sem horário de verão) */
const LUANDA_MS = 60 * 60 * 1000;

/** "2026-11-12" (dia de Luanda) de uma data ISO */
export function diaLuanda(iso: string | Date): string {
  return new Date(new Date(iso).getTime() + LUANDA_MS).toISOString().slice(0, 10);
}

/** Hora de Luanda (0–23) de uma data ISO */
export function horaLuanda(iso: string): number {
  return new Date(new Date(iso).getTime() + LUANDA_MS).getUTCHours();
}

/** "12:30" (hora de Luanda) de uma data ISO */
export function horaMinLuanda(iso: string): string {
  return new Date(new Date(iso).getTime() + LUANDA_MS).toISOString().slice(11, 16);
}

function somarDias(dia: string, n: number): string {
  const d = new Date(`${dia}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export type Periodo = 'hoje' | 'amanha' | 'semana' | 'datas';

/** Datas (de/até, dias de Luanda) de cada atalho. "datas" usa as escolhidas (aaaa-mm-dd). */
export function intervaloDo(periodo: Periodo, agora: Date, de?: string, ate?: string): { inicio: string; fim: string } | null {
  const hoje = diaLuanda(agora);
  if (periodo === 'hoje') return { inicio: hoje, fim: hoje };
  if (periodo === 'amanha') return { inicio: somarDias(hoje, 1), fim: somarDias(hoje, 1) };
  if (periodo === 'semana') return { inicio: hoje, fim: somarDias(hoje, 6) };
  const ok = (s?: string) => !!s && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));
  if (!ok(de)) return null;
  const fim = ok(ate) ? (ate as string) : (de as string);
  return fim < (de as string) ? null : { inicio: de as string, fim };
}

/** Nome do dia para o cabeçalho: "Hoje", "Amanhã" ou "sex 14/11" */
export function nomeDia(dia: string, agora: Date): string {
  const hoje = diaLuanda(agora);
  if (dia === hoje) return 'Hoje';
  if (dia === somarDias(hoje, 1)) return 'Amanhã';
  const semana = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'][new Date(`${dia}T00:00:00Z`).getUTCDay()];
  return `${semana} ${dia.slice(8, 10)}/${dia.slice(5, 7)}`;
}

export type GrupoHora = { hora: number; pedidos: AgendadoOperador[]; total: number };
export type GrupoDia = { dia: string; horas: GrupoHora[]; pedidos: number; total: number };

/** Agrupa por dia e, dentro do dia, por hora (11:00–12:00), com nº de pedidos e valor a receber */
export function agrupar(lista: AgendadoOperador[]): GrupoDia[] {
  const dias = new Map<string, Map<number, AgendadoOperador[]>>();
  const ordenada = [...lista].sort((a, b) => a.agendado_para.localeCompare(b.agendado_para));
  for (const a of ordenada) {
    const d = diaLuanda(a.agendado_para);
    const h = horaLuanda(a.agendado_para);
    if (!dias.has(d)) dias.set(d, new Map());
    const horas = dias.get(d) as Map<number, AgendadoOperador[]>;
    horas.set(h, [...(horas.get(h) ?? []), a]);
  }
  return [...dias.entries()].map(([dia, horas]) => {
    const hs = [...horas.entries()].map(([hora, pedidos]) => ({
      hora,
      pedidos,
      total: pedidos.reduce((s, p) => s + p.a_pagar, 0),
    }));
    return { dia, horas: hs, pedidos: hs.reduce((s, h) => s + h.pedidos.length, 0), total: hs.reduce((s, h) => s + h.total, 0) };
  });
}

export type LinhaProducao = { prato: string; qtd: number; opcoes: { nome: string; qtd: number }[]; sem: { nome: string; qtd: number }[] };

/** O que preparar: total por prato e, dentro do prato, por opção e por ingrediente a tirar */
export function listaProducao(lista: AgendadoOperador[]): LinhaProducao[] {
  const pratos = new Map<string, { qtd: number; opcoes: Map<string, number>; sem: Map<string, number> }>();
  for (const p of lista) {
    for (const i of p.itens) {
      const d = detalharItem(i);
      const qtd = Number(i.qtd) || 0;
      const linha = pratos.get(d.nome) ?? { qtd: 0, opcoes: new Map(), sem: new Map() };
      linha.qtd += qtd;
      for (const o of d.opcoes) linha.opcoes.set(o, (linha.opcoes.get(o) ?? 0) + qtd);
      for (const s of d.sem) linha.sem.set(s, (linha.sem.get(s) ?? 0) + qtd);
      pratos.set(d.nome, linha);
    }
  }
  const ordenar = (m: Map<string, number>) =>
    [...m.entries()].map(([nome, qtd]) => ({ nome, qtd })).sort((a, b) => b.qtd - a.qtd || a.nome.localeCompare(b.nome));
  return [...pratos.entries()]
    .map(([prato, l]) => ({ prato, qtd: l.qtd, opcoes: ordenar(l.opcoes), sem: ordenar(l.sem) }))
    .sort((a, b) => b.qtd - a.qtd || a.prato.localeCompare(b.prato));
}

/**
 * Alerta do agendado (a hora do alerta vem do servidor, com a regra do turno):
 * - urgente: já entrou na fila (90 min antes) e continua pendente;
 * - por_confirmar: passou a hora do alerta e continua pendente.
 */
export function estadoAlerta(a: AgendadoOperador, agora: Date): 'urgente' | 'por_confirmar' | null {
  if (a.estado !== 'pendente') return null;
  if (a.na_fila) return 'urgente';
  if (a.alerta_em && new Date(a.alerta_em).getTime() <= agora.getTime()) return 'por_confirmar';
  return null;
}

/** "faltam 3 h 20 min" / "faltam 45 min" / "já passou" */
export function faltam(iso: string, agora: Date): string {
  const min = Math.round((new Date(iso).getTime() - agora.getTime()) / 60000);
  if (min <= 0) return 'já passou a hora';
  if (min < 60) return `faltam ${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  if (h >= 48) return `faltam ${Math.floor(h / 24)} dias`;
  return m ? `faltam ${h} h ${m} min` : `faltam ${h} h`;
}

/** Telefone angolano em formato internacional (sem +): 923000111 -> 244923000111 */
export function telefoneInternacional(tel: string | null | undefined): string | null {
  const d = (tel ?? '').replace(/\D/g, '');
  if (!d) return null;
  return d.startsWith('244') ? d : `244${d}`;
}

export function linkWhatsapp(tel: string | null | undefined, texto: string): string | null {
  const t = telefoneInternacional(tel);
  return t ? `https://wa.me/${t}?text=${encodeURIComponent(texto)}` : null;
}

export function linkMapa(lat: number | null, lng: number | null): string | null {
  return lat != null && lng != null ? `https://www.google.com/maps/search/?api=1&query=${lat},${lng}` : null;
}

/** Lembrete para o cliente (WhatsApp) */
export function textoLembrete(a: AgendadoOperador): string {
  const primeiro = a.cliente_nome.trim().split(/\s+/)[0] || 'Olá';
  const hora = horaMinLuanda(a.agendado_para);
  const dia = diaLuanda(a.agendado_para);
  return `Olá ${primeiro}! Aqui é a Manda Bué. Confirmamos o teu pedido agendado para ${dia.slice(8, 10)}/${dia.slice(5, 7)} às ${hora}. Está tudo certo?`;
}

/** O agendado no formato do pedido, para reaproveitar os talões (cozinha e entrega) */
export function comoPedido(a: AgendadoOperador): PedidoOperador {
  return {
    pedido_id: a.pedido_id,
    criado_em: a.criado_em,
    estado: a.estado,
    cozinha_id: a.cozinha_id,
    cliente_nome: a.cliente_nome,
    cliente_telefone: a.cliente_telefone,
    itens: a.itens,
    subtotal: a.subtotal,
    taxa_entrega: a.taxa_entrega,
    desconto_indicacao: a.desconto_indicacao,
    credito_indicacao_usado: a.credito_indicacao_usado,
    a_pagar: a.a_pagar,
    observacoes: a.observacoes,
    hora_prometida: a.agendado_para,
    pagador_distinto: null,
    ponto_entrega_id: null,
    ponto_tipo: a.ponto_tipo,
    ponto_lat: a.ponto_lat,
    ponto_lng: a.ponto_lng,
    ponto_referencia: a.ponto_referencia,
    zona_nome: a.zona_nome,
    atribuido_a: null,
    atribuido_a_nome: a.atribuido_a_nome,
    atribuido_a_mim: false,
    minha: false,
  };
}

/** Dia (aaaa-mm-dd) + hora (HH:MM) de Luanda → instante ISO (Luanda é UTC+1, sem hora de verão); null se inválido */
export function instanteLuanda(dia: string, hora: string): string | null {
  const d = dia.trim();
  const h = hora.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(h)) return null;
  const t = new Date(`${d}T${h}:00+01:00`);
  return Number.isNaN(t.getTime()) ? null : t.toISOString();
}

/** Nome do alerta de um agendado */
export const NOME_ALERTA: Record<string, string> = {
  fora_de_horario: 'Fora do horário do prato',
  doses: 'Doses insuficientes',
  hora_cheia: 'Hora cheia',
};

/** Linhas do CSV (Excel) dos agendados do período */
export function linhasCsvAgendados(lista: AgendadoOperador[]): (string | number | null)[][] {
  return [
    ['Dia', 'Hora', 'Pedido', 'Estado', 'Cozinha', 'Cliente', 'Telefone', 'Pratos', 'Observações', 'Morada', 'Zona', 'A receber (Kz)'],
    ...lista.map((a) => [
      diaLuanda(a.agendado_para),
      horaMinLuanda(a.agendado_para),
      a.pedido_id.slice(0, 6).toUpperCase(),
      a.estado,
      a.cozinha_nome,
      a.cliente_nome,
      a.cliente_telefone,
      a.itens.map((i) => `${i.qtd}x ${i.nome}`).join('; '),
      a.observacoes,
      a.ponto_referencia,
      a.zona_nome,
      a.a_pagar,
    ]),
  ];
}

/** Um ponto no mapa do dia: pedido agendado com coordenadas */
export type ParagemMapa = { id: string; lat: number; lng: number; hora: string; rotulo: string; zona: string | null; alerta: boolean };

/** Pedidos com coordenadas, por hora de entrega (os sem coordenadas ficam de fora do mapa) */
export function paragensDoMapa(lista: AgendadoOperador[], comAlerta: Set<string> = new Set()): ParagemMapa[] {
  return lista
    .filter((a) => a.ponto_lat != null && a.ponto_lng != null && a.estado !== 'cancelado')
    .sort((x, y) => x.agendado_para.localeCompare(y.agendado_para))
    .map((a) => ({
      id: a.pedido_id,
      lat: a.ponto_lat as number,
      lng: a.ponto_lng as number,
      hora: horaMinLuanda(a.agendado_para),
      rotulo: `${horaMinLuanda(a.agendado_para)} · ${a.cliente_nome.split(' ')[0]}`,
      zona: a.zona_nome,
      alerta: comAlerta.has(a.pedido_id),
    }));
}

/** Resumo por zona (para agrupar entregas): nº de pedidos e a 1.ª e a última hora */
export function resumoPorZona(lista: AgendadoOperador[]): { zona: string; pedidos: number; de: string; ate: string }[] {
  const m = new Map<string, AgendadoOperador[]>();
  for (const a of lista) {
    if (a.estado === 'cancelado') continue;
    const z = a.zona_nome ?? 'Sem zona';
    m.set(z, [...(m.get(z) ?? []), a]);
  }
  return [...m.entries()]
    .map(([zona, ps]) => {
      const horas = ps.map((p) => horaMinLuanda(p.agendado_para)).sort();
      return { zona, pedidos: ps.length, de: horas[0], ate: horas[horas.length - 1] };
    })
    .sort((a, b) => b.pedidos - a.pedidos || a.zona.localeCompare(b.zona));
}

/**
 * Rota no Google Maps pelas paragens, por ordem de hora (a partir da posição actual de quem abre).
 * O Google aceita até 9 paragens intermédias; com mais, a rota leva as 10 primeiras.
 */
export function linkRota(paragens: ParagemMapa[]): string | null {
  const ps = paragens.slice(0, 10);
  if (ps.length === 0) return null;
  const c = (p: ParagemMapa) => `${p.lat},${p.lng}`;
  const destino = ps[ps.length - 1];
  const meio = ps.slice(0, -1).map(c).join('|');
  return `https://www.google.com/maps/dir/?api=1&travelmode=driving&destination=${encodeURIComponent(c(destino))}${
    meio ? `&waypoints=${encodeURIComponent(meio)}` : ''
  }`;
}
