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

/** Link de convite: abre a app em /convite/MB-1234 (esquema mandabue://) */
export function linkConvite(codigo: string): string {
  return Linking.createURL(`/convite/${codigo}`);
}

/** Link do pedido de grupo: abre a app em /grupo/G-ABC123 */
export function linkGrupo(codigo: string): string {
  return Linking.createURL(`/grupo/${codigo}`);
}
