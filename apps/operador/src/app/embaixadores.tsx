import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { definirNivel, embaixadores } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores } from '@/lib/tema';
import type { Embaixador } from '@/lib/tipos';

/** O4. Embaixadores: elegíveis e actuais; promover ou remover */
export default function Embaixadores() {
  const [lista, setLista] = useState<Embaixador[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    embaixadores()
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  async function mudar(e: Embaixador) {
    setErro(null);
    setOcupado(e.cliente_id);
    try {
      await definirNivel(e.cliente_id, e.nivel === 'embaixador' ? 'normal' : 'embaixador');
      carregar();
    } catch (x) {
      setErro(mensagemErro(x));
    } finally {
      setOcupado(null);
    }
  }

  return (
    <Guarda permissoes={['plataforma.parametros']}>
      <Ecra>
        <Paragrafo suave>
          Elegíveis: indicadores com indicados activos acima do limiar. Ao promover, combine o contacto pessoal por telefone.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Paragrafo suave>Ainda não há embaixadores nem elegíveis.</Paragrafo>}
        {lista?.map((e) => (
          <Cartao key={e.cliente_id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontWeight: '700', fontSize: 16 }}>
                {e.nome}
                {e.nivel === 'embaixador' ? ' ★' : ''}
              </Text>
              <Text style={{ color: e.nivel === 'embaixador' ? cores.marca : cores.aviso, fontWeight: '700' }}>
                {e.nivel === 'embaixador' ? 'Embaixador' : 'Elegível'}
              </Text>
            </View>
            <Text>
              {e.indicados_activos} indicados activos · {formatarKz(e.ganho_mes)} este mês
            </Text>
            {e.telefone && (
              <Text style={{ color: cores.marca }} onPress={() => Linking.openURL(`tel:+244${e.telefone}`)}>
                Ligar {e.telefone}
              </Text>
            )}
            <Botao
              titulo={e.nivel === 'embaixador' ? 'Remover de Embaixador' : 'Promover a Embaixador'}
              variante={e.nivel === 'embaixador' ? 'secundario' : 'principal'}
              aCarregar={ocupado === e.cliente_id}
              aoCarregar={() => mudar(e)}
            />
          </Cartao>
        ))}
      </Ecra>
    </Guarda>
  );
}
