import { type ReactNode, useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Pressable, ScrollView, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { RecipienteDesenhado, Tabuleiro } from '@/components/Recipientes';
import { Botao } from '@/components/ui';
import {
  dicaDoPasso,
  passoFeito,
  passosDoBalcao,
  perguntaDoPasso,
  recipienteDaOpcao,
  textoRestam,
  textoRestamOpcao,
  textoSeguinte,
  pecasDoPrato,
  zonaDaOpcao,
  zonasDasPecas,
  zonasDoPrato,
} from '@/lib/balcaoPanelas';
import { formatarKz } from '@/lib/formatar';
import { cores, espaco, raio } from '@/lib/tema';
import type { ComponentePrato, GrupoOpcoes } from '@/lib/tipos';

const PRATO = 150;
const MADEIRA = '#F2E6D8';
const GELEIRA = '#E3F0F7';

type Props = {
  grupos: GrupoOpcoes[];
  componentes: ComponentePrato[];
  escolhidas: string[];
  tirados: string[];
  aoEscolher: (grupo: GrupoOpcoes, opcaoId: string) => void;
  aoTirar: (produtoId: string) => void;
  total: number;
  /** Pratos que restam hoje (contagem real das doses), ou null sem contagem */
  restantes: number | null;
  /** Unidades que restam de cada opção que conta o stock (latas, garrafas) */
  unidades: Record<string, number>;
  /** Grupos obrigatórios ainda por escolher (o servidor recusaria o prato sem eles) */
  faltam: string[];
  tituloAdicionar: string;
  adicionarDesactivado: boolean;
  aoAdicionar: () => void;
  /** Cabeçalho: nome do prato, convite, mínimo, aviso do pedido anterior */
  topo: ReactNode;
  /** Avisos de baixo: esgotado, cozinha errada */
  avisos: ReactNode;
  rodape?: ReactNode;
  caixas?: ReactNode;
};

/**
 * «Serve o teu prato» como num balcão: um passo de cada vez, a comida em panelas e tigelas vistas
 * de cima e as bebidas numa geleira; em baixo o tabuleiro com o prato (base, proteína e
 * acompanhamentos, cada um na sua zona) e a bebida ao lado, com a conta.
 * As escolhas usam as mesmas regras do ecrã em lista; o servidor valida e calcula o preço.
 */
export function BalcaoPanelas(p: Props) {
  const passos = passosDoBalcao(p.grupos, p.componentes);
  const [indice, setIndice] = useState(0);
  const [verLista, setVerLista] = useState(false);
  const passo = passos[Math.min(indice, passos.length - 1)];
  const ultimo = indice >= passos.length - 1;
  const zonas = zonasDoPrato(p.grupos, p.escolhidas);
  // Cada peça leva o seu recipiente (a sopa vai em malga, o pão no cesto, a gasosa em lata)
  const comRecipiente = zonasDasPecas(pecasDoPrato(p.grupos, p.escolhidas));
  const noPrato = [...zonas.base, ...zonas.proteina, ...zonas.acompanhamento];
  // Pela ordem em que se serve: prato, o que vai ao lado, sobremesa e bebida
  const todos = [...noPrato, ...zonas.lado, ...zonas.sobremesa, ...zonas.bebida];
  const temBebidas = passos.some((x) => x.tipo === 'bebida');
  const temSobremesa = passos.some((x) => x.tipo === 'sobremesa');
  const restam = textoRestam(p.restantes);

  // Resposta a cada escolha (Skinner): o prato dá um pequeno salto quando recebe comida
  const salto = useRef(new Animated.Value(1)).current;
  const [semMovimento, setSemMovimento] = useState(false);
  const antes = useRef(p.escolhidas.length);
  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled?.()
      .then((v) => setSemMovimento(!!v))
      .catch(() => undefined);
  }, []);
  useEffect(() => {
    const mais = p.escolhidas.length > antes.current;
    antes.current = p.escolhidas.length;
    if (!mais || semMovimento) return;
    Animated.sequence([
      Animated.timing(salto, { toValue: 1.06, duration: 120, useNativeDriver: true }),
      Animated.spring(salto, { toValue: 1, friction: 4, useNativeDriver: true }),
    ]).start();
  }, [p.escolhidas.length, semMovimento, salto]);

  if (!passo) return null;
  const feitos = passos.map((x) => passoFeito(x, p.escolhidas));
  const eBebida = passo.tipo === 'bebida';

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }} edges={['bottom', 'left', 'right']}>
      {p.caixas}
      {/* Passos: o feito fica verde, o actual a vermelho; toca-se para voltar atrás */}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0 }} contentContainerStyle={{ gap: espaco.xs, paddingHorizontal: espaco.l, paddingTop: espaco.s }}>
        {passos.map((x, i) => {
          const actual = i === indice;
          const feito = !actual && feitos[i] && (i < indice || p.escolhidas.some((id) => x.grupo?.opcoes.some((o) => o.id === id)));
          return (
            <Pressable
              key={x.chave}
              accessibilityRole="tab"
              accessibilityState={{ selected: actual }}
              accessibilityLabel={`Passo ${i + 1}: ${x.titulo}${feito ? ', feito' : ''}`}
              onPress={() => setIndice(i)}
              style={{
                paddingHorizontal: 10,
                paddingVertical: 5,
                borderRadius: 14,
                borderWidth: 1.5,
                borderColor: actual ? cores.marca : feito ? cores.sucesso : cores.linha,
                backgroundColor: actual ? cores.marca : feito ? cores.sucessoFundo : cores.fundo,
              }}>
              <Text style={{ fontSize: 12, fontWeight: '700', color: actual ? '#fff' : feito ? cores.sucesso : cores.textoSuave }}>
                {feito ? '✓ ' : `${i + 1} · `}
                {x.titulo}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: espaco.l, gap: espaco.m, paddingBottom: espaco.xl }}>
        {indice === 0 && p.topo}
        <View style={{ gap: 2 }}>
          <Text style={{ fontSize: 18, fontWeight: '800', color: cores.texto }}>{perguntaDoPasso(passo)}</Text>
          <Text style={{ fontSize: 13, color: cores.textoSuave }}>{dicaDoPasso(passo)}</Text>
        </View>

        {passo.grupo ? (
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', rowGap: espaco.m, backgroundColor: eBebida ? GELEIRA : MADEIRA, borderRadius: raio, paddingVertical: espaco.m }}>
            {passo.grupo.opcoes.length === 0 && (passo.grupo.acabaram ?? []).length === 0 && (
              <Text style={{ padding: espaco.m, color: cores.textoSuave }}>Hoje não há nada nesta parte do balcão.</Text>
            )}
            {passo.grupo.opcoes.map((o) => {
              const g = passo.grupo as GrupoOpcoes;
              const escolhida = p.escolhidas.includes(o.id);
              const noGrupo = g.opcoes.filter((x) => p.escolhidas.includes(x.id)).length;
              const cheio = !escolhida && g.maximo > 1 && noGrupo >= g.maximo;
              const resta = textoRestamOpcao(p.unidades[o.id]);
              const zona = zonaDaOpcao(g, o);
              const noTabuleiro = zona === 'lado' || zona === 'sobremesa' || zona === 'bebida';
              return (
                <Pressable
                  key={o.id}
                  accessibilityRole={g.maximo === 1 ? 'radio' : 'checkbox'}
                  accessibilityState={{ checked: escolhida, disabled: cheio }}
                  accessibilityHint={escolhida ? (noTabuleiro ? 'Toca para tirar do tabuleiro' : 'Toca para devolver') : noTabuleiro ? 'Toca para pôr no tabuleiro' : 'Toca para pôr no prato'}
                  onPress={() => p.aoEscolher(g, o.id)}
                  style={{ width: '50%', alignItems: 'center', gap: 2, opacity: cheio ? 0.45 : 1 }}>
                  <RecipienteDesenhado tipo={recipienteDaOpcao(g, o)} opcao={o} escolhida={escolhida} />
                  <Text style={{ fontSize: 14, fontWeight: '700', color: cores.texto, textAlign: 'center' }} numberOfLines={2}>
                    {o.nome.trim()}
                  </Text>
                  <Text style={{ fontSize: 12, color: cores.textoSuave }}>{o.preco_extra > 0 ? `+${formatarKz(o.preco_extra)}` : 'incluído'}</Text>
                  {resta && !escolhida && (
                    <View style={{ backgroundColor: cores.avisoFundo, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 1 }}>
                      <Text style={{ color: cores.aviso, fontSize: 11, fontWeight: '800' }}>{resta}</Text>
                    </View>
                  )}
                  {escolhida && (
                    <View style={{ backgroundColor: cores.marca, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 1 }}>
                      <Text style={{ color: '#fff', fontSize: 11, fontWeight: '800' }}>{noTabuleiro ? '✓ no tabuleiro' : '🥄 no prato'}</Text>
                    </View>
                  )}
                </Pressable>
              );
            })}
            {(passo.grupo.acabaram ?? []).map((o) => (
              <View key={o.id} accessible accessibilityLabel={`${o.nome.trim()}: hoje não há`} style={{ width: '50%', alignItems: 'center', gap: 2 }}>
                <RecipienteDesenhado tipo={recipienteDaOpcao(passo.grupo as GrupoOpcoes, o)} opcao={o} vazia />
                <Text style={{ fontSize: 14, fontWeight: '700', color: cores.textoSuave, textAlign: 'center' }} numberOfLines={2}>
                  {o.nome.trim()}
                </Text>
                <View style={{ backgroundColor: cores.fundoSuave, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 1 }}>
                  <Text style={{ color: cores.textoSuave, fontSize: 11, fontWeight: '800' }}>Hoje não há</Text>
                </View>
              </View>
            ))}
          </View>
        ) : (
          <View style={{ gap: espaco.s }}>
            {p.componentes.map((c) => {
              const tirado = p.tirados.includes(c.produto_id);
              const unico = !tirado && p.tirados.length >= p.componentes.length - 1;
              return (
                <Pressable
                  key={c.produto_id}
                  accessibilityRole="checkbox"
                  accessibilityLabel={`Tirar ${c.nome}`}
                  accessibilityState={{ checked: tirado, disabled: unico }}
                  disabled={unico}
                  onPress={() => p.aoTirar(c.produto_id)}
                  style={{
                    flexDirection: 'row',
                    alignItems: 'center',
                    gap: espaco.s,
                    padding: espaco.m,
                    borderRadius: raio,
                    borderWidth: 1,
                    borderColor: tirado ? cores.marca : cores.linha,
                    opacity: unico ? 0.45 : 1,
                  }}>
                  <Text style={{ color: cores.marca, fontSize: 18 }}>{tirado ? '☒' : '☐'}</Text>
                  <Text style={{ flex: 1, fontSize: 15, textDecorationLine: tirado ? 'line-through' : 'none' }}>{c.nome}</Text>
                  {c.valor > 0 && <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{tirado ? '−' : ''}{formatarKz(c.valor)}</Text>}
                </Pressable>
              );
            })}
          </View>
        )}
        {ultimo && p.faltam.length > 0 && (
          <Text style={{ fontSize: 13, fontWeight: '600', color: cores.marcaEscura }}>Falta escolher: {p.faltam.join(', ')}.</Text>
        )}
        {p.avisos}
      </ScrollView>

      {/* O que está no tabuleiro, quando se toca no prato */}
      {verLista && todos.length > 0 && (
        <View style={{ borderTopWidth: 1, borderTopColor: '#E0D3C3', backgroundColor: '#fff', paddingHorizontal: espaco.l, paddingVertical: espaco.s, gap: 2 }}>
          {todos.map((o) => (
            <View key={o.id} style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 13, color: cores.texto }}>{o.nome.trim()}</Text>
              <Text style={{ fontSize: 13, color: cores.textoSuave }}>{o.preco_extra > 0 ? formatarKz(o.preco_extra) : 'incluído'}</Text>
            </View>
          ))}
        </View>
      )}

      {/* O tabuleiro na mão do cliente; a conta fica por baixo, sempre à vista (nunca tapada pelo tabuleiro) */}
      <View style={{ padding: espaco.m, gap: espaco.s, borderTopWidth: 2, borderTopColor: '#E0D3C3', backgroundColor: '#FFF8F0' }}>
        <View style={{ alignItems: 'flex-start' }}>
          <Tabuleiro
            zonas={comRecipiente}
            prato={PRATO}
            mostrarVazios={{ bebida: temBebidas, sobremesa: temSobremesa }}
            aoTocar={() => setVerLista((v) => !v)}
            rotuloAcessivel={noPrato.length > 0 ? `O teu prato: ${noPrato.map((o) => o.nome.trim()).join(', ')}. Toca para ver a lista` : 'O teu prato está vazio'}
            salto={salto}
          />
        </View>
        <Pressable
          onPress={() => setVerLista((v) => !v)}
          disabled={todos.length === 0}
          accessibilityRole="button"
          style={{ flexDirection: 'row', alignItems: 'baseline', flexWrap: 'wrap', columnGap: espaco.s }}>
          <Text style={{ fontSize: 22, fontWeight: '800', color: cores.texto }}>{formatarKz(p.total)}</Text>
          <Text style={{ fontSize: 12, color: cores.textoSuave }}>
            {todos.length === 0 ? 'o teu prato' : todos.length === 1 ? '1 item' : `${todos.length} itens`}
            {todos.length > 0 ? (verLista ? ' · esconder' : ' · ver') : ''}
          </Text>
          {restam && <Text style={{ fontSize: 12, fontWeight: '700', color: cores.aviso }}>{restam}</Text>}
        </Pressable>
        {ultimo ? (
          <Botao titulo={p.tituloAdicionar} desactivado={p.adicionarDesactivado} aoCarregar={p.aoAdicionar} />
        ) : (
          <Botao titulo={textoSeguinte(passos, indice, p.escolhidas)} desactivado={!feitos[indice]} aoCarregar={() => setIndice((i) => i + 1)} />
        )}
        {p.rodape}
      </View>
    </SafeAreaView>
  );
}
