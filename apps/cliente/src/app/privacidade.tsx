import { Redirect, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { ACarregar, Aviso, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { alterarPerfilDestaques, lerPerfilDestaques } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { PerfilDestaques } from '@/lib/tipos';

type Opcao = 'mostrar_nome_real' | 'ocultar_ganhos';

/** C5. Privacidade na lista de destaques */
export default function Privacidade() {
  const { carregado, ligada, perfil } = useSessao();
  const [dados, setDados] = useState<PerfilDestaques | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!perfil || !ligada('destaques')) return;
      lerPerfilDestaques(perfil.cliente_id)
        .then(setDados)
        .catch((e) => setErro(mensagemErro(e)));
    }, [perfil, ligada]),
  );

  // Aberto por link ou notificação: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('destaques')) return <Redirect href="/inicio" />;
  if (!dados && !erro) return <ACarregar />;

  async function mudar(opcao: Opcao, valor: boolean) {
    if (!perfil || !dados) return;
    const anterior = dados;
    setDados({ ...dados, [opcao]: valor });
    setErro(null);
    try {
      await alterarPerfilDestaques(perfil.cliente_id, { [opcao]: valor });
    } catch (e) {
      setDados(anterior);
      setErro(mensagemErro(e));
    }
  }

  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {dados && (
        <>
          <Cartao>
            <Paragrafo suave>Na lista apareces como</Paragrafo>
            <Text style={{ fontSize: 20, fontWeight: '700' }}>{dados.pseudonimo}</Text>
          </Cartao>
          <Cartao>
            <Interruptor
              rotulo="Mostrar o meu primeiro nome"
              valor={dados.mostrar_nome_real}
              aoMudar={(v) => mudar('mostrar_nome_real', v)}
            />
            <Interruptor rotulo="Não mostrar os meus ganhos" valor={dados.ocultar_ganhos} aoMudar={(v) => mudar('ocultar_ganhos', v)} />
          </Cartao>
          <Paragrafo suave>Nunca mostramos o teu telefone nem o teu nome completo.</Paragrafo>
        </>
      )}
    </Ecra>
  );
}

function Interruptor({ rotulo, valor, aoMudar }: { rotulo: string; valor: boolean; aoMudar: (v: boolean) => void }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 6 }}>
      <Text style={{ fontSize: 15, flex: 1 }}>{rotulo}</Text>
      <Switch value={valor} onValueChange={aoMudar} trackColor={{ true: cores.marca, false: cores.linha }} />
    </View>
  );
}
