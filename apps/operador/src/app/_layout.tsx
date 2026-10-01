import * as Notifications from 'expo-notifications';
import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';

import { rotaDaNotificacao } from '@/lib/push';
import { SessaoProvider } from '@/lib/sessao';
import { cores } from '@/lib/tema';

/** Abre o ecrã certo ao tocar numa notificação (N12 -> Equipa) */
function AbrirNotificacoes() {
  const router = useRouter();
  useEffect(() => {
    const sub = Notifications.addNotificationResponseReceivedListener((resposta) => {
      const rota = rotaDaNotificacao(resposta.notification.request.content.data);
      if (rota) router.push(rota);
    });
    return () => sub.remove();
  }, [router]);
  return null;
}

export default function LayoutRaiz() {
  return (
    <SessaoProvider>
      <AbrirNotificacoes />
      <Stack
        screenOptions={{
          headerTintColor: cores.marca,
          headerTitleStyle: { color: cores.texto },
          headerBackButtonDisplayMode: 'minimal',
        }}>
        <Stack.Screen name="index" options={{ headerShown: false }} />
        <Stack.Screen name="entrar" options={{ headerShown: false }} />
        <Stack.Screen name="sem-acesso" options={{ headerShown: false }} />
        <Stack.Screen name="inicio" options={{ title: 'Manda Bué · Operador', headerBackVisible: false }} />
        <Stack.Screen name="painel" options={{ title: 'Painel do programa' }} />
        <Stack.Screen name="verificacao" options={{ title: 'Verificação' }} />
        <Stack.Screen name="levantamentos" options={{ title: 'Levantamentos' }} />
        <Stack.Screen name="embaixadores" options={{ title: 'Embaixadores' }} />
        <Stack.Screen name="parametros" options={{ title: 'Parâmetros e interruptores' }} />
        <Stack.Screen name="cozinhas/index" options={{ title: 'Cozinhas' }} />
        <Stack.Screen name="cozinhas/[id]" options={{ title: 'Cozinha' }} />
        <Stack.Screen name="relatorios" options={{ title: 'Relatórios de cozinha' }} />
        <Stack.Screen name="entregas" options={{ title: 'Pedidos e entregas' }} />
        <Stack.Screen name="moderacao" options={{ title: 'Moderação' }} />
        <Stack.Screen name="equipa" options={{ title: 'Equipa' }} />
        <Stack.Screen name="grupos" options={{ title: 'Grupos do dia' }} />
      </Stack>
      <StatusBar style="dark" />
    </SessaoProvider>
  );
}
