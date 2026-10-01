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
      </Stack>
      <StatusBar style="dark" />
    </SessaoProvider>
  );
}
