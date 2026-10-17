import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { apagarEndereco, lerEnderecos } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Endereco } from '@/lib/tipos';

/** C11. Endereços */
export default function Enderecos() {
  const router = useRouter();
  const [enderecos, setEnderecos] = useState<Endereco[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    lerEnderecos()
      .then(setEnderecos)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  function confirmarApagar(e: Endereco) {
    Alert.alert('Apagar endereço', `Queres apagar "${e.nome ?? 'este endereço'}"?`, [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Apagar',
        style: 'destructive',
        onPress: () =>
          apagarEndereco(e.id)
            .then(carregar)
            .catch((err) => setErro(mensagemErro(err))),
      },
    ]);
  }

  if (erro) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!enderecos) return <ACarregar />;
  return (
    <Ecra>
      {enderecos.length === 0 && <Paragrafo suave>Ainda não tens endereços.</Paragrafo>}
      {enderecos.map((e) => (
        <Cartao key={e.id}>
          <Text style={{ fontWeight: '700', fontSize: 15 }}>
            {e.nome ?? 'Endereço'}
            {e.principal ? ' · principal' : ''}
          </Text>
          <Text style={{ color: cores.textoSuave }}>
            {e.pontos_entrega?.tipo === 'empresa' ? 'Trabalho' : 'Casa'}
            {e.pontos_entrega?.zonas?.nome ? ` · ${e.pontos_entrega.zonas.nome}` : ''}
          </Text>
          {e.pontos_entrega?.referencia ? <Text>{e.pontos_entrega.referencia}</Text> : null}
          <View style={{ flexDirection: 'row', justifyContent: 'flex-end', marginTop: espaco.xs }}>
            <Botao titulo="Apagar" variante="texto" aoCarregar={() => confirmarApagar(e)} />
          </View>
        </Cartao>
      ))}
      <Botao titulo="Adicionar endereço" aoCarregar={() => router.push('/enderecos/novo')} />
    </Ecra>
  );
}
