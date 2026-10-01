import { Redirect, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { ACarregar, Aviso, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { avaliacoesPublicas, mediasAvaliacoes } from '@/lib/api';
import { formatarData, formatarMedia, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { AvaliacaoPublica, Media } from '@/lib/tipos';

/** C10. Avaliações da cozinha ou de um prato (só as visíveis; sem ids) */
export default function Avaliacoes() {
  const { cozinha, prato, nome } = useLocalSearchParams<{ cozinha: string; prato?: string; nome?: string }>();
  const { ligada } = useSessao();
  const [lista, setLista] = useState<AvaliacaoPublica[] | null>(null);
  const [media, setMedia] = useState<Media | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!ligada('avaliacoes') || !cozinha) return;
      Promise.all([avaliacoesPublicas(cozinha, prato), mediasAvaliacoes(cozinha)])
        .then(([l, m]) => {
          setLista(l);
          setMedia(prato ? (m?.pratos.find((p) => p.prato_base_id === prato) ?? null) : (m?.cozinha ?? null));
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, [ligada, cozinha, prato]),
  );

  if (!ligada('avaliacoes')) return <Redirect href="/inicio" />;
  if (!lista && !erro) return <ACarregar />;

  return (
    <Ecra>
      {nome && <Subtitulo>{nome}</Subtitulo>}
      {media && <Paragrafo>{formatarMedia(media.media, media.total)}</Paragrafo>}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {lista && lista.length === 0 && <Paragrafo suave>Ainda não há avaliações.</Paragrafo>}
      {lista?.map((a, i) => (
        <Cartao key={`${a.criado_em}-${i}`}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
            <Text style={{ color: cores.destaque, fontSize: 16 }}>{'★'.repeat(a.estrelas)}<Text style={{ color: cores.linha }}>{'★'.repeat(5 - a.estrelas)}</Text></Text>
            <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{formatarData(a.criado_em)}</Text>
          </View>
          {a.comentario && <Text style={{ fontSize: 15 }}>{a.comentario}</Text>}
          {a.pratos.length > 0 && (
            <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{a.pratos.map((p) => `${p.nome} ${p.estrelas}★`).join(' · ')}</Text>
          )}
          <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{a.autor}</Text>
        </Cartao>
      ))}
    </Ecra>
  );
}
