import { useRouter } from 'expo-router';
import { View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Marca } from '@/components/Marca';
import { Botao, Paragrafo } from '@/components/ui';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';

/** Entrou, mas não é estafeta (sem funcionário associado, ou sem a permissão entregas.registar). */
export default function SemAcesso() {
  const router = useRouter();
  const { sessao, funcionario, actualizar, sair } = useSessao();
  const mensagem = funcionario
    ? 'Esta app é só para estafetas. A tua conta não tem a função de entregas. Pede ao administrador para te dar acesso às entregas.'
    : `O número ${sessao?.user.phone ? `+${sessao.user.phone}` : ''} não está associado a nenhum funcionário. Pede ao administrador para registar o teu telefone na tua ficha e depois tenta outra vez.`;
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }}>
      <View style={{ flex: 1, padding: espaco.xl, justifyContent: 'center', gap: espaco.l }}>
        <Marca grande />
        <Paragrafo>{mensagem}</Paragrafo>
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
