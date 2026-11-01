// Cache local das entregas de hoje, para o estafeta ver a última lista conhecida mesmo sem rede
// (fundação do modo offline). É só leitura de conveniência; as acções continuam a precisar de rede
// nesta fase. Guardar/ler nunca rebenta: sem storage, segue sem cache.
import AsyncStorage from '@react-native-async-storage/async-storage';

import type { PedidoOperador } from './tipos';

const CHAVE = 'manda-bue-estafeta:entregas-hoje';

export async function guardarEntregasCache(lista: PedidoOperador[]): Promise<void> {
  try {
    await AsyncStorage.setItem(CHAVE, JSON.stringify(lista));
  } catch {
    // sem storage: ignora
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
