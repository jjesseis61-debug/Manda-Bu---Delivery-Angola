import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { lerConversaAtendimento, lerConversasAtendimento, mudarConversaAtendimento, responderAtendimento } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco, raio } from '@/lib/tema';
import type { ConversaDetalhe, ConversaResumo } from '@/lib/tipos';

const nomeEstado: Record<ConversaResumo['estado'], string> = {
  humano: 'À espera de uma pessoa',
  agente: 'Com o assistente',
  fechada: 'Terminada',
};
const nomeAutor = { cliente: 'Cliente', agente: 'Assistente', sistema: 'Sistema' } as const;

/**
 * Atendimento: as conversas dos clientes com o assistente. As que ele passou para uma pessoa aparecem primeiro;
 * quem atende responde (o cliente recebe uma notificação), devolve ao assistente ou termina a conversa.
 */
export default function Atendimento() {
  const [lista, setLista] = useState<ConversaResumo[] | null>(null);
  const [aberta, setAberta] = useState<ConversaDetalhe | null>(null);
  const [resposta, setResposta] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    lerConversasAtendimento().then(setLista, (e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  async function abrir(id: string) {
    setErro(null);
    try {
      setAberta(await lerConversaAtendimento(id));
      setResposta('');
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  async function correr(accao: () => Promise<unknown>, fechar = false) {
    if (!aberta) return;
    setErro(null);
    setOcupado(true);
    try {
      await accao();
      setResposta('');
      if (fechar) setAberta(null);
      else setAberta(await lerConversaAtendimento(aberta.id));
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  if (aberta) {
    const terminada = aberta.estado === 'fechada';
    return (
      <Guarda permissoes={['atendimento.responder']}>
        <Ecra>
          <Botao titulo="‹ Voltar às conversas" variante="texto" aoCarregar={() => setAberta(null)} />
          <Subtitulo>{aberta.cliente}</Subtitulo>
          <Paragrafo suave>
            {nomeEstado[aberta.estado]}
            {aberta.motivo ? ` · ${aberta.motivo}` : ''}
            {aberta.telefone ? ` · ${aberta.telefone}` : ''}
          </Paragrafo>
          {aberta.mensagens.map((m) => {
            const doCliente = m.autor === 'cliente';
            return (
              <View
                key={m.id}
                style={{
                  alignSelf: doCliente ? 'flex-start' : 'flex-end',
                  maxWidth: '85%',
                  backgroundColor: doCliente ? cores.fundoSuave : cores.marcaClara,
                  borderRadius: raio,
                  padding: espaco.m,
                  gap: espaco.xs,
                }}
              >
                <Text style={{ color: cores.textoSuave, fontSize: 12 }}>
                  {m.autor === 'funcionario' ? (m.quem ?? 'Equipa') : nomeAutor[m.autor]}
                </Text>
                <Text>{m.texto}</Text>
              </View>
            );
          })}
          {erro && <Aviso tipo="erro">{erro}</Aviso>}
          {!terminada && (
            <>
              <Campo rotulo="Resposta ao cliente" value={resposta} onChangeText={setResposta} maxLength={1500} multiline />
              <Botao
                titulo="Responder"
                aCarregar={ocupado}
                desactivado={resposta.trim().length === 0}
                aoCarregar={() => correr(() => responderAtendimento(aberta.id, resposta.trim()))}
              />
              {aberta.estado === 'humano' && (
                <Botao titulo="Devolver ao assistente" variante="secundario" aoCarregar={() => correr(() => mudarConversaAtendimento(aberta.id, 'agente'))} />
              )}
              <Botao titulo="Terminar a conversa" variante="texto" aoCarregar={() => correr(() => mudarConversaAtendimento(aberta.id, 'fechada'), true)} />
            </>
          )}
          {aberta.pedidos.length > 0 && <Subtitulo>Últimos pedidos</Subtitulo>}
          {aberta.pedidos.map((p) => (
            <Text key={p.pedido_id} style={{ color: cores.textoSuave }}>
              {p.feito_em} · {p.estado} · {p.itens ?? ''} · {formatarKz(p.total_kz)}
            </Text>
          ))}
        </Ecra>
      </Guarda>
    );
  }

  return (
    <Guarda permissoes={['atendimento.responder']}>
      <Ecra>
        <Paragrafo suave>
          O assistente responde aos clientes na app. Quando é preciso uma decisão (reclamação, reembolso, alergias) ou o
          cliente pede, a conversa passa para aqui.
        </Paragrafo>
        <Botao titulo="Actualizar" variante="texto" aoCarregar={carregar} />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {lista === null ? (
          <ACarregar />
        ) : lista.length === 0 ? (
          <Aviso tipo="sucesso">Sem conversas.</Aviso>
        ) : (
          lista.map((c) => (
            <Pressable key={c.id} accessibilityRole="button" onPress={() => abrir(c.id)}>
              <Cartao>
                <Text style={{ fontWeight: '700', color: c.estado === 'humano' ? cores.erro : cores.texto }}>
                  {c.cliente} · {nomeEstado[c.estado]}
                </Text>
                {c.motivo && c.estado === 'humano' && <Text style={{ color: cores.textoSuave }}>{c.motivo}</Text>}
                <Text numberOfLines={2}>{c.ultima_mensagem ?? ''}</Text>
                {c.atendido_por && <Text style={{ color: cores.textoSuave }}>A atender: {c.atendido_por}</Text>}
              </Cartao>
            </Pressable>
          ))
        )}
      </Ecra>
    </Guarda>
  );
}
