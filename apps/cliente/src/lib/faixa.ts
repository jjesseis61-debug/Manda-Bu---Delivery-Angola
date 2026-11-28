// Faixa de confiança (decisão do dono com os especialistas, 17/11/2026).
// Só promete o que se cumpre: a 3.ª frase vem de factos medidos no servidor.
//  * B (base): "Problema? Resolvemos";
//  * A: "Na tua porta em ~N min" quando >= 90% das entregas dos últimos 30 dias chegaram a tempo (>= 30);
//  * pedido agendado: "Na hora que escolheres" (o tempo não se aplica);
//  * C: "X pedidos hoje no teu bairro" alterna com A/B quando o contador da zona tem número.
import { supabase } from './supabase';

export type Pontualidade = { entregas: number; a_tempo_pct: number | null; tempo_min: number | null; cumpre: boolean };

export type FraseFaixa = { icone: string; texto: string; ajuda?: boolean };

export async function lerPontualidade(): Promise<Pontualidade | null> {
  // Sem rede ou sem a função no servidor: fica a frase base (B), nunca um erro no ecrã
  try {
    const r = await supabase.rpc('pontualidade_entregas');
    if (r.error) return null;
    return (r.data as Pontualidade) ?? null;
  } catch {
    return null;
  }
}

/** A 3.ª frase (sem a prova social): o tempo, se cumprimos; senão "Problema? Resolvemos" */
export function terceiraFrase(p: Pontualidade | null, agendado = false): FraseFaixa {
  if (agendado) return { icone: '🗓️', texto: 'Na hora que escolheres' };
  if (p?.cumpre && p.tempo_min && p.tempo_min > 0) return { icone: '⏱️', texto: `Na tua porta em ~${p.tempo_min} min` };
  return { icone: '🤝', texto: 'Problema? Resolvemos', ajuda: true };
}

/** Prova social do bairro (só quando o servidor dá número: já vem acima do mínimo) */
export function fraseBairro(contador: number | null | undefined, bairro?: string | null): FraseFaixa | null {
  if (!contador || contador <= 0) return null;
  const onde = bairro ? `no ${bairro}` : 'no teu bairro';
  return { icone: '🔥', texto: `${contador} ${contador === 1 ? 'pedido' : 'pedidos'} hoje ${onde}` };
}

/** As três frases a mostrar; com prova social, a 3.ª alterna (vez par/ímpar) */
export function frasesFaixa(p: Pontualidade | null, bairro: FraseFaixa | null, vez = 0, agendado = false): FraseFaixa[] {
  const base: FraseFaixa[] = [
    { icone: '💵', texto: 'Pagas na entrega' },
    { icone: '🍲', texto: 'Comida de casa' },
  ];
  const terceira = bairro && vez % 2 === 1 ? bairro : terceiraFrase(p, agendado);
  return [...base, terceira];
}
