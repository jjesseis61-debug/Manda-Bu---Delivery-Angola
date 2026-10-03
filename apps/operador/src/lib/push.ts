import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

import { registarTokenPush, removerTokenPush } from './api';

const CHAVE = 'manda-bue-operador:token-push';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

function projectId(): string | undefined {
  return (Constants.expoConfig?.extra?.eas?.projectId as string | undefined) ?? Constants.easConfig?.projectId;
}

/**
 * Regista o token Expo deste telemóvel para o funcionário (N12).
 * Sem projectId do EAS (app.json → extra.eas.projectId), num simulador ou na web, não faz nada.
 */
export async function activarPush(): Promise<void> {
  const id = projectId();
  if (Platform.OS === 'web' || !Device.isDevice || !id) return;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'Manda Bué Operador',
      importance: Notifications.AndroidImportance.DEFAULT,
    });
  }
  let { status } = await Notifications.getPermissionsAsync();
  if (status !== 'granted') ({ status } = await Notifications.requestPermissionsAsync());
  if (status !== 'granted') return;

  const token = (await Notifications.getExpoPushTokenAsync({ projectId: id })).data;
  await registarTokenPush(token, Platform.OS);
  await AsyncStorage.setItem(CHAVE, token);
}

/** Ao sair: este telemóvel deixa de receber as notificações do funcionário */
export async function desactivarPush(): Promise<void> {
  const token = await AsyncStorage.getItem(CHAVE);
  if (!token) return;
  await removerTokenPush(token).catch(() => undefined);
  await AsyncStorage.removeItem(CHAVE);
}

/** Ecrã a abrir quando o funcionário toca numa notificação */
export function rotaDaNotificacao(dados: unknown): '/equipa' | '/pacotes' | '/entregas' | '/reclamacoes' | '/conferencia' | '/analista' | '/vigilancia' | '/turno' | null {
  const codigo = (dados as { codigo?: unknown } | null | undefined)?.codigo;
  if (codigo === 'N12') return '/equipa';
  if (codigo === 'N15') return '/pacotes';
  if (codigo === 'N17' || codigo === 'N18' || codigo === 'N19') return '/entregas';
  if (codigo === 'N21') return '/reclamacoes';
  if (codigo === 'N24') return '/conferencia';
  if (codigo === 'N25') return '/analista';
  if (codigo === 'N26') return '/vigilancia';
  if (codigo === 'N27') return '/turno';
  return null;
}
