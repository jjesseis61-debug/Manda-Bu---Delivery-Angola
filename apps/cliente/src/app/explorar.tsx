import { Redirect, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Image, Pressable, Text, View } from 'react-native';

import { FaixaConfianca } from '@/components/FaixaConfianca';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import {
  guardarZonaVisitante,
  lerCozinhasVisitante,
  lerZonasVisitante,
  COZINHAS_A_MOSTRAR,
  ordenarCozinhasVisitante,
  rotuloZona,
  type CozinhaVisitante,
  type ZonaVisitante,
} from '@/lib/visitante';

/** Bairro escolhido: uma zona, ou «outro bairro» (todas as cozinhas) */
type Escolha = { zona: ZonaVisitante | null };

/**
 * «Ver o cardápio primeiro» (página de entrada): o visitante escolhe o bairro e vê as cozinhas
 * que lhe servem, da mais perto para a mais longe. Com uma só cozinha, abre logo o cardápio.
 * O número só é pedido em «Pedir» (ecrã visita/[cozinha]).
 */
export default function Explorar() {
  const router = useRouter();
  const { carregado, sessao, perfil } = useSessao();
  const [zonas, setZonas] = useState<ZonaVisitante[] | null>(null);
  const [escolha, setEscolha] = useState<Escolha | null>(null);
  const [cozinhas, setCozinhas] = useState<CozinhaVisitante[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [verTodas, setVerTodas] = useState(false);

  useEffect(() => {
    lerZonasVisitante()
      .then(setZonas)
      .catch((e) => {
        setErro(mensagemErro(e));
        setZonas([]);
      });
  }, []);

  useEffect(() => {
    if (!escolha) return;
    // O cardápio e o carrinho mostram a entrega deste bairro
    void guardarZonaVisitante(escolha.zona);
    let vivo = true;
    setCozinhas(null);
    lerCozinhasVisitante(escolha.zona?.id ?? null)
      .then((lista) => {
        if (!vivo) return;
        // Uma só cozinha: não há nada para escolher, abre logo o cardápio
        if (lista.length === 1) router.replace({ pathname: '/visita/[cozinha]', params: { cozinha: lista[0].id } });
        else {
          setVerTodas(false);
          setCozinhas(ordenarCozinhasVisitante(lista));
        }
      })
      .catch((e) => {
        if (!vivo) return;
        setErro(mensagemErro(e));
        setCozinhas([]);
      });
    return () => {
      vivo = false;
    };
  }, [escolha, router]);

  if (!carregado) return <ACarregar />;
  if (sessao && perfil) return <Redirect href="/inicio" />;
  if (zonas === null) return <ACarregar />;

  if (!escolha) {
    return (
      <Ecra>
        <Subtitulo>Onde queres receber a comida?</Subtitulo>
        <Paragrafo suave>Escolhe o teu bairro para veres as cozinhas que te podem servir.</Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {zonas.map((z) => (
          <Botao key={z.id} titulo={rotuloZona(z, formatarKz)} variante="leve" aoCarregar={() => setEscolha({ zona: z })} />
        ))}
        <Botao titulo="O meu bairro não está na lista" variante="texto" aoCarregar={() => setEscolha({ zona: null })} />
        <FaixaConfianca />
      </Ecra>
    );
  }

  if (cozinhas === null) return <ACarregar />;

  return (
    <Ecra>
      <Subtitulo>{escolha.zona ? `Cozinhas para ${escolha.zona.nome}` : 'Cozinhas da Manda Bué'}</Subtitulo>
      {escolha.zona ? (
        <Paragrafo suave>
          {escolha.zona.taxa > 0 ? `Entrega para ${escolha.zona.nome}: ${formatarKz(escolha.zona.taxa)}` : `Entrega grátis para ${escolha.zona.nome}`}
          {escolha.zona.taxa > 0 && escolha.zona.entrega_gratis_acima ? ` · grátis a partir de ${formatarKz(escolha.zona.entrega_gratis_acima)}` : ''}.
        </Paragrafo>
      ) : (
        <Paragrafo suave>Ao pedir, confirmamos se entregamos na tua morada e quanto custa a entrega.</Paragrafo>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {cozinhas.length === 0 && <Aviso>Agora não há cozinhas abertas. Volta um pouco mais tarde.</Aviso>}
      {(verTodas ? cozinhas : cozinhas.slice(0, COZINHAS_A_MOSTRAR)).map((c) => (
        <Pressable
          key={c.id}
          accessibilityRole="button"
          accessibilityLabel={`Ver o cardápio de ${c.nome}`}
          onPress={() => router.push({ pathname: '/visita/[cozinha]', params: { cozinha: c.id } })}>
          <Cartao estilo={{ flexDirection: 'row', gap: espaco.m, alignItems: 'center' }}>
            {c.foto_url ? (
              <Image source={{ uri: c.foto_url }} style={{ width: 56, height: 56, borderRadius: raio }} accessibilityIgnoresInvertColors />
            ) : (
              <View
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
                style={{ width: 56, height: 56, borderRadius: raio, backgroundColor: cores.marcaClara, alignItems: 'center', justifyContent: 'center' }}>
                <Text style={{ fontSize: 26 }}>🍲</Text>
              </View>
            )}
            <View style={{ flex: 1, gap: 2 }}>
              <Text style={{ fontSize: 16, fontWeight: '700', color: cores.texto }}>{c.nome}</Text>
              <Text style={{ color: cores.textoSuave }}>
                {c.pratos} {c.pratos === 1 ? 'prato' : 'pratos'}
                {c.distancia_km !== null ? ` · a ${String(c.distancia_km).replace('.', ',')} km` : ''}
              </Text>
            </View>
            <Text style={{ color: cores.marca, fontWeight: '800' }}>Ver ›</Text>
          </Cartao>
        </Pressable>
      ))}
      {!verTodas && cozinhas.length > COZINHAS_A_MOSTRAR && (
        <Botao
          titulo={`Ver mais cozinhas (${cozinhas.length - COZINHAS_A_MOSTRAR})`}
          variante="secundario"
          aoCarregar={() => setVerTodas(true)}
        />
      )}
      <Botao titulo="Mudar de bairro" variante="texto" aoCarregar={() => setEscolha(null)} />
    </Ecra>
  );
}
