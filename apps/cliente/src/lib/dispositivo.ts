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
