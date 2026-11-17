// «Partilha e ganha»: o visitante que escolhe «Entrar e partilhar» deixa aqui o prato; depois de
// entrar (ou de criar conta), a app abre a partilha sozinha, já com o código de convite.
// O aviso aparece no máximo uma vez a cada 24 h (para não insistir).
import AsyncStorage from '@react-native-async-storage/async-storage';

const CHAVE_PENDENTE = 'manda-bue:partilha-pendente';
const CHAVE_AVISO = 'manda-bue:aviso-partilha';
const PRAZO_PENDENTE_MS = 30 * 60 * 1000; // a partilha espera até 30 min (tempo de receber o código)
const INTERVALO_AVISO_MS = 24 * 60 * 60 * 1000;

export type PartilhaPendente = { nome: string; id: string };

export async function guardarPartilhaPendente(p: PartilhaPendente): Promise<void> {
  await AsyncStorage.setItem(CHAVE_PENDENTE, JSON.stringify({ ...p, em: Date.now() })).catch(() => undefined);
}

/** Tira a partilha pendente (uma só vez); null se não houver ou já tiver passado o prazo */
export async function tirarPartilhaPendente(agora = Date.now()): Promise<PartilhaPendente | null> {
  try {
    const bruto = await AsyncStorage.getItem(CHAVE_PENDENTE);
    if (!bruto) return null;
    await AsyncStorage.removeItem(CHAVE_PENDENTE);
    const p = JSON.parse(bruto) as PartilhaPendente & { em: number };
    if (typeof p.em !== 'number' || agora - p.em > PRAZO_PENDENTE_MS || !p.id || !p.nome) return null;
    return { nome: p.nome, id: p.id };
  } catch {
    return null;
  }
}

/** O aviso «Partilha e ganha» pode aparecer agora? (no máximo uma vez a cada 24 h) */
export async function podeMostrarAvisoPartilha(agora = Date.now()): Promise<boolean> {
  try {
    const ultimo = Number(await AsyncStorage.getItem(CHAVE_AVISO));
    return !Number.isFinite(ultimo) || ultimo <= 0 || agora - ultimo > INTERVALO_AVISO_MS;
  } catch {
    return true;
  }
}

export async function marcarAvisoPartilha(agora = Date.now()): Promise<void> {
  await AsyncStorage.setItem(CHAVE_AVISO, String(agora)).catch(() => undefined);
}
