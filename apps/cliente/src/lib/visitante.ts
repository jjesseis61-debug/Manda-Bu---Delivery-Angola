// Visitante: quem abre o link de um prato sem conta. Vê o prato e o cardápio daquela cozinha,
// monta o carrinho (guardado 24 h) e só entra/cria conta ao carregar em «Pedir».
// As leituras são do servidor (visitante_prato / visitante_cardapio): só o que a app já mostra.
import AsyncStorage from '@react-native-async-storage/async-storage';

import { supabase } from './supabase';
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
export type ZonaVisitante = { id: string; nome: string };
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

// ------------------------------------------------------------ para onde ir depois de entrar
const CHAVE_DESTINO = 'manda-bue:depois-de-entrar';
/** O destino vale 24 h (o mesmo tempo do carrinho guardado) */
const VALIDADE_MS = 24 * 60 * 60 * 1000;
/** Só destinos conhecidos (nunca um caminho vindo de fora) */
const DESTINOS = ['/carrinho'] as const;
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
