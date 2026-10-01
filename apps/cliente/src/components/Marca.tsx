import { Text, View } from 'react-native';

import { cores } from '@/lib/tema';

/** Manda Bué como marca principal; Delivery Angola como descritivo, em tamanho menor */
export function Marca({ grande = false }: { grande?: boolean }) {
  return (
    <View style={{ alignItems: grande ? 'center' : 'flex-start' }}>
      <Text style={{ fontSize: grande ? 36 : 22, fontWeight: '800', color: cores.marca }}>Manda Bué</Text>
      <Text style={{ fontSize: grande ? 15 : 12, color: cores.textoSuave, letterSpacing: 0.5 }}>Delivery Angola</Text>
    </View>
  );
}
