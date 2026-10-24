import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Confirmar } from '@/components/Confirmar';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { apagarEndereco, lerEnderecos } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Endereco } from '@/lib/tipos';

/** C11. Endereços */
export default function Enderecos() {
  const router = useRouter();
  const { perfil } = useSessao();
  const [enderecos, setEnderecos] = useState<Endereco[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [aApagar, setAApagar] = useState<Endereco | null>(null);

  const carregar = useCallback(() => {
    lerEnderecos(perfil?.cliente_id)
      .then(setEnderecos)
      .catch((e) => setErro(mensagemErro(e)));
  }, [perfil?.cliente_id]);
  useFocusEffect(carregar);

  function apagar() {
    const e = aApagar;
    if (!e) return;
    setAApagar(null);
    setErro(null);
    apagarEndereco(e.id)
      .then(() => {
        setSucesso('Endereço apagado.');
        carregar();
      })
      .catch((err) => setErro(mensagemErro(err)));
  }

  if (erro && !enderecos) return <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra>;
  if (!enderecos) return <ACarregar />;
  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
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
            <Botao titulo="Apagar" variante="texto" aoCarregar={() => { setSucesso(null); setAApagar(e); }} />
          </View>
        </Cartao>
      ))}
      <Botao titulo="Adicionar endereço" aoCarregar={() => router.push('/enderecos/novo')} />

      <Confirmar
        visivel={aApagar !== null}
        titulo="Apagar endereço"
        mensagem={`Queres apagar "${aApagar?.nome ?? 'este endereço'}"?`}
        textoConfirmar="Apagar"
        aoConfirmar={apagar}
        aoCancelar={() => setAApagar(null)}
      />
    </Ecra>
  );
}
