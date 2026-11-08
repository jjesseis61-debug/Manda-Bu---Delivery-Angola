import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Image, Pressable, ScrollView, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ACarregar, Aviso, Botao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { lerComponentes, lerDoses, lerItemCardapio, lerOpcoes } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { alternar, emojiOpcao, gruposEmFalta, gruposEsgotados, opcoesEscolhidas, precoMontado, regraGrupo } from '@/lib/opcoes';
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
  const { id } = useLocalSearchParams<{ id: string }>();
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

  useEffect(() => {
    Promise.all([lerItemCardapio(String(id)), lerOpcoes([String(id)]), lerComponentes([String(id)]).catch(() => [])])
      .then(([i, g, c]) => {
        setItem(i);
        if (i) lerDoses(i.cozinha_id).then((ds) => setSemDoses(ds.some((d) => d.cardapio_id === i.id && d.restantes === 0)), () => undefined);
        // Só se pode tirar ingredientes quando a receita tem mais do que um (não se tira tudo)
        setComponentes(c.length > 1 ? c : []);
        // Grupos opcionais sem opções disponíveis não aparecem; os obrigatórios ficam para mostrar que esgotaram
        setGrupos(g.filter((x) => x.opcoes.length > 0 || x.minimo > 0));
      })
      .catch((e) => {
        setErro(mensagemErro(e));
        setItem(null);
      });
  }, [id]);

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

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }} edges={['bottom', 'left', 'right']}>
      <View style={{ flex: 1, flexDirection: 'row' }}>
        {/* ---------------- ESQUERDA: escolhas em rolagem ---------------- */}
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: espaco.l, paddingBottom: espaco.xl, gap: espaco.m }}>
          {item.foto_url ? (
            <Image source={{ uri: item.foto_url }} style={{ width: '100%', aspectRatio: 4 / 3, borderRadius: raio }} accessibilityLabel={item.nome} />
          ) : null}
          <Text style={{ color: cores.marca, fontSize: 12, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.4 }}>
            À tua maneira
          </Text>
          <Text style={{ fontSize: 22, fontWeight: '700', color: cores.texto }}>{item.nome}</Text>
          {item.descricao && <Paragrafo suave>{item.descricao}</Paragrafo>}

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
          </ScrollView>

          {/* Soma + Adicionar, sempre à vista */}
          <View style={{ padding: espaco.m, borderTopWidth: 1, borderTopColor: cores.linha, backgroundColor: '#fff', gap: espaco.s }}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <Text style={{ fontSize: 13, color: cores.textoSuave }}>Soma</Text>
              <Text style={{ fontSize: 17, fontWeight: '800', color: cores.texto }}>{formatarKz(total)}</Text>
            </View>
            <Botao
              titulo={esgotados.length > 0 ? 'Esgotado' : `Adicionar · ${formatarKz(total)}`}
              desactivado={faltam.length > 0 || esgotados.length > 0}
              aoCarregar={() => {
                carrinho.adicionar(item, opcoes, semEstes);
                // Aberto por link não há ecrã anterior: segue para o início
                if (router.canGoBack()) router.back();
                else router.replace('/inicio');
              }}
            />
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}
