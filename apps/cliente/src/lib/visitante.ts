// Visitante: quem abre o link de um prato sem conta. Vê o prato e o cardápio daquela cozinha,
// monta o carrinho (guardado 24 h) e só entra/cria conta ao carregar em «Pedir».
// As leituras são do servidor (visitante_prato / visitante_cardapio): só o que a app já mostra.
import AsyncStorage from '@react-native-async-storage/async-storage';

import { supabase } from './supabase';
import type { RegrasConvida } from './formatar';
import type { ComponentePrato, GrupoOpcoes, ItemCardapio } from './tipos';

export type PratoVisitante = {
  prato: ItemCardapio;
  cozinha: { id: string; nome: string };
  esgotado: boolean;
  grupos: GrupoOpcoes[];
  componentes: ComponentePrato[];
  /** Código de convite válido: desconto do 1.º pedido e subtotal mínimo */
  convite: { desconto: number; minimo: number } | null;
};

export type PratoCardapioVisitante = ItemCardapio & { esgotado: boolean; montar: boolean };

export type CardapioVisitante = { cozinha: { id: string; nome: string }; pratos: PratoCardapioVisitante[] };

/** O prato partilhado; null = já não está disponível (ou a cozinha não aceita pedidos agora) */
export async function lerPratoVisitante(id: string, codigo?: string | null): Promise<PratoVisitante | null> {
  const r = await supabase.rpc('visitante_prato', { p_id: id, p_codigo: codigo ?? null });
  if (r.error) throw r.error;
  return (r.data as PratoVisitante | null) ?? null;
}

export async function lerCardapioVisitante(cozinhaId: string): Promise<CardapioVisitante | null> {
  const r = await supabase.rpc('visitante_cardapio', { p_cozinha: cozinhaId });
  if (r.error) throw r.error;
  return (r.data as CardapioVisitante | null) ?? null;
}

// ------------------------------------------------------------ porta da frente (sem link)
/** Bairro com a taxa de entrega e o limiar da entrega grátis (null = sem entrega grátis) */
export type ZonaVisitante = { id: string; nome: string; taxa: number; entrega_gratis_acima: number | null };
export type CozinhaVisitante = { id: string; nome: string; pratos: number; distancia_km: number | null; foto_url: string | null };

/** Bairros (zonas de entrega) para o visitante escolher */
export async function lerZonasVisitante(): Promise<ZonaVisitante[]> {
  const r = await supabase.rpc('visitante_zonas');
  if (r.error) throw r.error;
  return (r.data as ZonaVisitante[] | null) ?? [];
}

/** Cozinhas que servem o visitante, da mais perto do bairro para a mais longe; sem bairro, todas */
export async function lerCozinhasVisitante(zonaId: string | null): Promise<CozinhaVisitante[]> {
  const r = await supabase.rpc('visitante_cozinhas', { p_zona: zonaId });
  if (r.error) throw r.error;
  return (r.data as CozinhaVisitante[] | null) ?? [];
}

// O bairro escolhido fica guardado 24 h (o cardápio e o carrinho do visitante mostram a entrega)
const CHAVE_ZONA = 'manda-bue:zona-visitante';

export async function guardarZonaVisitante(z: ZonaVisitante | null): Promise<void> {
  await (z ? AsyncStorage.setItem(CHAVE_ZONA, JSON.stringify({ zona: z, em: Date.now() })) : AsyncStorage.removeItem(CHAVE_ZONA)).catch(
    () => undefined,
  );
}

export async function lerZonaVisitante(agora = Date.now()): Promise<ZonaVisitante | null> {
  try {
    const bruto = await AsyncStorage.getItem(CHAVE_ZONA);
    if (!bruto) return null;
    const { zona, em } = JSON.parse(bruto) as { zona: ZonaVisitante; em: number };
    if (typeof em !== 'number' || agora - em > VALIDADE_MS || !zona || typeof zona.taxa !== 'number') return null;
    return zona;
  } catch {
    return null;
  }
}

