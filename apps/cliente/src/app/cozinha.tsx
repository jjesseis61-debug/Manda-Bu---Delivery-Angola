import { Redirect, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Image } from 'react-native';

import { ACarregar, Cartao, Ecra, Linha, Paragrafo, Subtitulo, Titulo } from '@/components/ui';
import { lerCardapio, lerCozinhaPublica, mediaAvaliacoes, type Cozinha } from '@/lib/api';
import { formatarKz } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { raio } from '@/lib/tema';
import type { ItemCardapio } from '@/lib/tipos';

/** C8. Perfil da cozinha: só com o interruptor e o consentimento público da responsável */
export default function PerfilCozinha() {
  const { ligada } = useSessao();
  const [cozinha, setCozinha] = useState<Cozinha | null | undefined>(undefined);
  const [doDia, setDoDia] = useState<ItemCardapio[]>([]);
  const [media, setMedia] = useState<{ media: number; total: number } | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!ligada('perfil_cozinha')) return;
      lerCozinhaPublica()
        .then(async (c) => {
          setCozinha(c);
          if (!c) return;
          const [itens, m] = await Promise.all([lerCardapio(), mediaAvaliacoes(c.id).catch(() => null)]);
          setDoDia(itens.filter((i) => i.do_dia));
          setMedia(m);
        })
        .catch(() => setCozinha(null));
    }, [ligada]),
  );

  if (!ligada('perfil_cozinha') || cozinha === null) return <Redirect href="/inicio" />;
  if (cozinha === undefined) return <ACarregar />;

  return (
    <Ecra>
      {cozinha.foto_url && (
        <Image source={{ uri: cozinha.foto_url }} style={{ width: '100%', height: 200, borderRadius: raio }} accessibilityLabel={cozinha.nome} />
      )}
      <Titulo>{cozinha.nome}</Titulo>
      {/* A média só aparece com o mínimo de avaliações (a vista do servidor não devolve abaixo disso) */}
      {media && <Paragrafo suave>★ {media.media.toFixed(1)} · {media.total} avaliações</Paragrafo>}
      {cozinha.historia && <Paragrafo>{cozinha.historia}</Paragrafo>}
      {doDia.length > 0 && (
        <>
          <Subtitulo>Pratos do dia</Subtitulo>
          <Cartao>
            {doDia.map((i) => (
              <Linha key={i.id} esquerda={i.nome} direita={formatarKz(i.preco)} />
            ))}
          </Cartao>
        </>
      )}
    </Ecra>
  );
}
