import { Redirect } from 'expo-router';
import { Tabs } from 'expo-router/js-tabs';
import { Text, type ColorValue } from 'react-native';

import { ACarregar } from '@/components/ui';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';

function icone(simbolo: string) {
  return function Icone({ color }: { color: ColorValue }) {
    return <Text style={{ fontSize: 18, color }}>{simbolo}</Text>;
  };
}

export default function LayoutSeparadores() {
  const { carregado, sessao, perfil, ligada } = useSessao();
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!perfil) return <Redirect href="/registo" />;

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: cores.marca,
        tabBarInactiveTintColor: cores.textoSuave,
        headerTitleStyle: { color: cores.texto },
      }}>
      <Tabs.Screen name="inicio" options={{ title: 'Início', headerTitle: 'Manda Bué', tabBarIcon: icone('🍽') }} />
      <Tabs.Screen name="pedidos" options={{ title: 'Pedidos', tabBarIcon: icone('🧾') }} />
      {/* Interruptor desligado: o separador não aparece */}
      <Tabs.Screen
        name="convida"
        options={{ title: 'Convida e Ganha', tabBarIcon: icone('🎁'), href: ligada('indicacao') ? undefined : null }}
      />
      <Tabs.Screen name="conta" options={{ title: 'Conta', tabBarIcon: icone('👤') }} />
    </Tabs>
  );
}
