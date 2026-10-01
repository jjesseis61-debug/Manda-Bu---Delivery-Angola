import * as Notifications from 'expo-notifications';
import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';

import { CarrinhoProvider } from '@/lib/carrinho';
import { activarPush, desactivarPush, rotaDaNotificacao } from '@/lib/push';
import { SessaoProvider, useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';

/** Regista o telemóvel para push depois do registo e abre o ecrã certo ao tocar numa notificação */
function EfeitosSessao() {
  const { perfil } = useSessao();
  const router = useRouter();

  useEffect(() => {
    if (perfil) void activarPush().catch(() => undefined);
  }, [perfil]);

  useEffect(() => {
    const sub = Notifications.addNotificationResponseReceivedListener((resposta) => {
      const rota = rotaDaNotificacao(resposta.notification.request.content.data?.codigo);
      if (rota) router.push(rota);
    });
    return () => sub.remove();
  }, [router]);

  return null;
}

export default function LayoutRaiz() {
  return (
    <SessaoProvider aoSair={desactivarPush}>
      <CarrinhoProvider>
        <EfeitosSessao />
        <Stack
          screenOptions={{
            headerTintColor: cores.marca,
            headerTitleStyle: { color: cores.texto },
            headerBackButtonDisplayMode: 'minimal',
          }}>
          <Stack.Screen name="index" options={{ headerShown: false }} />
          <Stack.Screen name="entrar" options={{ headerShown: false }} />
          <Stack.Screen name="registo" options={{ title: 'Criar conta', headerBackVisible: false }} />
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="convite/[codigo]" options={{ headerShown: false }} />
          <Stack.Screen name="carrinho" options={{ title: 'O teu pedido' }} />
          <Stack.Screen name="pedido/[id]" options={{ title: 'Pedido' }} />
          <Stack.Screen name="levantar" options={{ title: 'Levantar saldo' }} />
          <Stack.Screen name="como-funciona" options={{ title: 'Como funciona' }} />
          <Stack.Screen name="cozinha" options={{ title: 'A cozinha' }} />
          <Stack.Screen name="destaques" options={{ title: 'Destaques do mês' }} />
          <Stack.Screen name="privacidade" options={{ title: 'Privacidade na lista' }} />
          <Stack.Screen name="notificacoes" options={{ title: 'Notificações' }} />
          <Stack.Screen name="enderecos/index" options={{ title: 'Endereços' }} />
          <Stack.Screen name="enderecos/novo" options={{ title: 'Novo endereço' }} />
        </Stack>
        <StatusBar style="dark" />
      </CarrinhoProvider>
    </SessaoProvider>
  );
}
