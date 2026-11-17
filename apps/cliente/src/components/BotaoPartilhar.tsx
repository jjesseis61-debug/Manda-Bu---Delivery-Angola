import Ionicons from '@expo/vector-icons/Ionicons';
import { Pressable, Text } from 'react-native';

import { usePartilhar } from '@/components/Partilhar';
import { cores, espaco } from '@/lib/tema';

/** «Partilhar» um prato no WhatsApp; com conta leva o código de convite; sem conta propõe «Partilha e ganha» */
export function BotaoPartilhar({ nome, id }: { nome: string; id: string }) {
  const { partilhar, convite, folhas } = usePartilhar();
  return (
    <>
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Partilhar ${nome.trim()} no WhatsApp`}
      onPress={() => void partilhar(nome, id)}
      hitSlop={8}
      style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.xs, alignSelf: 'flex-start', paddingVertical: espaco.xs }}>
      <Ionicons name="share-social-outline" size={18} color={cores.marca} />
      <Text style={{ color: cores.marca, fontWeight: '600' }}>
        {convite ? `Partilhar · o amigo ganha desconto` : 'Partilhar'}
      </Text>
    </Pressable>
    {folhas}
    </>
  );
}
