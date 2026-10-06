// Escolha do mapa: por defeito usa-se o OpenStreetMap (grátis, sem chave). O interruptor
// `mapa_google` só troca para o Google Maps se o build tiver a plataforma disponível:
// no iOS usa-se o Apple Maps (sem chave); no Android é preciso a chave do Google Maps no build.
import Constants from 'expo-constants';
import { Platform } from 'react-native';

/** O Google/Apple Maps (react-native-maps) pode ser desenhado neste build? */
export function googleDisponivel(os: string, extra: Record<string, unknown> | undefined): boolean {
  return os === 'ios' || (os === 'android' && extra?.mapaGoogle === true);
}

/** true se o interruptor `mapa_google`, quando ligado, consegue mesmo mostrar o Google/Apple Maps. */
export const GOOGLE_DISPONIVEL = googleDisponivel(Platform.OS, Constants.expoConfig?.extra ?? undefined);

/** Há um mapa onde tocar? No telemóvel há sempre (OpenStreetMap, ou Google). Na web mostra-se texto. */
export const HA_MAPA = Platform.OS !== 'web';
