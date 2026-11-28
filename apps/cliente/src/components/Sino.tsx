import Ionicons from '@expo/vector-icons/Ionicons';
import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { LoginNecessario } from '@/components/LoginNecessario';
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

/**
 * Cabeçalho de quem ainda não entrou: «Entrar» bem visível (quem já é cliente sabe logo que falta
 * o login) e o mesmo sino; os dois abrem a folha de login e, depois, ficam onde estavam (ou avisos).
 */
export function SinoVisitante() {
  const [aberto, setAberto] = useState<'entrar' | 'avisos' | null>(null);
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 14, marginRight: 16 }}>
      <Pressable accessibilityRole="button" accessibilityLabel="Entrar na conta" onPress={() => setAberto('entrar')} hitSlop={8}>
        <Text style={{ color: cores.marca, fontWeight: '800', fontSize: 15 }}>Entrar</Text>
      </Pressable>
      <Pressable accessibilityRole="button" accessibilityLabel="Avisos" onPress={() => setAberto('avisos')} hitSlop={10}>
        <Ionicons name="notifications-outline" size={24} color={cores.marca} />
      </Pressable>
      <LoginNecessario
        visivel={aberto !== null}
        motivo={
          aberto === 'avisos'
            ? 'Entra para receberes os avisos dos teus pedidos.'
            : 'Para veres os teus pedidos, o teu saldo e os avisos. Se és novo, a conta cria-se aqui.'
        }
        destino={aberto === 'avisos' ? '/avisos' : '/inicio'}
        aoFechar={() => setAberto(null)}
      />
    </View>
  );
}
