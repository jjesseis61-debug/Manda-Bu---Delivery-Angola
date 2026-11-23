import * as Location from 'expo-location';

import { supabase } from './supabase';
import { horaLuanda } from './formatar';
import type { CozinhaParaPedir } from './tipos';

/** A partir de quantos km a mais o balcão escolhido merece o aviso «há um mais perto» */
export const DIFERENCA_KM_AVISO = 5;

function verificar<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw r.error;
  return r.data as T;
}

/** Balcões ordenados pela distância a uma posição (GPS «perto de mim»), mais perto primeiro */
export async function cozinhasPertoDe(lat: number, lng: number): Promise<CozinhaParaPedir[]> {
  return (verificar(await supabase.rpc('cozinhas_perto_de', { p_lat: lat, p_lng: lng })) as CozinhaParaPedir[]) ?? [];
}

/** Posição actual do telemóvel, pedindo autorização; null se o cliente não deixar ou falhar */
export async function posicaoActual(): Promise<{ lat: number; lng: number } | null> {
  try {
    let { status } = await Location.getForegroundPermissionsAsync();
    if (status !== 'granted') ({ status } = await Location.requestForegroundPermissionsAsync());
    if (status !== 'granted') return null;
    const conhecida = await Location.getLastKnownPositionAsync({ maxAge: 5 * 60_000 });
    const pos = conhecida ?? (await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced }));
    return { lat: pos.coords.latitude, lng: pos.coords.longitude };
  } catch {
    return null;
  }
}

/**
 * O balcão escolhido está bem mais longe do que o mais perto da lista (ordenada pela morada ou pelo GPS)?
 * Devolve os dois para o aviso; null se está bem escolhido ou se faltam distâncias.
 */
export function balcaoLonge(
  lista: CozinhaParaPedir[],
  actualId: string | null,
  limiteKm = DIFERENCA_KM_AVISO,
): { actual: CozinhaParaPedir; perto: CozinhaParaPedir } | null {
  const actual = lista.find((c) => c.cozinha_id === actualId);
  const perto = lista.filter((c) => c.distancia_km != null).sort((a, b) => (a.distancia_km ?? 0) - (b.distancia_km ?? 0))[0];
  if (!actual || !perto || actual.distancia_km == null || perto.cozinha_id === actual.cozinha_id) return null;
  return actual.distancia_km - (perto.distancia_km ?? 0) >= limiteKm ? { actual, perto } : null;
}

/** Prato fora do horário agora, com a próxima vez que está à venda */
export type PratoMaisTarde = { cardapio_id: string; nome: string; preco: number; foto_url: string | null; categoria: string | null; proxima: string };

export async function cardapioMaisTarde(cozinhaId: string): Promise<PratoMaisTarde[]> {
  return ((verificar(await supabase.rpc('cardapio_mais_tarde', { p_cozinha: cozinhaId })) as PratoMaisTarde[]) ?? []).map((p) => ({
    ...p,
    preco: Number(p.preco),
  }));
}

const DIAS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];

/** «hoje às 12h00», «amanhã às 12h00», «sex 28/11 às 12h00» (hora de Luanda) */
export function textoQuandoVolta(iso: string, agora: Date = new Date()): string {
  const diaLuanda = (d: Date) => new Date(d.getTime() + 3600_000).toISOString().slice(0, 10);
  const dia = diaLuanda(new Date(iso));
  const hoje = diaLuanda(agora);
  const amanha = diaLuanda(new Date(agora.getTime() + 86_400_000));
  const hora = horaLuanda(iso);
  if (dia === hoje) return `hoje às ${hora}`;
  if (dia === amanha) return `amanhã às ${hora}`;
  const semana = DIAS[new Date(`${dia}T12:00:00Z`).getUTCDay()];
  return `${semana} ${dia.slice(8, 10)}/${dia.slice(5, 7)} às ${hora}`;
}

/** Ids de pratos num erro do servidor (o «detail» do item_indisponivel traz o id do prato) */
export function pratoDoErro(e: unknown): string | null {
  if (!e || typeof e !== 'object') return null;
  const { message, details } = e as { message?: string; details?: string };
  return message === 'item_indisponivel' && typeof details === 'string' && /^[0-9a-f-]{36}$/i.test(details) ? details : null;
}
