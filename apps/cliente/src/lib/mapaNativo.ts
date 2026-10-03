// O mapa nativo só pode ser mostrado se existir: no Android o Google Maps sem chave fecha a app.
import Constants from 'expo-constants';
import { Platform } from 'react-native';

/** true se o mapa pode ser desenhado (iOS usa o Apple Maps; Android precisa da chave no build) */
export function mapaDisponivel(os: string, extra: Record<string, unknown> | undefined): boolean {
  return os !== 'android' || extra?.mapaGoogle === true;
}

export const MAPA_NATIVO = mapaDisponivel(Platform.OS, Constants.expoConfig?.extra);
