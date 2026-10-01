import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { adicionarPalavra, comentariosModeracao, lerPalavras, ocultarAvaliacao, removerPalavra } from '@/lib/api';
import { formatarData, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { ComentarioModeracao, PalavraFiltrada } from '@/lib/tipos';

/** O7. Moderação: comentários recentes (Ocultar/Mostrar) e palavras filtradas. Fotos chegam na I7. */
export default function Moderacao() {
  const [filtro, setFiltro] = useState<'todos' | 'ocultos'>('todos');
  const [lista, setLista] = useState<ComentarioModeracao[] | null>(null);
  const [palavras, setPalavras] = useState<PalavraFiltrada[]>([]);
  const [nova, setNova] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    Promise.all([comentariosModeracao(30), lerPalavras()])
      .then(([c, p]) => {
        setLista(c);
        setPalavras(p);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  async function accao(chave: string, f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(chave);
    try {
      await f();
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  const visiveis = (lista ?? []).filter((c) => filtro === 'todos' || c.oculta);

  return (
    <Guarda permissoes={['avaliacoes.moderar']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        <Subtitulo>Comentários dos últimos 30 dias</Subtitulo>
        <Escolha
          opcoes={[
            { valor: 'todos', rotulo: 'Todos' },
            { valor: 'ocultos', rotulo: 'Ocultos' },
          ]}
          valor={filtro}
          aoMudar={setFiltro}
        />
        {!lista && !erro && <ACarregar />}
        {lista && visiveis.length === 0 && <Paragrafo suave>Sem comentários.</Paragrafo>}
        {visiveis.map((c) => (
          <Cartao key={c.avaliacao_id} estilo={c.oculta ? { opacity: 0.7 } : undefined}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ color: cores.destaque, fontSize: 16 }}>{'★'.repeat(c.estrelas)}</Text>
              <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{formatarData(c.criado_em, true)}</Text>
            </View>
            <Text style={{ fontSize: 15 }}>{c.comentario}</Text>
            <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
              {c.autor_nome} (público: {c.autor_publico}) · {c.cozinha_nome}
            </Text>
            {c.oculta && <Text style={{ color: cores.aviso, fontWeight: '700' }}>Oculto (pelo filtro ou por um moderador)</Text>}
            <Botao
              titulo={c.oculta ? 'Mostrar' : 'Ocultar'}
              variante={c.oculta ? 'secundario' : 'texto'}
              aCarregar={ocupado === c.avaliacao_id}
              aoCarregar={() => accao(c.avaliacao_id, () => ocultarAvaliacao(c.avaliacao_id, !c.oculta))}
            />
          </Cartao>
        ))}

        <Subtitulo>Palavras filtradas</Subtitulo>
        <Paragrafo suave>Um comentário novo com uma destas palavras fica oculto até um moderador o mostrar.</Paragrafo>
        <Cartao>
          {palavras.length === 0 && <Paragrafo suave>Nenhuma palavra.</Paragrafo>}
          {palavras.map((p) => (
            <View key={p.id} style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: espaco.s }}>
              <Text style={{ fontSize: 15 }}>{p.palavra}</Text>
              <Botao titulo="Remover" variante="texto" aCarregar={ocupado === p.id} aoCarregar={() => accao(p.id, () => removerPalavra(p.id))} />
            </View>
          ))}
          <Campo rotulo="Nova palavra" value={nova} onChangeText={setNova} autoCapitalize="none" />
          <Botao
            titulo="Adicionar"
            variante="secundario"
            desactivado={!nova.trim()}
            aCarregar={ocupado === 'nova'}
            aoCarregar={() =>
              accao('nova', async () => {
                await adicionarPalavra(nova);
                setNova('');
              })
            }
          />
        </Cartao>
      </Ecra>
    </Guarda>
  );
}