/** Quantas cozinhas se mostram antes de «Ver mais» (escolha curta para quem está a experimentar) */
export const COZINHAS_A_MOSTRAR = 3;

/**
 * Ordem para o visitante: mantém a do servidor (mais perto primeiro), mas as cozinhas com um só
 * prato vão para o fim (a quem chega pela primeira vez parecem vazias).
 */
export function ordenarCozinhasVisitante(lista: CozinhaVisitante[]): CozinhaVisitante[] {
  return [...lista.filter((c) => c.pratos > 1), ...lista.filter((c) => c.pratos <= 1)];
}

/** O que mostrar no botão do bairro */
export function rotuloZona(z: ZonaVisitante, formatar: (v: number) => string): string {
  return `${z.nome} · ${z.taxa > 0 ? `entrega ${formatar(z.taxa)}` : 'entrega grátis'}`;
}

/**
 * Entrega estimada no carrinho do visitante: a taxa do bairro, grátis a partir do limiar.
 * Estimativa: o servidor confirma no carrinho (com a morada e os descontos).
 */
export function entregaVisitante(z: ZonaVisitante, pratos: number): { taxa: number; total: number; falta: number | null } {
  const gratis = z.entrega_gratis_acima !== null && z.entrega_gratis_acima > 0 && pratos >= z.entrega_gratis_acima;
  const taxa = gratis ? 0 : z.taxa;
  const falta = !gratis && z.taxa > 0 && z.entrega_gratis_acima ? z.entrega_gratis_acima - pratos : null;
  return { taxa, total: pratos + taxa, falta };
}

// ------------------------------------------------------------ Convida e ganha (montra)
/** As regras do programa para o visitante; null = programa desligado */
export async function lerRegrasConvida(): Promise<RegrasConvida | null> {
  const r = await supabase.rpc('visitante_convida');
  if (r.error) throw r.error;
  return (r.data as RegrasConvida | null) ?? null;
}

// ------------------------------------------------------------ para onde ir depois de entrar
const CHAVE_DESTINO = 'manda-bue:depois-de-entrar';
/** O destino vale 24 h (o mesmo tempo do carrinho guardado) */
const VALIDADE_MS = 24 * 60 * 60 * 1000;
/** Só destinos conhecidos (nunca um caminho vindo de fora) */
const DESTINOS = ['/carrinho', '/convida'] as const;
export type Destino = (typeof DESTINOS)[number];

export async function guardarDestino(destino: Destino): Promise<void> {
  await AsyncStorage.setItem(CHAVE_DESTINO, JSON.stringify({ destino, em: Date.now() })).catch(() => undefined);
}

/**
 * O destino guardado; null se não houver ou já tiver passado o prazo. Não o apaga: a porta de
 * entrada pode abrir mais de uma vez; quem lá chega (o carrinho) apaga-o com limparDestino().
 */
export async function lerDestino(agora = Date.now()): Promise<Destino | null> {
  try {
    const bruto = await AsyncStorage.getItem(CHAVE_DESTINO);
    if (!bruto) return null;
    const { destino, em } = JSON.parse(bruto) as { destino: string; em: number };
    if (typeof em !== 'number' || agora - em > VALIDADE_MS) return null;
    return (DESTINOS as readonly string[]).includes(destino) ? (destino as Destino) : null;
  } catch {
    return null;
  }
}

export async function limparDestino(): Promise<void> {
  await AsyncStorage.removeItem(CHAVE_DESTINO).catch(() => undefined);
}

/** Texto do desconto do convite para o visitante */
export function textoConviteVisitante(c: { desconto: number; minimo: number } | null, formatar: (v: number) => string): string | null {
  if (!c || c.desconto <= 0) return null;
  const minimo = c.minimo > 0 ? ` (pedido a partir de ${formatar(c.minimo)})` : '';
  return `🎁 Convite aplicado: −${formatar(c.desconto)} no teu 1.º pedido${minimo}.`;
}
