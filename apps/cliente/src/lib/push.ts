import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

import { registarTokenPush, removerTokenPush } from './api';

const CHAVE = 'manda-bue:token-push';

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
 * Pede autorização e regista o token Expo deste telemóvel no servidor.
 * Sem projectId do EAS (app.json → extra.eas.projectId), num simulador ou na web, não faz nada.
 */
export async function activarPush(): Promise<void> {
  const id = projectId();
  if (Platform.OS === 'web' || !Device.isDevice || !id) return;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'Manda Bué',
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

/** Ao sair da conta: este telemóvel deixa de receber as notificações da conta */
export async function desactivarPush(): Promise<void> {
  const token = await AsyncStorage.getItem(CHAVE);
  if (!token) return;
  await removerTokenPush(token).catch(() => undefined);
  await AsyncStorage.removeItem(CHAVE);
}

/** Ecrã a abrir quando o cliente toca numa notificação */
export function rotaDaNotificacao(dados: unknown): string | null {
  const d = (dados ?? {}) as { codigo?: unknown; pedido_id?: unknown; codigo_grupo?: unknown };
  const codigo = d.codigo;
  if (codigo === 'N2' || codigo === 'N3' || codigo === 'N4' || codigo === 'N5' || codigo === 'N6') return '/convida';
  if (codigo === 'N7') return '/destaques';
  if (codigo === 'N8') return '/levantar';
  if (codigo === 'N13' || codigo === 'N14') return '/pacotes';
  if (codigo === 'N9' && typeof d.pedido_id === 'string') return `/avaliar/${d.pedido_id}`;
  if ((codigo === 'N16' || codigo === 'N20' || codigo === 'N22') && typeof d.pedido_id === 'string') return `/pedido/${d.pedido_id}`;
  if (codigo === 'N30') return '/ajuda';
  if ((codigo === 'N10' || codigo === 'N11') && typeof d.codigo_grupo === 'string') return `/grupo/${d.codigo_grupo}`;
  return null;
}
