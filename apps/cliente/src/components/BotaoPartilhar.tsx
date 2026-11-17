import Ionicons from '@expo/vector-icons/Ionicons';
import { Pressable, Text } from 'react-native';

import { partilharPrato, type ConvitePartilha } from '@/lib/partilha';
import { cores, espaco } from '@/lib/tema';

/** «Partilhar» um prato no WhatsApp; com conta, o link leva o código de convite de quem partilha */
export function BotaoPartilhar({ nome, id, convite }: { nome: string; id: string; convite: ConvitePartilha | null }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Partilhar ${nome.trim()} no WhatsApp`}
      onPress={() => void partilharPrato(nome, id, convite)}
      hitSlop={8}
      style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.xs, alignSelf: 'flex-start', paddingVertical: espaco.xs }}>
      <Ionicons name="share-social-outline" size={18} color={cores.marca} />
      <Text style={{ color: cores.marca, fontWeight: '600' }}>
        {convite ? `Partilhar · o amigo ganha desconto` : 'Partilhar'}
      </Text>
    </Pressable>
  );
}
