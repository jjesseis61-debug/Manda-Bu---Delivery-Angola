import AsyncStorage from '@react-native-async-storage/async-storage';

const CHAVE = 'manda-bue:dispositivo-id';
let emMemoria: string | null = null;

/** UUID v4 gerado no telemóvel (ids criados offline, sem colisões entre dispositivos) */
export function novoId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

/** Identificador desta instalação, enviado em pedidos.dispositivo_id (sinal "mesmo dispositivo" do programa) */
export async function dispositivoId(): Promise<string> {
  if (emMemoria) return emMemoria;
  const guardado = await AsyncStorage.getItem(CHAVE);
  emMemoria = guardado ?? novoId();
  if (!guardado) await AsyncStorage.setItem(CHAVE, emMemoria);
  return emMemoria;
}

/**
 * Regista em que aparelho esta conta entrou (antifraude do Convida, sem bloquear ninguém).
 * Na app: o id da instalação + o id do aparelho (Android ID / iOS vendor), que não muda ao
 * reinstalar. Na web (PWA) o navegador não dá o id do aparelho: vai só o id do navegador.
 * Nunca falha a app: qualquer erro é ignorado.
 */
export async function registarEsteAparelho(): Promise<void> {
  try {
    const { Platform } = await import('react-native');
    const plataforma = Platform.OS === 'android' || Platform.OS === 'ios' ? Platform.OS : 'web';
    let aparelho: string | null = null;
    let modelo: string | null = null;
    if (plataforma !== 'web') {
      const Application = await import('expo-application');
      const Device = await import('expo-device');
      aparelho = plataforma === 'android' ? Application.getAndroidId() : await Application.getIosIdForVendorAsync();
      modelo = [Device.manufacturer, Device.modelName].filter(Boolean).join(' ') || null;
    }
    const { registarAparelho } = await import('./api');
    await registarAparelho(await dispositivoId(), aparelho, plataforma, modelo);
  } catch {
    // Sem rede ou sem permissão: tenta de novo na próxima abertura
  }
}
