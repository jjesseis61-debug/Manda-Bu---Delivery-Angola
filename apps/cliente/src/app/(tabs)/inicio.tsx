import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useMemo, useRef, useState } from 'react';
import { Image, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';

import { ComoChegar } from '@/components/ComoChegar';
import { Aviso, Botao, Cartao, Escolha, Paragrafo, Subtitulo, estilos } from '@/components/ui';
import {
  contadorZona,
  cozinhaPadrao,
  cozinhasParaPedir,
  lerCardapio,
  lerCozinhaPublica,
  lerEnderecos,
  lerOpcoes,
  mediasAvaliacoes,
  type Cozinha,
} from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, formatarMedia, mensagemErro } from '@/lib/formatar';
import { gruposEsgotados } from '@/lib/opcoes';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { CozinhaParaPedir, Endereco, ItemCardapio, MediasAvaliacoes } from '@/lib/tipos';

export default function Inicio() {
  const router = useRouter();
  const { ligada } = useSessao();
  const carrinho = useCarrinho();
  const [cardapio, setCardapio] = useState<ItemCardapio[] | null>(null);
  const [enderecos, setEnderecos] = useState<Endereco[]>([]);
  const [contador, setContador] = useState<number | null>(null);
  const [cozinha, setCozinha] = useState<Cozinha | null>(null);
  const [medias, setMedias] = useState<MediasAvaliacoes | null>(null);
  const [cozinhas, setCozinhas] = useState<CozinhaParaPedir[]>([]);
  // I9: pratos com opções (abrem o ecrã de montar em vez de irem direito ao carrinho)
  const [montaveis, setMontaveis] = useState<Set<string>>(new Set());
  const [esgotados, setEsgotados] = useState<Set<string>>(new Set());
  const cozinhaId = carrinho.cozinhaActual?.id ?? null;
  // Referência ao carrinho para o carregamento não depender de cada prato adicionado
  const carrinhoRef = useRef(carrinho);
  carrinhoRef.current = carrinho;
  const emGrupo = carrinho.grupo !== null;
  const [erro, setErro] = useState<string | null>(null);
  const [aActualizar, setAActualizar] = useState(false);

  const carregar = useCallback(async () => {
    setErro(null);
    try {
      // I8: com multi_cozinha, o cliente escolhe a cozinha; por defeito a primeira da lista
      let escolhida = cozinhaId;
      if (ligada('multi_cozinha')) {
        const lista = await cozinhasParaPedir();
        setCozinhas(lista);
        if (!emGrupo && (!escolhida || !lista.some((c) => c.cozinha_id === escolhida)) && lista[0]) {
          escolhida = lista[0].cozinha_id;
          carrinhoRef.current.definirCozinha({ id: lista[0].cozinha_id, nome: lista[0].nome });
        }
      } else {
        setCozinhas([]);
        // Sem multi_cozinha o servidor manda todos os pedidos para a cozinha padrão: só os pratos dela
        escolhida = await cozinhaPadrao();
      }
      const [itens, ends] = await Promise.all([lerCardapio(escolhida), lerEnderecos()]);
      setCardapio(itens);
      setEnderecos(ends);
      // I9: pratos com opções abrem o ecrã de montar; um grupo obrigatório sem opções disponíveis esgota o prato
      const grupos = ligada('pratos_montaveis') ? await lerOpcoes(itens.map((i) => i.id)) : [];
      setMontaveis(new Set(grupos.filter((g) => g.opcoes.length > 0).map((g) => g.cardapio_id)));
      setEsgotados(new Set(grupos.filter((g) => gruposEsgotados([g]).length > 0).map((g) => g.cardapio_id)));
      // C7: contador do bairro do endereço principal (o servidor devolve null abaixo do mínimo)
      const zona = ends[0]?.pontos_entrega?.zona_id;
      setContador(ligada('contadores_zona') && zona ? await contadorZona(zona) : null);
      // C8: só com o interruptor e o consentimento público da cozinha
      setCozinha(ligada('perfil_cozinha') ? await lerCozinhaPublica(ligada('multi_cozinha') ? escolhida : null) : null);
      // C10: média de cada prato (só com o mínimo de avaliações)
      setMedias(ligada('avaliacoes') && itens[0] ? await mediasAvaliacoes(itens[0].cozinha_id).catch(() => null) : null);
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }, [ligada, cozinhaId, emGrupo]);

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
        {/* I8: selector de cozinha (só com multi_cozinha e mais de uma cozinha a aceitar pedidos) */}
        {ligada('multi_cozinha') && !carrinho.grupo && cozinhas.length > 1 && (
          <View style={{ gap: espaco.s }}>
            <Escolha
              opcoes={cozinhas.map((c) => ({ valor: c.cozinha_id, rotulo: c.nome }))}
              valor={cozinhaId ?? ''}
              aoMudar={(id) => {
                const c = cozinhas.find((x) => x.cozinha_id === id);
                if (c) carrinho.definirCozinha({ id: c.cozinha_id, nome: c.nome });
              }}
            />
            {carrinho.quantidade > 0 && (
              <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Mudar de cozinha esvazia o carrinho.</Text>
            )}
          </View>
        )}
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
        {ligada('pedidos_grupo') && carrinho.grupo && (
          <Aviso>
            A juntar ao pedido de grupo das {carrinho.grupo.hora}. Escolhe os teus pratos.{' '}
            <Text style={{ fontWeight: '700' }} onPress={() => carrinho.definirGrupo(null)}>
              Sair do grupo
            </Text>
          </Aviso>
        )}
        {/* I10: morada da cozinha e botão para o Google Maps */}
        {ligada('como_chegar') && (cozinhaId ?? cardapio?.[0]?.cozinha_id) && (
          <ComoChegar cozinhaId={(cozinhaId ?? cardapio?.[0]?.cozinha_id) as string} />
        )}
        {ligada('pacotes') && !carrinho.grupo && (
          <Botao titulo="Pacote do mês: paga uma vez, almoça o mês todo" variante="secundario" aoCarregar={() => router.push('/pacotes')} />
        )}
        {ligada('pedidos_grupo') && !carrinho.grupo && (
          <Botao titulo="Pedido de grupo com os colegas" variante="secundario" aoCarregar={() => router.push('/grupos')} />
        )}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {cardapio !== null && cardapio.length === 0 && <Paragrafo suave>O cardápio de hoje ainda não está disponível.</Paragrafo>}
        {categorias.map(([categoria, itens]) => (
          <View key={categoria} style={{ gap: espaco.s }}>
            {categoria === 'Prato do dia' ? (
              <View style={{ alignSelf: 'flex-start', backgroundColor: cores.destaqueFundo, borderRadius: 14, paddingHorizontal: espaco.m, paddingVertical: 4, marginTop: espaco.s }}>
                <Text style={{ color: cores.texto, fontWeight: '700', fontSize: 15 }}>★ Prato do dia</Text>
              </View>
            ) : (
              <Subtitulo>{categoria}</Subtitulo>
            )}
            {itens.map((item) => {
              const noCarrinho = carrinho.quantidadeDe(item.id);
              return (
                <View key={item.id} style={{ backgroundColor: cores.fundoSuave, borderRadius: raio, padding: espaco.m, gap: 4 }}>
                  {item.foto_url ? (
                    <Image
                      source={{ uri: item.foto_url }}
                      style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio, marginBottom: 4 }}
                      accessibilityLabel={item.nome}
                    />
                  ) : null}
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
                    {esgotados.has(item.id) ? (
                      <Text style={{ color: cores.textoSuave, fontWeight: '700' }}>Esgotado</Text>
                    ) : (
                      <Pressable
                        accessibilityRole="button"
                        onPress={() =>
                          montaveis.has(item.id)
                            ? router.push({ pathname: '/montar/[id]', params: { id: item.id } })
                            : carrinho.adicionar(item)
                        }
                        style={{ backgroundColor: cores.marcaClara, borderRadius: 20, paddingHorizontal: espaco.l, paddingVertical: 6 }}>
                        <Text style={{ color: cores.marca, fontWeight: '700' }}>{montaveis.has(item.id) ? 'Montar' : 'Adicionar'}</Text>
                      </Pressable>
                    )}
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
