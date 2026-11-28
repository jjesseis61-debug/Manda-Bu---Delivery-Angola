import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

import { SessaoProvider } from '@/lib/sessao';
import { cores } from '@/lib/tema';

export default function LayoutRaiz() {
  return (
    <SessaoProvider>
      <Stack
        screenOptions={{
          headerTintColor: cores.marca,
          headerTitleStyle: { color: cores.texto },
          headerBackButtonDisplayMode: 'minimal',
        }}>
        <Stack.Screen name="index" options={{ headerShown: false }} />
        <Stack.Screen name="entrar" options={{ headerShown: false }} />
        <Stack.Screen name="sem-acesso" options={{ headerShown: false }} />
        <Stack.Screen name="inicio" options={{ title: 'Manda Bué · Estafeta', headerBackVisible: false }} />
        <Stack.Screen name="entrega/[id]" options={{ title: 'Entrega' }} />
      </Stack>
      <StatusBar style="dark" />
    </SessaoProvider>
  );
}
