import { Redirect, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Ecra, Paragrafo } from '@/components/ui';
import { enviarMensagemAtendimento, minhaConversaAtendimento, pedirPessoaAtendimento } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { ConversaAtendimento, MensagemAtendimento } from '@/lib/tipos';

const ESPERA_ASSISTENTE_MS = 3000;
const ESPERA_PESSOA_MS = 15000;

/**
 * Ajuda: conversa com o assistente da Manda Bué, que conhece os teus pedidos e a tua conta. Quando é preciso uma
 * decisão (reclamação, reembolso, alergias) ou se pedires, a conversa passa para uma pessoa da equipa.
 */
export default function Ajuda() {
  const { carregado, ligada } = useSessao();
  const [conversa, setConversa] = useState<ConversaAtendimento | null | undefined>(undefined);
  const [texto, setTexto] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);

  const ligado = carregado && ligada('agente_atendimento');
  const carregar = useCallback(() => {
    if (!ligado) return;
    minhaConversaAtendimento().then(setConversa, (e) => setErro(mensagemErro(e)));
  }, [ligado]);
  useFocusEffect(carregar);

  // Enquanto o assistente escreve, ou com uma pessoa, vai buscando as respostas novas
  const aberta = conversa && conversa.estado !== 'fechada';
  const espera = conversa?.a_escrever ? ESPERA_ASSISTENTE_MS : conversa?.estado === 'humano' ? ESPERA_PESSOA_MS : null;
  useEffect(() => {
    if (!espera) return;
    const t = setTimeout(carregar, espera);
    return () => clearTimeout(t);
  }, [espera, conversa, carregar]);

  if (!carregado) return <ACarregar />;
  if (!ligada('agente_atendimento')) return <Redirect href="/inicio" />;

  async function enviar() {
    setErro(null);
    setAEnviar(true);
    try {
      await enviarMensagemAtendimento(texto.trim());
      setTexto('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  async function pedirPessoa() {
    setErro(null);
    try {
      await pedirPessoaAtendimento();
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  function balao(m: MensagemAtendimento) {
    const meu = m.autor === 'cliente';
    if (m.autor === 'sistema') {
      return (
        <Text key={m.id} style={{ color: cores.textoSuave, textAlign: 'center', fontStyle: 'italic' }}>
          {m.texto}
        </Text>
      );
    }
    return (
      <View
        key={m.id}
        style={{
          alignSelf: meu ? 'flex-end' : 'flex-start',
          maxWidth: '85%',
          backgroundColor: meu ? cores.marcaClara : cores.fundoSuave,
          borderRadius: raio,
          padding: espaco.m,
          gap: espaco.xs,
        }}
      >
        {!meu && (
          <Text style={{ color: cores.textoSuave, fontSize: 12 }}>
            {m.autor === 'funcionario' ? `${m.quem ?? 'Equipa'} · equipa Manda Bué` : 'Assistente Manda Bué'}
          </Text>
        )}
        <Text style={{ color: cores.texto }}>{m.texto}</Text>
      </View>
    );
  }

  return (
    <Ecra>
      <Paragrafo suave>
        O assistente conhece os teus pedidos e a tua conta e responde logo. Se precisares de uma decisão, passa a conversa a
        uma pessoa da equipa.
      </Paragrafo>
      {conversa === undefined ? (
        <ACarregar />
      ) : (
        <View style={{ gap: espaco.s }}>
          {(conversa?.mensagens ?? []).map(balao)}
          {conversa?.a_escrever && <Text style={{ color: cores.textoSuave }}>O assistente está a escrever…</Text>}
          {conversa?.estado === 'humano' && <Aviso>Um colega da equipa responde aqui assim que puder.</Aviso>}
        </View>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Campo rotulo="A tua mensagem" value={texto} onChangeText={setTexto} maxLength={1000} multiline />
      <Botao titulo="Enviar" aCarregar={aEnviar} desactivado={texto.trim().length === 0} aoCarregar={enviar} />
      {aberta && conversa?.estado === 'agente' && (
        <Botao titulo="Falar com uma pessoa" variante="texto" aoCarregar={pedirPessoa} />
      )}
    </Ecra>
  );
}
