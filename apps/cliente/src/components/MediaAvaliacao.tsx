import Ionicons from '@expo/vector-icons/Ionicons';
import { Text, View } from 'react-native';

import { formatarMedia } from '@/lib/formatar';
import { cores } from '@/lib/tema';

/**
 * Média de avaliações com a estrela dourada da marca (ícone vectorial, não o caráter ★).
 * Dourado = qualidade (cores.destaque); o texto fica na cor normal ou suave.
 */
export function MediaAvaliacao({ media, total, suave = false }: { media: number; total: number; suave?: boolean }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5 }}>
      <Ionicons name="star" size={15} color={cores.destaque} />
      <Text style={{ color: suave ? cores.textoSuave : cores.texto, fontWeight: '600' }}>{formatarMedia(media, total)}</Text>
    </View>
  );
}
