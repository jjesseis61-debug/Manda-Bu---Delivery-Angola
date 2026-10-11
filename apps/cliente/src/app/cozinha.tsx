import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Image } from 'react-native';

import { BlocoContactos, temContacto } from '@/components/BlocoContactos';
import { ComoChegar } from '@/components/ComoChegar';
import { ACarregar, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo, Titulo } from '@/components/ui';
import { lerCardapio, lerContactos, lerCozinhaPublica, mediasAvaliacoes, type Cozinha } from '@/lib/api';
import { formatarKz, formatarMedia } from '@/lib/formatar';
import { useCarrinho } from '@/lib/carrinho';
import { useSessao } from '@/lib/sessao';
import { raio } from '@/lib/tema';
import type { Contacto, ItemCardapio } from '@/lib/tipos';

/** C8. Perfil da cozinha: só com o interruptor e o consentimento público da responsável */
export default function PerfilCozinha() {
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const carrinho = useCarrinho();
  const cozinhaId = carrinho.cozinhaActual?.id ?? null;
  const [cozinha, setCozinha] = useState<Cozinha | null | undefined>(undefined);
  const [doDia, setDoDia] = useState<ItemCardapio[]>([]);
  const [media, setMedia] = useState<{ media: number; total: number } | null>(null);
  const [contacto, setContacto] = useState<Contacto | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!ligada('perfil_cozinha')) return;
      lerCozinhaPublica(cozinhaId)
        .then(async (c) => {
          setCozinha(c);
          if (!c) return;
          const [itens, m, cs] = await Promise.all([
            lerCardapio(c.id),
            ligada('avaliacoes') ? mediasAvaliacoes(c.id).catch(() => null) : Promise.resolve(null),
            lerContactos().catch(() => null),
          ]);
          setDoDia(itens.filter((i) => i.do_dia));
          setMedia(m?.cozinha ?? null);
          setContacto(cs?.cozinhas.find((x) => x.id === c.id) ?? null);
        })
        .catch(() => setCozinha(null));
    }, [ligada, cozinhaId]),
  );

  // Aberto por link ou notificação: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('perfil_cozinha') || cozinha === null) return <Redirect href="/inicio" />;
  if (cozinha === undefined) return <ACarregar />;

  return (
    <Ecra>
      {cozinha.foto_url && (
        <Image source={{ uri: cozinha.foto_url }} style={{ width: '100%', height: 200, borderRadius: raio }} accessibilityLabel={cozinha.nome} />
      )}
      <Titulo>{cozinha.nome}</Titulo>
      {/* A média só aparece com o mínimo de avaliações (o servidor não a devolve abaixo disso) */}
      {media && <Paragrafo suave>{formatarMedia(media.media, media.total)}</Paragrafo>}
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
      {temContacto(contacto) && <BlocoContactos titulo="Contactos da cozinha" contacto={contacto} />}
      {ligada('como_chegar') && <ComoChegar cozinhaId={cozinha.id} comMapa />}
      {ligada('avaliacoes') && (
        <Botao
          titulo="Ver avaliações"
          variante="secundario"
          aoCarregar={() => router.push({ pathname: '/avaliacoes', params: { cozinha: cozinha.id, nome: cozinha.nome } })}
        />
      )}
    </Ecra>
  );
}
