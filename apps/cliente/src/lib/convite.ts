import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Linking from 'expo-linking';

import { normalizarCodigo } from './formatar';

const CHAVE = 'manda-bue:codigo-convite';

/** Guarda o código que chegou pelo link de convite, para pré-preencher C2 */
export async function guardarCodigoPendente(codigo: string): Promise<string | null> {
  const normalizado = normalizarCodigo(codigo);
  if (normalizado) await AsyncStorage.setItem(CHAVE, normalizado);
  return normalizado;
}

export async function lerCodigoPendente(): Promise<string | null> {
  return normalizarCodigo(await AsyncStorage.getItem(CHAVE));
}

export async function limparCodigoPendente(): Promise<void> {
  await AsyncStorage.removeItem(CHAVE);
}

/** Package Android da app do cliente (igual ao app.json) */
const PACOTE_ANDROID = 'ao.mandabue.cliente';

/**
 * Link de convite: a página da Play Store com o código no `referrer`. É um https (clicável no
 * WhatsApp) e, ao instalar pela Play Store, a Google entrega o código à app no 1.º arranque
 * (Install Referrer — Fase 2). Quem já tem a app continua a poder usar o código em texto.
 */
export function linkConvite(codigo: string): string {
  const normalizado = normalizarCodigo(codigo) ?? codigo;
  return `https://play.google.com/store/apps/details?id=${PACOTE_ANDROID}&referrer=${encodeURIComponent(normalizado)}`;
}

/** Link do pedido de grupo: abre a app em /grupo/G-ABC123 */
export function linkGrupo(codigo: string): string {
  return Linking.createURL(`/grupo/${codigo}`);
}
