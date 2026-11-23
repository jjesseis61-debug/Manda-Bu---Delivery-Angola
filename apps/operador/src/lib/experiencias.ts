import { supabase } from './supabase';

/** Números de um grupo de um teste com grupo de controlo (A = como era, B = o desenho novo) */
export type GrupoExperiencia = {
  clientes: number;
  dias_visita: number;
  visitas: number;
  dias_com_pedido: number;
  conversao_pct: number | null;
  pedidos: number;
  valor_medio: number | null;
  mediana_segundos: number | null;
};
export type ResultadoExperiencia = {
  experiencia: string;
  de: string;
  ate: string;
  activo: boolean;
  grupos: { A: GrupoExperiencia; B: GrupoExperiencia };
};

export type Experiencia = 'fotos_inicio' | 'balcao_panelas';

/** Textos de cada teste: o que A e B mostram e o que fica quando não há diferença clara */
export type TextosExperiencia = {
  /** Nome curto de cada grupo, ex.: «A fotografia grande» */
  a: string;
  b: string;
  /** Quem fica sem diferença clara e porquê */
  semDiferenca: { vencedor: 'A' | 'B'; texto: string };
};

export const TEXTOS: Record<Experiencia, TextosExperiencia> = {
  fotos_inicio: {
    a: 'A fotografia grande',
    b: 'A fotografia média',
    semDiferenca: { vencedor: 'B', texto: 'Fica a fotografia média: gasta menos dados e mostra mais pratos.' },
  },
  balcao_panelas: {
    a: 'A lista',
    b: 'O balcão de panelas',
    semDiferenca: { vencedor: 'A', texto: 'Fica a lista: é a que os clientes já conhecem (Rogers) e é mais leve.' },
  },
};

export async function resultadoExperiencia(experiencia: Experiencia, de: string, ate: string): Promise<ResultadoExperiencia> {
  const { data, error } = await supabase.rpc('resultado_experiencia', { p_experiencia: experiencia, p_de: de, p_ate: ate });
  if (error) throw error;
  return data as ResultadoExperiencia;
}

/** Dias de visita por grupo antes de tirar conclusões (abaixo disto a diferença pode ser acaso) */
export const MINIMO_DIAS_VISITA = 100;
/** Diferença de conversão (pontos percentuais) abaixo da qual não se considera haver vencedor */
export const DIFERENCA_MINIMA_PP = 2;

/**
 * Leitura do resultado em linguagem simples (Skinner: decidir pelos números, mas só com dados
 * suficientes). Sem diferença clara fica o B, que gasta menos dados e mostra mais pratos.
 */
export function veredictoExperiencia(
  a: GrupoExperiencia,
  b: GrupoExperiencia,
  textos: TextosExperiencia = TEXTOS.fotos_inicio,
): { vencedor: 'A' | 'B' | null; claro: boolean; texto: string } {
  if (a.dias_visita < MINIMO_DIAS_VISITA || b.dias_visita < MINIMO_DIAS_VISITA) {
    return {
      vencedor: null,
      claro: false,
      texto: `Ainda poucos dados (A: ${a.dias_visita}, B: ${b.dias_visita} visitas). Espera até cada grupo ter pelo menos ${MINIMO_DIAS_VISITA}.`,
    };
  }
  const ca = a.conversao_pct ?? 0;
  const cb = b.conversao_pct ?? 0;
  const dif = Math.round((cb - ca) * 10) / 10;
  if (Math.abs(dif) < DIFERENCA_MINIMA_PP) {
    return {
      vencedor: textos.semDiferenca.vencedor,
      claro: false,
      texto: `Sem diferença clara (${Math.abs(dif).toLocaleString('pt-PT')} ${Math.abs(dif) === 1 ? 'ponto' : 'pontos'}). ${textos.semDiferenca.texto}`,
    };
  }
  return dif > 0
    ? { vencedor: 'B', claro: true, texto: `${textos.b} converte mais: +${dif.toLocaleString('pt-PT')} pontos (${cb.toLocaleString('pt-PT')}% contra ${ca.toLocaleString('pt-PT')}%).` }
    : { vencedor: 'A', claro: true, texto: `${textos.a} converte mais: +${(-dif).toLocaleString('pt-PT')} pontos (${ca.toLocaleString('pt-PT')}% contra ${cb.toLocaleString('pt-PT')}%).` };
}
