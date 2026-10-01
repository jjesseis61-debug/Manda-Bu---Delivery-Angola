import { useRouter } from 'expo-router';
import { View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Marca } from '@/components/Marca';
import { Botao, Paragrafo } from '@/components/ui';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';

export default function SemAcesso() {
  const router = useRouter();
  const { sessao, actualizar, sair } = useSessao();
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }}>
      <View style={{ flex: 1, padding: espaco.xl, justifyContent: 'center', gap: espaco.l }}>
        <Marca grande />
        <Paragrafo>
          O número {sessao?.user.phone ? `+${sessao.user.phone}` : ''} não está associado a nenhum funcionário. Pede ao
          administrador para registar o teu telefone na tua ficha e depois tenta outra vez.
        </Paragrafo>
        <Botao
          titulo="Tentar outra vez"
          aoCarregar={async () => {
            await actualizar();
            router.replace('/');
          }}
        />
        <Botao
          titulo="Entrar com outro número"
          variante="texto"
          aoCarregar={async () => {
            await sair();
            router.replace('/entrar');
          }}
        />
      </View>
    </SafeAreaView>
  );
}
