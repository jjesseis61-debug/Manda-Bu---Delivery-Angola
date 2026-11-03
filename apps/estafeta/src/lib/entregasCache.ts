// Cache local das entregas de hoje, para o estafeta ver a última lista conhecida mesmo sem rede
// (fundação do modo offline). É só leitura de conveniência; as acções continuam a precisar de rede
// nesta fase. Guardar/ler nunca rebenta: sem storage, segue sem cache.
import AsyncStorage from '@react-native-async-storage/async-storage';

import type { Caixa, PedidoOperador } from './tipos';

const CHAVE = 'manda-bue-estafeta:entregas-hoje';
const CHAVE_EM = 'manda-bue-estafeta:entregas-hoje-em'; // quando foi a última carga com sucesso
const CHAVE_CAIXAS = 'manda-bue-estafeta:caixas';

export async function guardarEntregasCache(lista: PedidoOperador[]): Promise<void> {
  try {
    await AsyncStorage.multiSet([
      [CHAVE, JSON.stringify(lista)],
      [CHAVE_EM, String(Date.now())],
    ]);
  } catch {
    // sem storage: ignora
  }
}

/** Instante (ms) da última carga com sucesso guardada em cache, ou null. */
export async function lerEntregasCacheEm(): Promise<number | null> {
  try {
    const s = await AsyncStorage.getItem(CHAVE_EM);
    const n = s ? Number(s) : NaN;
    return Number.isFinite(n) ? n : null;
  } catch {
    return null;
  }
}

export async function lerEntregasCache(): Promise<PedidoOperador[] | null> {
  try {
    const s = await AsyncStorage.getItem(CHAVE);
    return s ? (JSON.parse(s) as PedidoOperador[]) : null;
  } catch {
    return null;
  }
}

// Caixas abertas em cache, para a entrega paga em dinheiro funcionar offline (escolher a caixa).
export async function guardarCaixasCache(lista: Caixa[]): Promise<void> {
  try {
    await AsyncStorage.setItem(CHAVE_CAIXAS, JSON.stringify(lista));
  } catch {
    // sem storage: ignora
  }
}

export async function lerCaixasCache(): Promise<Caixa[] | null> {
  try {
    const s = await AsyncStorage.getItem(CHAVE_CAIXAS);
    return s ? (JSON.parse(s) as Caixa[]) : null;
  } catch {
    return null;
  }
}
