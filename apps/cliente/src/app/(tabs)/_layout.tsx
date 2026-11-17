import { Redirect, useRouter } from 'expo-router';
import { Tabs } from 'expo-router/js-tabs';
import Ionicons from '@expo/vector-icons/Ionicons';
import type { ComponentProps } from 'react';
import type { ColorValue } from 'react-native';

import { Sino } from '@/components/Sino';
import { Pressable, Text } from 'react-native';

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

/** No cabeçalho do visitante, em vez do sino: quem já tem conta encontra logo onde entrar */
function BotaoEntrar() {
  const router = useRouter();
  return (
    <Pressable accessibilityRole="button" onPress={() => router.push('/entrar')} hitSlop={8} style={{ marginRight: 16 }}>
      <Text style={{ color: cores.marca, fontWeight: '800', fontSize: 16 }}>Entrar</Text>
    </Pressable>
  );
}

export default function LayoutSeparadores() {
  const { carregado, sessao, perfil, ligada } = useSessao();
  if (!carregado) return <ACarregar />;
  // Sem conta a app abre na mesma (visitante): o número só é pedido no «Pedir».
  // Com sessão mas sem registo (a meio de criar conta): acaba o registo.
  if (sessao && !perfil) return <Redirect href="/registo" />;
  const visitante = !sessao;

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: cores.marca,
        tabBarInactiveTintColor: cores.textoSuave,
        headerTitleStyle: { color: cores.texto },
        headerRight: () => (visitante ? <BotaoEntrar /> : <Sino />),
      }}>
      <Tabs.Screen name="inicio" options={{ title: 'Início', headerTitle: 'Cozinha da Alexandra', tabBarIcon: icone('restaurant-outline', 'restaurant') }} />
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
