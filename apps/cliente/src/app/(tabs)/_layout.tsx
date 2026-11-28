import { Redirect } from 'expo-router';
import { Tabs } from 'expo-router/js-tabs';
import Ionicons from '@expo/vector-icons/Ionicons';
import type { ComponentProps } from 'react';
import { type ColorValue, Text } from 'react-native';

import { Sino, SinoVisitante } from '@/components/Sino';
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

/** «Convida e Ganha» na cor da marca e a negrito; encolhe o tamanho para caber sempre inteiro (nunca cortado) */
function EtiquetaConvida({ activo }: { activo: boolean }) {
  return (
    <Text
      numberOfLines={1}
      adjustsFontSizeToFit
      minimumFontScale={0.75}
      style={{ fontSize: 11, fontWeight: activo ? '800' : '700', color: cores.marca, paddingHorizontal: 2 }}>
      Convida e Ganha
    </Text>
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
        headerRight: () => (visitante ? <SinoVisitante /> : <Sino />),
      }}>
      <Tabs.Screen name="inicio" options={{ title: 'Início', headerTitle: 'Cozinha da Alexandra', tabBarIcon: icone('restaurant-outline', 'restaurant') }} />
      <Tabs.Screen name="pedidos" options={{ title: 'Pedidos', tabBarIcon: icone('receipt-outline', 'receipt') }} />
      {/* Interruptor desligado: o separador não aparece */}
      {/* Convida e Ganha em destaque (Cialdini/Skinner: a recompensa sempre à vista): sempre na cor da marca,
          presente cheio e um pouco maior, e o nome inteiro em qualquer telemóvel */}
      <Tabs.Screen
        name="convida"
        options={{
          title: 'Convida e Ganha',
          tabBarLabel: ({ focused }) => <EtiquetaConvida activo={focused} />,
          tabBarAccessibilityLabel: 'Convida e Ganha',
          tabBarIcon: ({ size, focused }) => <Ionicons name="gift" size={focused ? size + 4 : size + 2} color={cores.marca} />,
          href: ligada('indicacao') ? undefined : null,
        }}
      />
      {/* Sem conta, o separador diz «Entrar»: quem já é cliente encontra logo onde entrar */}
      <Tabs.Screen name="conta" options={{ title: visitante ? 'Entrar' : 'Conta', tabBarIcon: icone('person-outline', 'person') }} />
    </Tabs>
  );
}
