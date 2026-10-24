import AsyncStorage from '@react-native-async-storage/async-storage';

const CHAVE_MODO_ESTAFETA = 'op.modo_estafeta';

/** Lê a preferência guardada do modo estafeta. null = o utilizador nunca escolheu. */
export async function lerModoEstafeta(): Promise<boolean | null> {
  try {
    const v = await AsyncStorage.getItem(CHAVE_MODO_ESTAFETA);
    return v === null ? null : v === '1';
  } catch {
    return null;
  }
}

/** Guarda a escolha do utilizador (nunca rebenta se o armazenamento falhar). */
export async function guardarModoEstafeta(v: boolean): Promise<void> {
  try {
    await AsyncStorage.setItem(CHAVE_MODO_ESTAFETA, v ? '1' : '0');
  } catch {
    // sem armazenamento: fica só para esta sessão
  }
}

/**
 * Estado inicial do modo estafeta:
 * 1) se vier forçado (atalho "As minhas entregas"), liga;
 * 2) senão, respeita a escolha guardada;
 * 3) senão, o default inteligente: ligado para o estafeta puro (entrega mas não gere).
 */
export function modoEstafetaInicial(o: {
  entregar: boolean;
  gerir: boolean;
  guardado: boolean | null;
  forcado: boolean;
}): boolean {
  if (!o.entregar) return false;
  if (o.forcado) return true;
  if (o.guardado !== null) return o.guardado;
  return o.entregar && !o.gerir;
}
