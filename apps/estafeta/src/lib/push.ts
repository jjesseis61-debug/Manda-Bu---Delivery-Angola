import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import type { Href } from 'expo-router';
import { Platform } from 'react-native';

import { registarTokenPush, removerTokenPush } from './api';

const CHAVE = 'manda-bue-estafeta:token-push';
const CHAVE_ESTADO = 'manda-bue-estafeta:push-estado'; // diagnóstico: porque é que o push (não) registou

/** Estado do último registo de push, para mostrar no ecrã (diagnóstico). */
export async function estadoDoPush(): Promise<string> {
  try {
    return (await AsyncStorage.getItem(CHAVE_ESTADO)) ?? 'por iniciar';
  } catch {
    return 'por iniciar';
  }
}
async function guardarEstado(s: string): Promise<void> {
  try {
    await AsyncStorage.setItem(CHAVE_ESTADO, s);
  } catch {
    // ignora
  }
}

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
  try {
    const id = projectId();
    if (Platform.OS === 'web') return void (await guardarEstado('web (sem push)'));
    if (!Device.isDevice) return void (await guardarEstado('emulador (sem push)'));
    if (!id) return void (await guardarEstado('sem projectId no build'));

    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'Manda Bué Estafeta',
        importance: Notifications.AndroidImportance.DEFAULT,
      });
    }
    let { status } = await Notifications.getPermissionsAsync();
    if (status !== 'granted') ({ status } = await Notifications.requestPermissionsAsync());
    if (status !== 'granted') return void (await guardarEstado('sem permissão: ' + status));

    const token = (await Notifications.getExpoPushTokenAsync({ projectId: id })).data;
    await registarTokenPush(token, Platform.OS);
    await AsyncStorage.setItem(CHAVE, token);
    await guardarEstado('ok · projeto ' + id.slice(0, 8) + ' · ' + token.slice(0, 26) + '…');
  } catch (e) {
    await guardarEstado('ERRO: ' + ((e as Error)?.message ?? String(e)));
  }
}

/** Ao sair: este telemóvel deixa de receber as notificações do funcionário */
export async function desactivarPush(): Promise<void> {
  const token = await AsyncStorage.getItem(CHAVE);
  if (!token) return;
  await removerTokenPush(token).catch(() => undefined);
  await AsyncStorage.removeItem(CHAVE);
}

/**
 * Ecrã a abrir quando o estafeta toca numa notificação. Nesta app tudo leva às entregas de hoje
 * (onde o estafeta vê e trata os seus pedidos). Mantém-se a mesma assinatura das outras apps.
 */
export function rotaDaNotificacao(dados: unknown): Href | null {
  const codigo = (dados as { codigo?: unknown } | null | undefined)?.codigo;
  const pedidoId = (dados as { pedido_id?: unknown } | null | undefined)?.pedido_id;
  if (typeof pedidoId === 'string' || typeof codigo === 'string') return '/inicio';
  return null;
}
