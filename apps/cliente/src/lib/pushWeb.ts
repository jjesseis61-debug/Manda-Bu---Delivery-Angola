// Notificações push na versão web (PWA): o navegador regista uma assinatura Web Push com a
// chave pública VAPID e o servidor manda os avisos para ela (mesmo com o site fechado).
// Android/Chrome: funciona no navegador e na PWA instalada. iPhone: só com a PWA adicionada ao
// ecrã principal (iOS 16.4+). Na app instalada (APK) não se usa: aí é o push da Expo.
import { Platform } from 'react-native';

import { chavePublicaPushWeb, registarPushWeb, removerPushWeb } from './api';

// A chave pública vem do servidor (que guarda o par); pede-se uma vez por sessão
let chaveEmCache: string | null = null;
async function chaveVapid(): Promise<string | null> {
  if (!chaveEmCache) chaveEmCache = await chavePublicaPushWeb().catch(() => null);
  return chaveEmCache;
}

export type EstadoPushWeb = 'nao_suportado' | 'instalar_no_iphone' | 'bloqueado' | 'desligado' | 'ligado';

function temApis(): boolean {
  return (
    Platform.OS === 'web' &&
    typeof window !== 'undefined' &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window
  );
}

/** iPhone/iPad no Safari sem a PWA no ecrã principal: o push só funciona depois de a instalar */
export function iphoneSemInstalar(): boolean {
  if (Platform.OS !== 'web' || typeof navigator === 'undefined') return false;
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent);
  const instalada =
    (typeof window !== 'undefined' && window.matchMedia?.('(display-mode: standalone)').matches) ||
    (navigator as unknown as { standalone?: boolean }).standalone === true;
  return ios && !instalada;
}

/** Converte a chave VAPID (base64url) para o formato que o navegador pede */
export function chaveParaBytes(base64url: string): Uint8Array {
  const pad = '='.repeat((4 - (base64url.length % 4)) % 4);
  const b64 = (base64url + pad).replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

async function assinaturaActual(): Promise<PushSubscription | null> {
  const reg = await navigator.serviceWorker.ready;
  return reg.pushManager.getSubscription();
}

export async function estadoPushWeb(): Promise<EstadoPushWeb> {
  if (Platform.OS !== 'web') return 'nao_suportado';
  if (iphoneSemInstalar()) return 'instalar_no_iphone';
  if (!temApis() || !(await chaveVapid())) return 'nao_suportado';
  if (Notification.permission === 'denied') return 'bloqueado';
  if (Notification.permission !== 'granted') return 'desligado';
  return (await assinaturaActual()) ? 'ligado' : 'desligado';
}

async function enviarAssinatura(sub: PushSubscription) {
  const j = sub.toJSON() as { endpoint?: string; keys?: { p256dh?: string; auth?: string } };
  if (!j.endpoint || !j.keys?.p256dh || !j.keys?.auth) throw new Error('Assinatura incompleta.');
  await registarPushWeb(j.endpoint, j.keys.p256dh, j.keys.auth);
}

/** Pede autorização (tem de ser num toque do cliente) e liga os avisos neste navegador */
export async function ligarPushWeb(): Promise<EstadoPushWeb> {
  const VAPID = temApis() ? await chaveVapid() : null;
  if (!VAPID) return 'nao_suportado';
  const permissao = await Notification.requestPermission();
  if (permissao !== 'granted') return permissao === 'denied' ? 'bloqueado' : 'desligado';
  const reg = await navigator.serviceWorker.ready;
  const sub =
    (await reg.pushManager.getSubscription()) ??
    (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: chaveParaBytes(VAPID) as BufferSource }));
  await enviarAssinatura(sub);
  return 'ligado';
}

/** Desliga os avisos neste navegador (ou ao sair da conta) */
export async function desligarPushWeb(): Promise<void> {
  if (!temApis()) return;
  const sub = await assinaturaActual().catch(() => null);
  if (!sub) return;
  await removerPushWeb(sub.endpoint).catch(() => undefined);
  await sub.unsubscribe().catch(() => undefined);
}

/** Ao abrir a PWA com sessão: se já tinha autorizado, volta a enviar a assinatura (pode ter mudado) */
export async function renovarPushWeb(): Promise<void> {
  try {
    if (!temApis() || Notification.permission !== 'granted') return;
    const sub = await assinaturaActual();
    if (sub) await enviarAssinatura(sub);
  } catch {
    // tenta na próxima abertura
  }
}
