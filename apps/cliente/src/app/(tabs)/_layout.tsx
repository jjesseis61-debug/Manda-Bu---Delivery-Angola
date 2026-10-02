import { Redirect } from 'expo-router';
import { Tabs } from 'expo-router/js-tabs';
import Ionicons from '@expo/vector-icons/Ionicons';
import type { ComponentProps } from 'react';
import type { ColorValue } from 'react-native';

import { ACarregar } from '@/components/ui';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';

type NomeIcone = ComponentProps<typeof Ionicons>['name'];

/** Ícones de linha num só tom: cinzento inactivo, cor da marca activo (cheio quando activo) */
function icone(nome: NomeIcone, nomeActivo: NomeIcone) {
  return function Icone({ color, focused, size }: { color: ColorValue; focused: boolean; size: number }) {
    return <Ionicons name={focused ? nomeActivo : nome} size={size} color={color as string} />;
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
      <Tabs.Screen name="inicio" options={{ title: 'Início', headerTitle: 'Manda Bué', tabBarIcon: icone('restaurant-outline', 'restaurant') }} />
      <Tabs.Screen name="pedidos" options={{ title: 'Pedidos', tabBarIcon: icone('receipt-outline', 'receipt') }} />
      {/* Interruptor desligado: o separador não aparece */}
      <Tabs.Screen
        name="convida"
        options={{ title: 'Convida e Ganha', tabBarIcon: icone('gift-outline', 'gift'), href: ligada('indicacao') ? undefined : null }}
      />
      <Tabs.Screen name="conta" options={{ title: 'Conta', tabBarIcon: icone('person-outline', 'person') }} />
    </Tabs>
  );
}
