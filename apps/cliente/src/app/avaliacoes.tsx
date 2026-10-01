import { Redirect, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Image, Text, View } from 'react-native';

import { ACarregar, Aviso, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { avaliacoesPublicas, mediasAvaliacoes } from '@/lib/api';
import { enderecosFotos } from '@/lib/fotos';
import { formatarData, formatarMedia, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, raio } from '@/lib/tema';
import type { AvaliacaoPublica, Media } from '@/lib/tipos';

/** C10. Avaliações da cozinha ou de um prato (só as visíveis; sem ids) */
export default function Avaliacoes() {
  const { cozinha, prato, nome } = useLocalSearchParams<{ cozinha: string; prato?: string; nome?: string }>();
  const { ligada } = useSessao();
  const [lista, setLista] = useState<AvaliacaoPublica[] | null>(null);
  const [media, setMedia] = useState<Media | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});

  useFocusEffect(
    useCallback(() => {
      if (!ligada('avaliacoes') || !cozinha) return;
      Promise.all([avaliacoesPublicas(cozinha, prato), mediasAvaliacoes(cozinha)])
        .then(([l, m]) => {
          setLista(l);
          // Fotos aprovadas: endereços temporários do bucket privado
          enderecosFotos(l.flatMap((a) => a.fotos ?? []))
            .then(setUrls)
            .catch(() => setUrls({}));
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
          {(a.fotos ?? []).some((f) => urls[f]) && (
            <View style={{ flexDirection: 'row', gap: 8 }}>
              {(a.fotos ?? []).map((f) =>
                urls[f] ? (
                  <Image
                    key={f}
                    source={{ uri: urls[f] }}
                    style={{ width: 120, height: 120, borderRadius: raio }}
                    accessibilityLabel={`Foto de ${a.autor}`}
                  />
                ) : null,
              )}
            </View>
          )}
          <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{a.autor}</Text>
        </Cartao>
      ))}
    </Ecra>
  );
}
