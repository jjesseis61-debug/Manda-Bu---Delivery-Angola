import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Image, Pressable, ScrollView, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Confirmar } from '@/components/Confirmar';
import { ACarregar, Aviso, Botao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { lerComponentes, lerDoses, lerItemCardapio, lerOpcoes } from '@/lib/api';
import { type PendenteMontar, useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { alternar, emojiOpcao, gruposEmFalta, gruposEsgotados, opcoesEscolhidas, precoMontado, regraGrupo } from '@/lib/opcoes';
import { cozinhasDisponiveis, decidirCozinha, pratoSimples, TEXTO_INDISPONIVEL } from '@/lib/pratoPartilhado';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';
import type { ComponentePrato, GrupoOpcoes, ItemCardapio } from '@/lib/tipos';

/** Largura da coluna fixa "O teu prato" (a soma do prato, sempre à vista) */
const LARGURA_RESUMO = 150;

/**
 * I9. Montar o prato em 2 colunas (modelo Meesho): à esquerda os grupos/opções em rolagem,
 * à direita, fixa, a soma do prato que cresce a cada escolha, com o botão Adicionar sempre à vista.
 * As escolhas tiram ingredientes da receita (o que se tira não se paga) e o preço actualiza.
 * O servidor volta a validar e calcula o preço a pagar.
 */
export default function MontarPrato() {
  const { id, rever } = useLocalSearchParams<{ id: string; rever?: string }>();
  const router = useRouter();
  const { carregado, ligada } = useSessao();
  const carrinho = useCarrinho();
  const [item, setItem] = useState<ItemCardapio | null | undefined>(undefined);
  const [grupos, setGrupos] = useState<GrupoOpcoes[]>([]);
  const [escolhidas, setEscolhidas] = useState<string[]>([]);
  const [componentes, setComponentes] = useState<ComponentePrato[]>([]);
  const [tirados, setTirados] = useState<string[]>([]);
  const [semDoses, setSemDoses] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  // "Pedir de novo" de um prato que mudou: chega com rever=1 e o prato pendente à frente da fila
  const [pendente, setPendente] = useState<PendenteMontar | null>(null);
  const repeticaoRef = useRef(carrinho.repeticao);
  repeticaoRef.current = carrinho.repeticao;
  // Cozinhas a que o cliente pode pedir (o prato pode ser de outra cozinha, aberto por link)
  const [disponiveis, setDisponiveis] = useState<{ id: string; nome: string }[] | null>(null);
  const [trocaPendente, setTrocaPendente] = useState<(() => void) | null>(null);
  const [avisoCozinha, setAvisoCozinha] = useState<string | null>(null);
  const multi = ligada('multi_cozinha');
  const comCondominios = ligada('condominios');

  useEffect(() => {
    Promise.all([lerItemCardapio(String(id)), lerOpcoes([String(id)]), lerComponentes([String(id)]).catch(() => [])])
      .then(([i, g, c]) => {
        setItem(i);
        if (i) lerDoses(i.cozinha_id).then((ds) => setSemDoses(ds.some((d) => d.cardapio_id === i.id && d.restantes === 0)), () => undefined);
        // Só se pode tirar ingredientes quando a receita tem mais do que um (não se tira tudo)
        setComponentes(c.length > 1 ? c : []);
        // Grupos opcionais sem opções disponíveis não aparecem; os obrigatórios ficam para mostrar que esgotaram
        setGrupos(g.filter((x) => x.opcoes.length > 0 || x.minimo > 0));
        const frente = repeticaoRef.current?.fila[0];
        const pend = rever === '1' && frente && frente.itemId === String(id) ? frente : null;
        setPendente(pend);
        if (pend) {
          // Volta como estava, só com o que ainda há; o cliente troca o que faltou ou segue sem ele
          const ids = new Set(g.flatMap((x) => x.opcoes.map((o) => o.id)));
          setEscolhidas(pend.escolhidas.filter((x) => ids.has(x)));
          setTirados(c.length > 1 ? pend.tirados.filter((x) => c.some((k) => k.produto_id === x)) : []);
        }
      })
      .catch((e) => {
        setErro(mensagemErro(e));
        setItem(null);
      });
  }, [id, rever]);

  useEffect(() => {
    if (!carregado) return;
    let vivo = true;
    cozinhasDisponiveis(multi, comCondominios).then((d) => vivo && setDisponiveis(d));
    return () => {
      vivo = false;
    };
  }, [carregado, multi, comCondominios]);

  // Aberto por link: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('pratos_montaveis')) return <Redirect href="/inicio" />;
  if (item === undefined) return <ACarregar />;
  if (item === null) return <Ecra><Aviso tipo="erro">{erro ?? 'Este prato já não está disponível.'}</Aviso></Ecra>;

  const opcoes = opcoesEscolhidas(grupos, escolhidas);
  const fotoDaOpcao = (id: string) => grupos.flatMap((g) => g.opcoes).find((x) => x.id === id)?.foto_url ?? null;
  const semEstes = componentes.filter((c) => tirados.includes(c.produto_id));
  const esgotados = [...gruposEsgotados(grupos), ...(semDoses ? ['as doses de hoje'] : [])];
  const faltam = gruposEmFalta(grupos, escolhidas);
  const total = precoMontado(item.preco, opcoes, semEstes);
  const minimo = item.minimo_montavel ?? 0;
  const abaixoMinimo = minimo > 0 && total < minimo;

  /**
   * Põe o prato no carrinho na cozinha certa. Prato de outra cozinha (aberto por link): com o
   * carrinho vazio muda de cozinha; com pratos no carrinho pergunta antes de o esvaziar.
   */
  function adicionarNaCozinha(depois: () => void) {
    if (!item) return;
    setAvisoCozinha(null);
    const actual = carrinho.cozinhaActual?.id ?? null;
    const decisao = decidirCozinha({
      cozinhaPrato: item.cozinha_id,
      // Sem multi_cozinha só há a cozinha principal: o carrinho não guarda cozinha
      actual: multi ? actual : item.cozinha_id,
      quantidade: carrinho.quantidade,
      emGrupo: carrinho.grupo !== null,
      disponiveis: disponiveis?.map((c) => c.id) ?? null,
    });
    const nomeCozinha = disponiveis?.find((c) => c.id === item.cozinha_id)?.nome ?? '';
    const colocar = () => {
      carrinho.adicionar(item, opcoes, semEstes);
      depois();
    };
    if (decisao === 'indisponivel') setAvisoCozinha(TEXTO_INDISPONIVEL);
    else if (decisao === 'grupo')
      setAvisoCozinha(`Estás num pedido de grupo da ${carrinho.cozinhaActual?.nome ?? 'outra cozinha'}: este prato é de outra cozinha.`);
    else if (decisao === 'adicionar') colocar();
    else if (decisao === 'trocar') {
      carrinho.definirCozinha({ id: item.cozinha_id, nome: nomeCozinha });
      colocar();
    } else
      setTrocaPendente(() => () => {
        carrinho.definirCozinha({ id: item.cozinha_id, nome: nomeCozinha });
        colocar();
      });
  }

  const voltar = () => {
    // Aberto por link não há ecrã anterior: segue para o início
    if (router.canGoBack()) router.back();
    else router.replace('/inicio');
  };

  const caixaTroca = (
    <Confirmar
      visivel={trocaPendente !== null}
      titulo="Trocar de cozinha?"
      mensagem={`Este prato é de ${disponiveis?.find((c) => c.id === item.cozinha_id)?.nome || 'outra cozinha'}. O teu carrinho tem pratos de ${carrinho.cozinhaActual?.nome || 'outra cozinha'} e vai ficar vazio.`}
      textoConfirmar="Trocar e adicionar"
      aoConfirmar={() => {
        const f = trocaPendente;
        setTrocaPendente(null);
        f?.();
      }}
      aoCancelar={() => setTrocaPendente(null)}
    />
  );

  // Prato sem opções nem ingredientes para tirar: página simples (não há nada para montar)
  if (pratoSimples(grupos, componentes) && !pendente) {
    return (
      <Ecra>
        {caixaTroca}
        {item.foto_url ? (
          <Image source={{ uri: item.foto_url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio }} accessibilityLabel={item.nome} />
        ) : null}
        <Text style={{ fontSize: 22, fontWeight: '700', color: cores.texto }}>{item.nome.trim()}</Text>
        {item.descricao && <Paragrafo suave>{item.descricao}</Paragrafo>}
        <Text style={{ fontSize: 18, fontWeight: '800', color: cores.texto }}>{formatarKz(item.preco)}</Text>
        {semDoses && <Aviso>Esgotado: acabaram as doses de hoje.</Aviso>}
        {avisoCozinha && <Aviso>{avisoCozinha}</Aviso>}
        <Botao
          titulo={semDoses ? 'Esgotado' : `Adicionar ao carrinho · ${formatarKz(item.preco)}`}
          desactivado={semDoses}
          aoCarregar={() => adicionarNaCozinha(voltar)}
        />
        <Botao titulo="Ver o cardápio" variante="texto" aoCarregar={() => router.replace('/inicio')} />
      </Ecra>
    );
  }

  /** Fila do "Pedir de novo": passa ao prato seguinte a rever, ou ao carrinho quando acaba */
  function seguirFila() {
    const faltamRepeticao = carrinho.repeticao?.faltam ?? [];
    const seguinte = carrinho.avancarFila();
    if (seguinte) router.replace({ pathname: '/montar/[id]', params: { id: seguinte.itemId, rever: '1' } });
    else router.replace({ pathname: '/carrinho', params: faltamRepeticao.length > 0 ? { faltam: faltamRepeticao.join(', ') } : {} });
  }

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }} edges={['bottom', 'left', 'right']}>
      {caixaTroca}
      <View style={{ flex: 1, flexDirection: 'row' }}>
        {/* ---------------- ESQUERDA: escolhas em rolagem ---------------- */}
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: espaco.l, paddingBottom: espaco.xl, gap: espaco.m }}>
          {item.foto_url ? (
            <Image source={{ uri: item.foto_url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio }} accessibilityLabel={item.nome} />
          ) : null}
          <Text style={{ color: cores.marca, fontSize: 12, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.4 }}>
            À tua maneira
          </Text>
          <Text style={{ fontSize: 22, fontWeight: '700', color: cores.texto }}>{item.nome.trim()}</Text>
          {item.descricao && <Paragrafo suave>{item.descricao}</Paragrafo>}
          {minimo > 0 && (
            <Text style={{ color: cores.marca, fontSize: 13, fontWeight: '600' }}>
              O valor mínimo para servir é {formatarKz(minimo)}.
            </Text>
          )}
          {pendente && (
            <Aviso>
              {pendente.faltaram.length > 0
                ? `Do teu pedido anterior já não temos: ${pendente.faltaram.join(', ')}. Escolhe outra opção ou continua sem ela.`
                : 'Revê o teu prato do pedido anterior: as opções ou o valor mínimo mudaram desde então.'}
            </Aviso>
          )}

          {grupos.map((g) => {
            const noGrupo = g.opcoes.filter((o) => escolhidas.includes(o.id)).length;
            const satisfeito = g.minimo > 0 && noGrupo >= g.minimo;
            return (
              <View key={g.id} style={{ gap: espaco.s }}>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginTop: espaco.s }}>
                  <Text style={{ color: cores.marca, fontSize: 14, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 0.3 }}>{g.nome}</Text>
                  <Text style={{ color: cores.textoSuave, fontSize: 12, textTransform: 'lowercase' }}>{regraGrupo(g)}{satisfeito ? ' ✓' : ''}</Text>
                </View>
                {g.opcoes.map((o) => {
                  const marcada = escolhidas.includes(o.id);
                  const cheio = !marcada && g.maximo > 1 && noGrupo >= g.maximo;
                  return (
                    <Pressable
                      key={o.id}
                      accessibilityRole={g.maximo === 1 ? 'radio' : 'checkbox'}
                      accessibilityState={{ checked: marcada, disabled: cheio }}
                      onPress={() => setEscolhidas((e) => alternar(g, e, o.id))}
                      style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        gap: espaco.s,
                        padding: espaco.s,
                        borderRadius: raio,
                        borderWidth: 1,
                        borderColor: marcada ? cores.marca : cores.linha,
                        backgroundColor: marcada ? cores.marcaClara : '#fff',
                        opacity: cheio ? 0.45 : 1,
                      }}>
                      {o.foto_url ? (
                        <Image source={{ uri: o.foto_url }} style={{ width: 38, height: 38, borderRadius: 9 }} accessibilityLabel={o.nome} />
                      ) : (
                        <View style={{ width: 38, height: 38, borderRadius: 9, backgroundColor: cores.fundoSuave, alignItems: 'center', justifyContent: 'center' }}>
                          <Text style={{ fontSize: 20 }}>{emojiOpcao(o.nome)}</Text>
                        </View>
                      )}
                      <View style={{ flex: 1, gap: 2 }}>
                        <Text style={{ fontSize: 15 }}>{o.nome}</Text>
                        {o.preco_extra > 0 && <Text style={{ color: cores.textoSuave, fontSize: 12 }}>+{formatarKz(o.preco_extra)}</Text>}
                      </View>
                      <View
                        style={{
                          width: 26,
                          height: 26,
                          borderRadius: 13,
                          borderWidth: 1.5,
                          borderColor: cores.marca,
                          alignItems: 'center',
                          justifyContent: 'center',
                          backgroundColor: marcada ? cores.marca : '#fff',
                        }}>
                        <Text style={{ color: marcada ? '#fff' : cores.marca, fontSize: 15, fontWeight: '800', lineHeight: 17 }}>{marcada ? '✓' : '+'}</Text>
                      </View>
                    </Pressable>
                  );
                })}
              </View>
            );
          })}

          {componentes.length > 0 && (
            <View style={{ gap: espaco.s }}>
              <Subtitulo>Ingredientes</Subtitulo>
              <Text style={{ color: cores.textoSuave }}>Toca para tirar o que não queres. O que tiras não pagas.</Text>
              {componentes.map((c) => {
                const tirado = tirados.includes(c.produto_id);
                // Fica sempre pelo menos um ingrediente
                const ultimo = !tirado && tirados.length >= componentes.length - 1;
                return (
                  <Pressable
                    key={c.produto_id}
                    accessibilityRole="checkbox"
                    accessibilityLabel={`Tirar ${c.nome}`}
                    accessibilityState={{ checked: tirado, disabled: ultimo }}
                    disabled={ultimo}
                    onPress={() => setTirados((t) => (tirado ? t.filter((x) => x !== c.produto_id) : [...t, c.produto_id]))}
                    style={{
                      flexDirection: 'row',
                      alignItems: 'center',
                      gap: espaco.s,
                      padding: espaco.m,
                      borderRadius: raio,
                      borderWidth: 1,
                      borderColor: tirado ? cores.marca : cores.linha,
                      opacity: ultimo ? 0.45 : 1,
                    }}>
                    <Text style={{ color: cores.marca, fontSize: 18 }}>{tirado ? '☒' : '☐'}</Text>
                    <Text style={{ flex: 1, fontSize: 15, textDecorationLine: tirado ? 'line-through' : 'none' }}>{c.nome}</Text>
                    {c.valor > 0 && <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{tirado ? '−' : ''}{formatarKz(c.valor)}</Text>}
                  </Pressable>
                );
              })}
            </View>
          )}

          {avisoCozinha && <Aviso>{avisoCozinha}</Aviso>}
          {esgotados.length > 0 && (
            <Aviso>{semDoses ? 'Esgotado: acabaram as doses de hoje.' : `Esgotado de momento: não há nenhuma opção disponível em ${esgotados.join(', ')}.`}</Aviso>
          )}
        </ScrollView>

        {/* ---------------- DIREITA: a soma do prato (fixa) ---------------- */}
        <View style={{ width: LARGURA_RESUMO, borderLeftWidth: 1, borderLeftColor: cores.linha, backgroundColor: cores.fundoSuave }}>
          <Text style={{ fontWeight: '800', color: cores.texto, fontSize: 14, padding: espaco.m, paddingBottom: espaco.s }}>
            🍽️ O teu prato
          </Text>
          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: espaco.m, gap: espaco.s }}>
            {/* Opções escolhidas */}
            {opcoes.map((o) => (
              <View key={o.id} style={{ backgroundColor: '#fff', borderWidth: 1, borderColor: cores.linha, borderRadius: 9, padding: espaco.s, flexDirection: 'row', alignItems: 'center', gap: espaco.xs }}>
                {fotoDaOpcao(o.id) ? (
                  <Image source={{ uri: fotoDaOpcao(o.id) as string }} style={{ width: 22, height: 22, borderRadius: 5 }} accessibilityLabel={o.nome} />
                ) : (
                  <Text style={{ fontSize: 15 }}>{emojiOpcao(o.nome)}</Text>
                )}
                <Text numberOfLines={1} style={{ fontSize: 13, color: cores.texto, flex: 1 }}>{o.nome}</Text>
                {o.preco_extra > 0 && <Text style={{ fontSize: 12, color: cores.textoSuave }}>+{formatarKz(o.preco_extra)}</Text>}
              </View>
            ))}
            {/* Ingredientes tirados */}
            {semEstes.map((c) => (
              <Text key={c.produto_id} style={{ fontSize: 12, color: cores.textoSuave, fontStyle: 'italic' }}>sem {c.nome}</Text>
            ))}
            {/* Sugestão / o que falta (Bandura: meta próxima). Mantém o texto exacto esperado. */}
            {esgotados.length === 0 && faltam.length > 0 && (
              <View style={{ backgroundColor: cores.marcaClara, borderLeftWidth: 4, borderLeftColor: cores.marca, borderRadius: 8, padding: espaco.s }}>
                <Text style={{ fontSize: 12, fontWeight: '600', color: cores.marcaEscura }}>Falta escolher: {faltam.join(', ')}.</Text>
              </View>
            )}
            {opcoes.length === 0 && faltam.length === 0 && (
              <Text style={{ fontSize: 12, color: cores.textoSuave, fontStyle: 'italic' }}>Escolhe à esquerda para montar o prato.</Text>
            )}
            {esgotados.length === 0 && faltam.length === 0 && abaixoMinimo && (
              <View style={{ backgroundColor: cores.marcaClara, borderLeftWidth: 4, borderLeftColor: cores.marca, borderRadius: 8, padding: espaco.s }}>
                <Text style={{ fontSize: 12, fontWeight: '600', color: cores.marcaEscura }}>
                  Falta {formatarKz(minimo - total)} para o mínimo de {formatarKz(minimo)}.
                </Text>
              </View>
            )}
          </ScrollView>

          {/* Soma + Adicionar, sempre à vista */}
          <View style={{ padding: espaco.m, borderTopWidth: 1, borderTopColor: cores.linha, backgroundColor: '#fff', gap: espaco.s }}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <Text style={{ fontSize: 13, color: cores.textoSuave }}>Soma</Text>
              <Text style={{ fontSize: 17, fontWeight: '800', color: cores.texto }}>{formatarKz(total)}</Text>
            </View>
            <Botao
              titulo={
                esgotados.length > 0
                  ? 'Esgotado'
                  : pendente && pendente.qtd > 1
                    ? `Adicionar ${pendente.qtd}× · ${formatarKz(total * pendente.qtd)}`
                    : `Adicionar · ${formatarKz(total)}`
              }
              desactivado={faltam.length > 0 || esgotados.length > 0 || abaixoMinimo}
              aoCarregar={() => {
                if (pendente) {
                  carrinho.adicionar(item, opcoes, semEstes, pendente.qtd);
                  seguirFila();
                  return;
                }
                adicionarNaCozinha(voltar);
              }}
            />
            {pendente && <Botao titulo="Tirar este prato do pedido" variante="texto" aoCarregar={seguirFila} />}
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}
