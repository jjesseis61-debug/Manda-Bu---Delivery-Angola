import { useRef } from 'react';
import { Pressable, Text, TextInput, View } from 'react-native';

import { cores, espaco, raio } from '@/lib/tema';

/**
 * Código de confirmação em caixas (uma por dígito). Por trás há um único TextInput transparente que
 * capta a escrita e o preenchimento automático do sistema (autofill do SMS); tocar em qualquer caixa
 * abre o teclado. Só dígitos.
 */
export function CodigoOtp({ valor, aoMudar, digitos = 6 }: { valor: string; aoMudar: (v: string) => void; digitos?: number }) {
  const ref = useRef<TextInput>(null);
  return (
    <Pressable onPress={() => ref.current?.focus()} accessibilityLabel="Código de confirmação">
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
        {Array.from({ length: digitos }).map((_, i) => {
          const activa = i === Math.min(valor.length, digitos - 1);
          return (
            <View
              key={i}
              style={{
                flex: 1,
                height: 58,
                borderRadius: raio,
                borderWidth: activa ? 2 : 1,
                borderColor: activa ? cores.marca : cores.contorno,
                backgroundColor: '#fff',
                alignItems: 'center',
                justifyContent: 'center',
              }}>
              <Text style={{ fontSize: 24, fontWeight: '700', color: cores.texto }}>{valor[i] ?? ''}</Text>
            </View>
          );
        })}
      </View>
      <TextInput
        ref={ref}
        value={valor}
        onChangeText={(t) => aoMudar(t.replace(/\D/g, '').slice(0, digitos))}
        keyboardType="number-pad"
        autoComplete="sms-otp"
        textContentType="oneTimeCode"
        autoFocus
        maxLength={digitos}
        caretHidden
        accessibilityLabel="Código de confirmação"
        style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 58, opacity: 0 }}
      />
    </Pressable>
  );
}
