import { supabase } from './supabase';

/** Pedidos agendados de um grupo do teste do compromisso (A = pergunta «Vais estar…?», B = controlo) */
export type GrupoCompromisso = { agendados: number; confirmados: number; com_ausencia: number; entregues: number; cancelados: number };
export type ResultadoCompromisso = Partial<Record<'A' | 'B', GrupoCompromisso>>;

const VAZIO: GrupoCompromisso = { agendados: 0, confirmados: 0, com_ausencia: 0, entregues: 0, cancelados: 0 };

export async function resultadoCompromisso(de: string, ate: string): Promise<{ A: GrupoCompromisso; B: GrupoCompromisso }> {
  const { data, error } = await supabase.rpc('resultado_compromisso', { p_de: de, p_ate: ate });
  if (error) throw error;
  const r = (data ?? {}) as ResultadoCompromisso;
  return { A: { ...VAZIO, ...r.A }, B: { ...VAZIO, ...r.B } };
}

/** Agendados por grupo antes de tirar conclusões */
export const MINIMO_AGENDADOS = 40;

/** % de agendados com o cliente ausente (null sem agendados) */
export const taxaAusencia = (g: GrupoCompromisso) => (g.agendados > 0 ? Math.round((g.com_ausencia / g.agendados) * 1000) / 10 : null);

/**
 * Leitura em linguagem simples (Skinner: decidir pelos números, só com dados suficientes).
 * Vence o grupo com menos ausências; abaixo de 2 pontos de diferença não há vencedor claro.
 */
export function veredictoCompromisso(a: GrupoCompromisso, b: GrupoCompromisso): { claro: boolean; vencedor: 'A' | 'B' | null; texto: string } {
  if (a.agendados < MINIMO_AGENDADOS || b.agendados < MINIMO_AGENDADOS) {
    return {
      claro: false,
      vencedor: null,
      texto: `Ainda poucos agendados (A: ${a.agendados}, B: ${b.agendados}). Espera até cada grupo ter pelo menos ${MINIMO_AGENDADOS}.`,
    };
  }
  const ta = taxaAusencia(a) ?? 0;
  const tb = taxaAusencia(b) ?? 0;
  const dif = Math.round((tb - ta) * 10) / 10;
  const n = (x: number) => x.toLocaleString('pt-PT');
  if (Math.abs(dif) < 2) return { claro: false, vencedor: null, texto: `Sem diferença clara nas ausências (${n(ta)}% com a pergunta, ${n(tb)}% sem).` };
  return dif > 0
    ? { claro: true, vencedor: 'A', texto: `A pergunta reduz as ausências: ${n(ta)}% contra ${n(tb)}% (−${n(dif)} pontos).` }
    : { claro: true, vencedor: 'B', texto: `A pergunta não ajuda: ${n(ta)}% de ausências com ela contra ${n(tb)}% sem.` };
}
