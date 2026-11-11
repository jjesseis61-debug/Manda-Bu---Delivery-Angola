import Ionicons from '@expo/vector-icons/Ionicons';
import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { contarAvisosNovos } from '@/lib/api';
import { cores } from '@/lib/tema';

/** Sino no topo: abre os avisos e mostra quantos estão por ler */
export function Sino() {
  const router = useRouter();
  const [novos, setNovos] = useState(0);
  useFocusEffect(
    useCallback(() => {
      const ler = () => void contarAvisosNovos().then(setNovos).catch(() => undefined);
      ler();
      const t = setInterval(ler, 60_000);
      return () => clearInterval(t);
    }, []),
  );
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={novos > 0 ? `Avisos, ${novos} por ler` : 'Avisos'}
      onPress={() => router.push('/avisos')}
      hitSlop={10}
      style={{ marginRight: 16 }}>
      <Ionicons name={novos > 0 ? 'notifications' : 'notifications-outline'} size={24} color={cores.marca} />
      {novos > 0 && (
        <View
          style={{
            position: 'absolute', top: -4, right: -8, minWidth: 18, height: 18, borderRadius: 9,
            backgroundColor: cores.marca, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 4,
          }}>
          <Text style={{ color: '#fff', fontSize: 11, fontWeight: '700' }}>{novos > 9 ? '9+' : novos}</Text>
        </View>
      )}
    </Pressable>
  );
}
