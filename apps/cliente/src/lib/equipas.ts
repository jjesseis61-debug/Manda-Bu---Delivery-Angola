// Junta Bué no trabalho: equipa fixa de colegas com uma responsável, grupo do dia, conta do mês e benefício.
import type { ItemCarrinho } from './api';
import { supabase } from './supabase';

export type Escalao = { media: number; pct: number; proximo_limite?: number | null; proximo_pct?: number | null; faltam?: number | null };

export type ColegaEquipa = {
  cliente_id: string;
  nome: string;
  estado: 'convidado' | 'activo';
  /** Só a responsável vê estes campos */
  pode_pedir: boolean | null;
  pode_ver_conta: boolean | null;
  em_atraso: boolean | null;
  pediu_hoje: boolean | null;
};

export type MinhaEquipa = {
  id: string;
  nome: string;
  sou_responsavel: boolean;
  estado: 'convidado' | 'activo';
  cozinha_id: string;
  responsavel: string;
  cozinha: string | null;
  local: string | null;
  hora_entrega: string;
  prazo_minutos: number;
  dias: number[];
  limite_mensal: number;
  activa: boolean;
  pode_pedir: boolean;
  pode_ver_conta: boolean;
  em_atraso: boolean;
  hoje: {
    grupo_id: string;
    codigo: string;
    estado: string;
    prazo: string;
    hora: string;
    meu_pedido: { id: string; estado: string; pedido_por: string | null; itens: string } | null;
    pedidos: number;
  } | null;
  extras_hoje: { id: string; quantidade: number; aprovadas: number | null; estado: 'pendente' | 'aprovado' | 'recusado'; motivo: string }[];
  acordo: { quem_paga: 'plataforma' | 'plataforma_cozinha' | 'cozinha' } | null;
  colegas: ColegaEquipa[];
  beneficio: { escalao: Escalao; mes_pendente: number; desbloqueado: number; pago: number; colegas_por_pagar: number } | null;
};

export type ContaMes = {
  equipa_id: string;
  cliente_id: string;
  nome: string;
  mes: string;
  limite: number;
  total: number;
  pago: number;
  a_confirmar: number;
  em_falta: number;
  em_atraso: boolean;
  linhas: { pedido_id: string; dia: string; valor: number; entregue: boolean; pedido_por: string | null; itens: string }[];
  pagamentos: { id: string; valor: number; metodo: string; estado: 'pendente' | 'confirmado' | 'rejeitado'; criado_em: string; motivo: string | null; pago_por: string | null }[];
};

function ok<T>(r: { data: unknown; error: unknown }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

export const minhasEquipas = async () => ok<MinhaEquipa[]>(await supabase.rpc('minhas_equipas'));

export const criarEquipa = async (d: { nome: string; ponto: string; cozinha: string; hora: string; prazoMinutos: number; dias: number[] }) =>
  ok<string>(
    await supabase.rpc('criar_equipa', {
      p_nome: d.nome,
      p_ponto: d.ponto,
      p_cozinha: d.cozinha,
      p_hora: d.hora,
      p_prazo_minutos: d.prazoMinutos,
      p_dias: d.dias,
    }),
  );

export const convidarColega = async (equipa: string, codigo: string) =>
  ok<string>(await supabase.rpc('equipa_convidar', { p_equipa: equipa, p_codigo: codigo }));

export const responderConvite = async (equipa: string, aceitar: boolean, podePedir: boolean, podeVerConta: boolean) =>
  ok<void>(await supabase.rpc('equipa_responder', { p_equipa: equipa, p_aceitar: aceitar, p_pode_pedir: podePedir, p_pode_ver_conta: podeVerConta }));

export const mudarAutorizacoes = async (equipa: string, podePedir: boolean, podeVerConta: boolean) =>
  ok<void>(await supabase.rpc('equipa_autorizacoes', { p_equipa: equipa, p_pode_pedir: podePedir, p_pode_ver_conta: podeVerConta }));

export const sairDaEquipa = async (equipa: string, cliente: string | null = null) =>
  ok<void>(await supabase.rpc('equipa_sair', { p_equipa: equipa, p_cliente: cliente }));

export const pedirPorColega = async (equipa: string, cliente: string, itens: ItemCarrinho[]) =>
  ok<string>(await supabase.rpc('pedir_por_colega', { p_equipa: equipa, p_cliente: cliente, p_itens: itens }));

export const pratoHabitualColega = async (equipa: string, cliente: string) =>
  ok<{ itens: ItemCarrinho[]; texto: string } | null>(await supabase.rpc('prato_habitual_colega', { p_equipa: equipa, p_cliente: cliente }));

export const recusarPedidoColega = async (pedido: string) => ok<void>(await supabase.rpc('recusar_pedido_colega', { p_pedido: pedido }));

export const pedirRefeicoesExtra = async (equipa: string, quantidade: number, motivo: string) =>
  ok<string>(await supabase.rpc('pedir_refeicoes_extra', { p_equipa: equipa, p_quantidade: quantidade, p_motivo: motivo }));

export const lerContaMes = async (equipa: string, cliente: string | null = null) =>
  ok<ContaMes>(await supabase.rpc('conta_mes', { p_equipa: equipa, p_cliente: cliente }));

export const pagarContaMes = async (d: { equipa: string; cliente: string; mes: string; metodo: 'multicaixa_express' | 'unitel_money'; referencia: string; valor: number }) =>
  ok<string>(
    await supabase.rpc('pagar_conta_mes', {
      p_equipa: d.equipa,
      p_cliente: d.cliente,
      p_mes: d.mes,
      p_metodo: d.metodo,
      p_referencia: d.referencia,
      p_valor: d.valor,
    }),
  );

const DIAS = ['', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/** «de segunda a sexta», ou a lista curta («seg, qua, sex») */
export function textoDias(dias: number[]): string {
  const d = [...dias].sort((a, b) => a - b);
  if (d.join() === '1,2,3,4,5') return 'de segunda a sexta';
  if (d.join() === '1,2,3,4,5,6') return 'de segunda a sábado';
  if (d.length === 7) return 'todos os dias';
  return d.map((x) => DIAS[x]).join(', ');
}

/**
 * Meta próxima da responsável (Bandura): «Faltam 3 almoços por dia para chegares aos 5%».
 * Comparada só consigo própria (a média do mês anterior), nunca com outras equipas.
 */
export function textoEscalao(e: Escalao): string {
  const pct = `${String(e.pct).replace('.', ',')}%`;
  if (e.proximo_limite == null || e.proximo_pct == null) return `Estás no escalão mais alto: ${pct} de cada almoço.`;
  const faltam = Math.max(1, Math.ceil(Number(e.faltam ?? 0)));
  return `Este mês ganhas ${pct} de cada almoço. Com mais ${faltam} almoço${faltam === 1 ? '' : 's'} por dia (média de ${e.proximo_limite}), passas a ${String(e.proximo_pct).replace('.', ',')}% no mês seguinte.`;
}

/** O que falta à responsável para receber tudo: «Faltam 2 colegas pagarem a conta» */
export function textoColegasPorPagar(n: number): string | null {
  if (n <= 0) return null;
  return n === 1 ? 'Falta 1 colega pagar a conta do mês para desbloqueares o resto.' : `Faltam ${n} colegas pagarem a conta do mês para desbloqueares o resto.`;
}

/** Hora «HH:MM» válida */
export function horaValida(t: string): boolean {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(t.trim());
}

/** Primeiro dia do mês (AAAA-MM-01) de uma data ISO */
export const inicioDoMes = (iso: string) => `${iso.slice(0, 7)}-01`;
