// Cadeado opcional da app (PIN + biometria), só NESTE aparelho. O login continua a ser por
// SMS; isto protege a app já aberta (telemóvel desbloqueado nas mãos de outra pessoa).
// O PIN nunca é guardado: guarda-se o SHA-512 de (sal aleatório + PIN) no cofre do sistema
// (Keychain / Keystore). Nada disto vai ao servidor. Ver docs/plano-cadeado-conta.md.
import * as Crypto from 'expo-crypto';
import * as LocalAuthentication from 'expo-local-authentication';
import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

/** Tempo em segundo plano a partir do qual se volta a pedir o código */
export const GRACA_MS = 60_000;
/** A partir de tantas falhas só resta "Esqueci o código" (entrar outra vez por SMS) */
export const MAX_FALHAS = 10;

const K = {
  activo: 'cadeado.activo',
  sal: 'cadeado.sal',
  hash: 'cadeado.hash',
  tamanho: 'cadeado.tamanho',
  biometria: 'cadeado.biometria',
  falhas: 'cadeado.falhas',
  falhaEm: 'cadeado.falha_em',
};

/** Só nas apps (Android/iOS). Na versão web não há cofre seguro nem biometria. */
export function cadeadoSuportado(): boolean {
  return Platform.OS === 'android' || Platform.OS === 'ios';
}

/** PIN de 4 a 6 dígitos, sem os demasiado fáceis (1111, 1234, 4321...) */
export function validarPin(pin: string): string | null {
  if (!/^\d{4,6}$/.test(pin)) return 'O código tem de ter 4 a 6 números.';
  if (/^(\d)\1+$/.test(pin)) return 'Evita repetir o mesmo número.';
  const d = pin.split('').map(Number);
  const passo = d[1] - d[0];
  if ((passo === 1 || passo === -1) && d.every((x, i) => i === 0 || x - d[i - 1] === passo)) {
    return 'Evita números seguidos (ex.: 1234).';
  }
  return null;
}

/** Espera depois de várias falhas: nada até 4; depois 30 s, 60 s, 90 s... até 5 min */
export function esperaPorFalhas(falhas: number): number {
  if (falhas < 5) return 0;
  return Math.min((falhas - 4) * 30_000, 5 * 60_000);
}

async function ler(k: string): Promise<string | null> {
  try {
    return await SecureStore.getItemAsync(k);
  } catch {
    return null;
  }
}

async function hashDe(sal: string, pin: string): Promise<string> {
  return Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA512, `${sal}:${pin}`);
}

function salNovo(): string {
  const bytes = Crypto.getRandomBytes(16);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function estaActivo(): Promise<boolean> {
  if (!cadeadoSuportado()) return false;
  return (await ler(K.activo)) === '1' && !!(await ler(K.hash));
}

export async function tamanhoPin(): Promise<number | null> {
  const t = Number(await ler(K.tamanho));
  return t >= 4 && t <= 6 ? t : null;
}

/** Cria (ou troca) o código. Liga o cadeado e limpa as falhas. */
export async function definirPin(pin: string, biometria: boolean): Promise<void> {
  const erro = validarPin(pin);
  if (erro) throw new Error(erro);
  const sal = salNovo();
  await SecureStore.setItemAsync(K.sal, sal);
  await SecureStore.setItemAsync(K.hash, await hashDe(sal, pin));
  await SecureStore.setItemAsync(K.tamanho, String(pin.length));
  await SecureStore.setItemAsync(K.biometria, biometria ? '1' : '0');
  await SecureStore.setItemAsync(K.falhas, '0');
  await SecureStore.deleteItemAsync(K.falhaEm);
  await SecureStore.setItemAsync(K.activo, '1');
}

export async function definirBiometria(ligada: boolean): Promise<void> {
  await SecureStore.setItemAsync(K.biometria, ligada ? '1' : '0');
}

/** Desliga e apaga tudo (ao desligar, ao sair da conta ou em "Esqueci o código") */
export async function removerCadeado(): Promise<void> {
  if (!cadeadoSuportado()) return;
  for (const k of Object.values(K)) await SecureStore.deleteItemAsync(k).catch(() => undefined);
}

export type EstadoFalhas = { falhas: number; esperaMs: number; esgotado: boolean };

/** Falhas acumuladas e quanto falta esperar (para mostrar no ecrã) */
export async function estadoFalhas(agora = Date.now()): Promise<EstadoFalhas> {
  const falhas = Number(await ler(K.falhas)) || 0;
  const em = Number(await ler(K.falhaEm)) || 0;
  const esperaMs = Math.max(0, em + esperaPorFalhas(falhas) - agora);
  return { falhas, esperaMs, esgotado: falhas >= MAX_FALHAS };
}

/** Verifica o código. Respeita a espera depois de falhas; conta a falha se errar. */
export async function verificarPin(pin: string, agora = Date.now()): Promise<{ ok: true } | ({ ok: false } & EstadoFalhas)> {
  const antes = await estadoFalhas(agora);
  if (antes.esgotado || antes.esperaMs > 0) return { ok: false, ...antes };
  const sal = await ler(K.sal);
  const hash = await ler(K.hash);
  if (sal && hash && (await hashDe(sal, pin)) === hash) {
    await limparFalhas();
    return { ok: true };
  }
  const falhas = antes.falhas + 1;
  await SecureStore.setItemAsync(K.falhas, String(falhas));
  await SecureStore.setItemAsync(K.falhaEm, String(agora));
  return { ok: false, falhas, esperaMs: esperaPorFalhas(falhas), esgotado: falhas >= MAX_FALHAS };
}

export async function limparFalhas(): Promise<void> {
  await SecureStore.setItemAsync(K.falhas, '0');
  await SecureStore.deleteItemAsync(K.falhaEm).catch(() => undefined);
}

/** O aparelho tem biometria (impressão digital / rosto) registada? */
export async function biometriaDisponivel(): Promise<boolean> {
  if (!cadeadoSuportado()) return false;
  try {
    return (await LocalAuthentication.hasHardwareAsync()) && (await LocalAuthentication.isEnrolledAsync());
  } catch {
    return false;
  }
}

/** Biometria ligada no cadeado E ainda disponível no aparelho */
export async function usaBiometria(): Promise<boolean> {
  return (await ler(K.biometria)) === '1' && (await biometriaDisponivel());
}

/** Pede a biometria; false se cancelar, falhar ou não houver (o PIN fica sempre como alternativa) */
export async function pedirBiometria(motivo: string): Promise<boolean> {
  try {
    const r = await LocalAuthentication.authenticateAsync({
      promptMessage: motivo,
      cancelLabel: 'Usar código',
      disableDeviceFallback: true,
    });
    if (r.success) await limparFalhas();
    return r.success;
  } catch {
    return false;
  }
}
