import { Image, Text, View } from 'react-native';

import { cores } from '@/lib/tema';

const simbolo = require('../../assets/icon.png');

/** Manda Bué como marca principal; Delivery Angola como descritivo, em tamanho menor */
export function Marca({ grande = false }: { grande?: boolean }) {
  return (
    <View style={{ alignItems: grande ? 'center' : 'flex-start' }}>
      {grande && (
        <Image source={simbolo} style={{ width: 88, height: 88, borderRadius: 22, marginBottom: 12 }} accessibilityIgnoresInvertColors />
      )}
      <Text style={{ fontSize: grande ? 36 : 22, fontWeight: '800', color: cores.texto }}>
        Manda <Text style={{ color: cores.marca }}>Bué</Text>
      </Text>
      <Text style={{ fontSize: grande ? 15 : 12, color: cores.textoSuave, letterSpacing: 0.5 }}>Delivery Angola</Text>
    </View>
  );
}
