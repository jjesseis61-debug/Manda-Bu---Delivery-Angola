import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { lerEnderecos } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores } from '@/lib/tema';
import type { Endereco } from '@/lib/tipos';

/** C11. Endereços */
export default function Enderecos() {
  const router = useRouter();
  const [enderecos, setEnderecos] = useState<Endereco[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      lerEnderecos()
        .then(setEnderecos)
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

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
        </Cartao>
      ))}
      <Botao titulo="Adicionar endereço" aoCarregar={() => router.push('/enderecos/novo')} />
    </Ecra>
  );
}
