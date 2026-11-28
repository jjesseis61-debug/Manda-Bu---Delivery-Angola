// Junta Bué no trabalho (operador): equipas, refeições extra, contas do mês, acordo e benefício.
import { supabase } from './supabase';

export type QuemPaga = 'plataforma' | 'plataforma_cozinha' | 'cozinha';

export type EquipaResumo = {
  id: string;
  nome: string;
  responsavel: string;
  cozinha_id: string;
  cozinha: string;
  activa: boolean;
  origem: 'plataforma' | 'cozinha';
  limite_mensal: number;
  hora_entrega: string;
  membros: number;
  extras_pendentes: number;
  pagamentos_por_confirmar: number;
  em_atraso: number;
  acordo: { id: string; estado: 'proposto' | 'activo'; quem_paga: QuemPaga } | null;
};

export type ContaColega = {
  cliente_id: string;
  nome: string;
  mes: string;
  limite: number;
  total: number;
  pago: number;
  a_confirmar: number;
  em_falta: number;
  em_atraso: boolean;
};

export type Acordo = {
  id: string;
  estado: 'proposto' | 'activo';
  quem_paga: QuemPaga;
  parte_cozinha_pct: number;
  pct_1: number;
  pct_2: number;
  pct_3: number;
  limite_2: number;
  limite_3: number;
  conta_bebidas: boolean;
  tecto_refeicao: number;
};

export type EquipaDetalhe = {
  id: string;
  nome: string;
  origem: 'plataforma' | 'cozinha';
  limite_mensal: number;
  activa: boolean;
  responsavel: string;
  cozinha: string;
  mes: string;
  hora_entrega: string;
  prazo_minutos: number;
  dias: number[];
  grupo_hoje: { id: string; estado: string; prazo: string; pedidos: number } | null;
  extras: { id: string; cliente: string; quantidade: number; motivo: string; estado: 'pendente' | 'aprovado' | 'recusado'; aprovadas: number | null; dia: string }[];
  contas: ContaColega[];
  pagamentos_pendentes: { id: string; cliente: string; valor: number; metodo: string; referencia: string | null; mes: string; criado_em: string }[];
  acordo: Acordo | null;
  escalao: { media: number; pct: number; proximo_limite?: number | null; faltam?: number | null };
  beneficios: {
    pendente: number;
    desbloqueado: number;
    parte_cozinha_desbloqueada: number;
    pago: number;
    mes: number;
    parte_cozinha_mes: number;
  };
};

function ok<T>(r: { data: unknown; error: unknown }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

export const lerEquipas = async () => ok<EquipaResumo[]>(await supabase.rpc('equipas_operador'));
export const lerEquipa = async (id: string, mes: string | null = null) => ok<EquipaDetalhe>(await supabase.rpc('equipa_operador', { p_equipa: id, p_mes: mes }));
export const decidirExtra = async (id: string, aprovadas: number) => ok<void>(await supabase.rpc('decidir_extra', { p_extra: id, p_aprovadas: aprovadas }));
export const registarDinheiro = async (equipa: string, cliente: string, mes: string, valor: number) =>
  ok<string>(await supabase.rpc('registar_dinheiro_conta_mes', { p_equipa: equipa, p_cliente: cliente, p_mes: mes, p_valor: valor, p_pago_por: null }));
export const decidirPagamento = async (id: string, confirmar: boolean, motivo: string | null = null) =>
  ok<void>(await supabase.rpc('decidir_pagamento_conta_mes', { p_id: id, p_confirmar: confirmar, p_motivo: motivo }));
export const definirEquipa = async (id: string, limite: number, origem: 'plataforma' | 'cozinha', activa: boolean) =>
  ok<void>(await supabase.rpc('definir_equipa', { p_equipa: id, p_limite: limite, p_origem: origem, p_activa: activa }));
export const proporAcordo = async (equipa: string, a: Omit<Acordo, 'id' | 'estado'>) =>
  ok<string>(
    await supabase.rpc('propor_acordo_equipa', {
      p_equipa: equipa,
      p_quem_paga: a.quem_paga,
      p_parte_cozinha_pct: a.parte_cozinha_pct,
      p_pct_1: a.pct_1,
      p_pct_2: a.pct_2,
      p_pct_3: a.pct_3,
      p_limite_2: a.limite_2,
      p_limite_3: a.limite_3,
      p_conta_bebidas: a.conta_bebidas,
      p_tecto: a.tecto_refeicao,
    }),
  );
export const aceitarAcordo = async (id: string) => ok<void>(await supabase.rpc('aceitar_acordo_equipa', { p_acordo: id }));
export const terminarAcordo = async (id: string) => ok<void>(await supabase.rpc('terminar_acordo_equipa', { p_acordo: id }));
export const pagarBeneficio = async (equipa: string, metodo: string) => ok<number>(await supabase.rpc('pagar_beneficio_equipa', { p_equipa: equipa, p_metodo: metodo }));

export const nomeQuemPaga: Record<QuemPaga, string> = {
  plataforma: 'Plataforma (sai da comissão)',
  plataforma_cozinha: 'Plataforma e cozinha',
  cozinha: 'Só a cozinha (comissão 0, entrega 0, dinheiro)',
};

/** Escalões do acordo em linguagem simples */
export function textoEscaloes(a: Pick<Acordo, 'pct_1' | 'pct_2' | 'pct_3' | 'limite_2' | 'limite_3'>): string {
  const p = (n: number) => `${String(n).replace('.', ',')}%`;
  return `${p(a.pct_1)} até ${a.limite_2 - 1} almoços por dia · ${p(a.pct_2)} de ${a.limite_2} a ${a.limite_3 - 1} · ${p(a.pct_3)} a partir de ${a.limite_3}`;
}

/** Custo para a cozinha de um benefício: tudo («só a cozinha»), a parte combinada, ou nada */
export function parteDaCozinha(valor: number, a: Pick<Acordo, 'quem_paga' | 'parte_cozinha_pct'>): number {
  if (a.quem_paga === 'cozinha') return valor;
  if (a.quem_paga === 'plataforma_cozinha') return Math.round((valor * a.parte_cozinha_pct) / 100);
  return 0;
}
