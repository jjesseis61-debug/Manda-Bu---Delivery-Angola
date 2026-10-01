import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';

import { Aviso, Botao, Cartao, Paragrafo, Subtitulo, estilos } from '@/components/ui';
import { contadorZona, lerCardapio, lerCozinhaPublica, lerEnderecos, mediasAvaliacoes, type Cozinha } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, formatarMedia, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { Endereco, ItemCardapio, MediasAvaliacoes } from '@/lib/tipos';

export default function Inicio() {
  const router = useRouter();
  const { ligada } = useSessao();
  const carrinho = useCarrinho();
  const [cardapio, setCardapio] = useState<ItemCardapio[] | null>(null);
  const [enderecos, setEnderecos] = useState<Endereco[]>([]);
  const [contador, setContador] = useState<number | null>(null);
  const [cozinha, setCozinha] = useState<Cozinha | null>(null);
  const [medias, setMedias] = useState<MediasAvaliacoes | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aActualizar, setAActualizar] = useState(false);

  const carregar = useCallback(async () => {
    setErro(null);
    try {
      const [itens, ends] = await Promise.all([lerCardapio(), lerEnderecos()]);
      setCardapio(itens);
      setEnderecos(ends);
      // C7: contador do bairro do endereço principal (o servidor devolve null abaixo do mínimo)
      const zona = ends[0]?.pontos_entrega?.zona_id;
      setContador(ligada('contadores_zona') && zona ? await contadorZona(zona) : null);
      // C8: só com o interruptor e o consentimento público da cozinha
      setCozinha(ligada('perfil_cozinha') ? await lerCozinhaPublica() : null);
      // C10: média de cada prato (só com o mínimo de avaliações)
      setMedias(ligada('avaliacoes') && itens[0] ? await mediasAvaliacoes(itens[0].cozinha_id).catch(() => null) : null);
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }, [ligada]);

  useFocusEffect(
    useCallback(() => {
      void carregar();
    }, [carregar]),
  );

  const doDia = useMemo(() => (cardapio ?? []).filter((i) => i.do_dia), [cardapio]);
  const categorias = useMemo(() => {
    const grupos = new Map<string, ItemCardapio[]>();
    for (const item of cardapio ?? []) {
      const chave = item.do_dia ? 'Prato do dia' : item.categoria || 'Cardápio';
      grupos.set(chave, [...(grupos.get(chave) ?? []), item]);
    }
    return [...grupos.entries()];
  }, [cardapio]);

  return (
    <View style={{ flex: 1, backgroundColor: cores.fundo }}>
      <ScrollView
        contentContainerStyle={[estilos.conteudo, { paddingBottom: 120 }]}
        refreshControl={
          <RefreshControl
            refreshing={aActualizar}
            onRefresh={async () => {
              setAActualizar(true);
              await carregar();
              setAActualizar(false);
            }}
          />
        }>
        {contador !== null && (
          <Cartao>
            <Text style={{ fontSize: 16, fontWeight: '600' }}>{contador} pedidos no teu bairro hoje</Text>
          </Cartao>
        )}
        {cozinha && doDia.length > 0 && (
          <Pressable onPress={() => router.push('/cozinha')}>
            <Cartao>
              <Text style={{ fontSize: 15 }}>
                Hoje na {cozinha.nome}: <Text style={{ fontWeight: '700' }}>{doDia.map((i) => i.nome).join(', ')}</Text>
              </Text>
            </Cartao>
          </Pressable>
        )}
        {enderecos.length === 0 && cardapio !== null && (
          <Aviso>
            Antes do primeiro pedido, adiciona o endereço de entrega.{' '}
            <Text style={{ fontWeight: '700' }} onPress={() => router.push('/enderecos/novo')}>
              Adicionar endereço
            </Text>
          </Aviso>
        )}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {cardapio !== null && cardapio.length === 0 && <Paragrafo suave>O cardápio de hoje ainda não está disponível.</Paragrafo>}
        {categorias.map(([categoria, itens]) => (
          <View key={categoria} style={{ gap: espaco.s }}>
            <Subtitulo>{categoria}</Subtitulo>
            {itens.map((item) => {
              const noCarrinho = carrinho.linhas.find((l) => l.item.id === item.id)?.qtd ?? 0;
              return (
                <View key={item.id} style={{ backgroundColor: cores.fundoSuave, borderRadius: raio, padding: espaco.m, gap: 4 }}>
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.m }}>
                    <Text style={{ fontSize: 16, fontWeight: '600', flex: 1 }}>{item.nome}</Text>
                    <Text style={{ fontSize: 16, fontWeight: '700' }}>{formatarKz(item.preco)}</Text>
                  </View>
                  {item.descricao ? <Text style={{ color: cores.textoSuave }}>{item.descricao}</Text> : null}
                  {(() => {
                    const m = item.prato_base_id ? medias?.pratos.find((p) => p.prato_base_id === item.prato_base_id) : undefined;
                    return m ? (
                      <Pressable
                        accessibilityRole="link"
                        onPress={() =>
                          router.push({
                            pathname: '/avaliacoes',
                            params: { cozinha: item.cozinha_id, prato: item.prato_base_id ?? '', nome: item.nome },
                          })
                        }>
                        <Text style={{ color: cores.marca, fontWeight: '600' }}>{formatarMedia(m.media, m.total)}</Text>
                      </Pressable>
                    ) : null;
                  })()}
                  <View style={{ flexDirection: 'row', justifyContent: 'flex-end', alignItems: 'center', gap: espaco.m }}>
                    {noCarrinho > 0 && <Text style={{ color: cores.marca, fontWeight: '600' }}>{noCarrinho} no carrinho</Text>}
                    <Pressable
                      accessibilityRole="button"
                      onPress={() => carrinho.adicionar(item)}
                      style={{ backgroundColor: cores.marca, borderRadius: 20, paddingHorizontal: espaco.l, paddingVertical: 6 }}>
                      <Text style={{ color: '#fff', fontWeight: '700' }}>Adicionar</Text>
                    </Pressable>
                  </View>
                </View>
              );
            })}
          </View>
        ))}
      </ScrollView>
      {carrinho.quantidade > 0 && (
        <View style={{ position: 'absolute', left: espaco.l, right: espaco.l, bottom: espaco.l }}>
          <Botao
            titulo={`Ver pedido (${carrinho.quantidade}) · ${formatarKz(carrinho.totalEstimado)}`}
            aoCarregar={() => router.push('/carrinho')}
          />
        </View>
      )}
    </View>
  );
}
