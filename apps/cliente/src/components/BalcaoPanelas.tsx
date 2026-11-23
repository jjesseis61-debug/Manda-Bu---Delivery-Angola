import { type ReactNode, useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Image, Pressable, ScrollView, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Botao } from '@/components/ui';
import {
  dicaDoPasso,
  passoFeito,
  passosDoBalcao,
  perguntaDoPasso,
  recipienteDaOpcao,
  type Recipiente,
  textoRestam,
  textoRestamOpcao,
  textoSeguinte,
  zonasDoPrato,
} from '@/lib/balcaoPanelas';
import { formatarKz } from '@/lib/formatar';
import { emojiOpcao } from '@/lib/opcoes';
import { cores, espaco, raio } from '@/lib/tema';
import type { ComponentePrato, GrupoOpcoes, Opcao } from '@/lib/tipos';

/** Panelas e tigelas: grandes, para a fotografia ser o centro */
const TAMANHO = 104;
const DENTRO = 78;
const PRATO = 150;
const MADEIRA = '#F2E6D8';
const GELEIRA = '#E3F0F7';

const ESTILO_RECIPIENTE: Record<'panela' | 'barro' | 'tigela', { fundo: string; aro: string; asas: string | null }> = {
  panela: { fundo: '#C9CDD1', aro: '#8D9297', asas: '#3A3A3A' },
  barro: { fundo: '#9B5530', aro: '#6E3417', asas: '#5A2A10' },
  tigela: { fundo: '#F7F3EE', aro: '#D9D2C8', asas: null },
};

/** Fotografia da opção (ou o emoji, sem fotografia), com o recorte pedido */
function Comida({ opcao, largura, altura, raioCanto }: { opcao: Opcao; largura: number | `${number}%`; altura: number | `${number}%`; raioCanto: number }) {
  return opcao.foto_url ? (
    <Image source={{ uri: opcao.foto_url }} resizeMode="cover" style={{ width: largura, height: altura, borderRadius: raioCanto }} accessibilityIgnoresInvertColors />
  ) : (
    <View style={{ width: largura, height: altura, borderRadius: raioCanto, backgroundColor: '#FFF8F0', alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ fontSize: typeof altura === 'number' ? Math.max(14, altura * 0.45) : 22 }}>{emojiOpcao(opcao.nome)}</Text>
    </View>
  );
}

/** Copo de sumo ou lata/garrafa de gasosa, vistos de frente */
function Bebida({ tipo, opcao, escolhida, vazia, escala = 1 }: { tipo: 'copo' | 'lata'; opcao: Opcao | null; escolhida: boolean; vazia: boolean; escala?: number }) {
  const largura = (tipo === 'lata' ? 58 : 66) * escala;
  const altura = 92 * escala;
  return (
    <View style={{ width: largura, height: altura, alignItems: 'center' }}>
      {tipo === 'lata' && <View style={{ width: largura - 8 * escala, height: 7 * escala, borderTopLeftRadius: 4, borderTopRightRadius: 4, backgroundColor: '#B8BEC4' }} />}
      <View
        style={{
          flex: 1,
          width: largura,
          overflow: 'hidden',
          borderWidth: escolhida ? 3 : 2,
          borderColor: escolhida ? cores.marca : tipo === 'lata' ? '#9EA6AD' : '#B9D3E0',
          backgroundColor: tipo === 'lata' ? '#DDE2E6' : 'rgba(255,255,255,0.7)',
          borderTopLeftRadius: tipo === 'copo' ? 4 : 10 * escala,
          borderTopRightRadius: tipo === 'copo' ? 4 : 10 * escala,
          borderBottomLeftRadius: tipo === 'copo' ? 16 * escala : 10 * escala,
          borderBottomRightRadius: tipo === 'copo' ? 16 * escala : 10 * escala,
          alignItems: 'center',
          justifyContent: 'center',
        }}>
        {vazia || !opcao ? (
          <Text style={{ fontSize: 11 * escala, fontWeight: '700', color: '#5F6368' }}>{vazia ? 'vazia' : ''}</Text>
        ) : (
          <Comida opcao={opcao} largura="100%" altura="100%" raioCanto={0} />
        )}
      </View>
    </View>
  );
}

/** Panela, panela de barro ou tigela vista de cima, com a comida lá dentro (ou vazia, quando hoje não há) */
function Recipiente({ tipo, opcao, escolhida, vazia }: { tipo: Recipiente; opcao: Opcao; escolhida: boolean; vazia: boolean }) {
  if (tipo === 'copo' || tipo === 'lata') {
    return (
      <View style={{ height: TAMANHO, justifyContent: 'center' }}>
        <Bebida tipo={tipo} opcao={opcao} escolhida={escolhida} vazia={vazia} escala={1.05} />
      </View>
    );
  }
  const e = ESTILO_RECIPIENTE[tipo];
  return (
    <View style={{ width: TAMANHO + 20, height: TAMANHO, alignItems: 'center', justifyContent: 'center' }}>
      {e.asas && (
        <>
          <View style={{ position: 'absolute', left: 0, top: TAMANHO / 2 - 8, width: 18, height: 16, borderRadius: 6, backgroundColor: e.asas }} />
          <View style={{ position: 'absolute', right: 0, top: TAMANHO / 2 - 8, width: 18, height: 16, borderRadius: 6, backgroundColor: e.asas }} />
        </>
      )}
      <View
        style={{
          width: TAMANHO,
          height: TAMANHO,
          borderRadius: TAMANHO / 2,
          backgroundColor: e.fundo,
          borderWidth: escolhida ? 5 : 4,
          borderColor: escolhida ? cores.marca : e.aro,
          alignItems: 'center',
          justifyContent: 'center',
        }}>
        {vazia ? (
          <View style={{ width: DENTRO, height: DENTRO, borderRadius: DENTRO / 2, backgroundColor: '#B9BEC3', alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ fontSize: 13, fontWeight: '700', color: '#5F6368' }}>vazia</Text>
          </View>
        ) : (
          <Comida opcao={opcao} largura={DENTRO} altura={DENTRO} raioCanto={DENTRO / 2} />
        )}
      </View>
    </View>
  );
}

/** Uma zona do prato: as fotografias enchem-na (empilhadas quando há mais do que uma); vazia fica tracejada */
function Zona({ itens, largura, altura, rotulo }: { itens: Opcao[]; largura: number; altura: number; rotulo: string }) {
  if (itens.length === 0) {
    return (
      <View
        style={{ width: largura, height: altura, borderWidth: 1.5, borderStyle: 'dashed', borderColor: '#CFCFCF', alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ fontSize: 10, color: '#9A9A9A' }}>{rotulo}</Text>
      </View>
    );
  }
  const cada = altura / itens.length;
  return (
    <View style={{ width: largura, height: altura }}>
      {itens.map((o) => (
        <Comida key={o.id} opcao={o} largura={largura} altura={cada} raioCanto={0} />
      ))}
    </View>
  );
}

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
  const noPrato = [...zonas.base, ...zonas.proteina, ...zonas.acompanhamento];
  const todos = [...noPrato, ...zonas.bebida];
  const temBebidas = passos.some((x) => x.tipo === 'bebida');
  const bebida = zonas.bebida[0] ?? null;
  const tipoBebida = bebida ? (recipienteDaOpcao(p.grupos.find((g) => g.opcoes.some((o) => o.id === bebida.id)) ?? { nome: 'bebida', maximo: 1 }, bebida) as 'copo' | 'lata') : 'copo';
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
  const MEIO = (PRATO - 24) / 2;

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
              return (
                <Pressable
                  key={o.id}
                  accessibilityRole={g.maximo === 1 ? 'radio' : 'checkbox'}
                  accessibilityState={{ checked: escolhida, disabled: cheio }}
                  accessibilityHint={escolhida ? (eBebida ? 'Toca para tirar do tabuleiro' : 'Toca para devolver') : eBebida ? 'Toca para pôr no tabuleiro' : 'Toca para pôr no prato'}
                  onPress={() => p.aoEscolher(g, o.id)}
                  style={{ width: '50%', alignItems: 'center', gap: 2, opacity: cheio ? 0.45 : 1 }}>
                  <Recipiente tipo={recipienteDaOpcao(g, o)} opcao={o} escolhida={escolhida} vazia={false} />
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
                      <Text style={{ color: '#fff', fontSize: 11, fontWeight: '800' }}>{eBebida ? '✓ no tabuleiro' : '🥄 no prato'}</Text>
                    </View>
                  )}
                </Pressable>
              );
            })}
            {(passo.grupo.acabaram ?? []).map((o) => (
              <View key={o.id} accessible accessibilityLabel={`${o.nome.trim()}: hoje não há`} style={{ width: '50%', alignItems: 'center', gap: 2 }}>
                <Recipiente tipo={recipienteDaOpcao(passo.grupo as GrupoOpcoes, o)} opcao={o} escolhida={false} vazia />
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

      {/* O tabuleiro na mão do cliente: o prato com as zonas, a bebida ao lado e a conta */}
      <View style={{ padding: espaco.m, gap: espaco.s, borderTopWidth: 2, borderTopColor: '#E0D3C3', backgroundColor: '#FFF8F0' }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.m }}>
          <View style={{ flexDirection: 'row', alignItems: 'flex-end', gap: espaco.s, backgroundColor: MADEIRA, borderRadius: 14, padding: espaco.s }}>
            <Pressable
              onPress={() => setVerLista((v) => !v)}
              accessibilityRole="button"
              accessibilityLabel={noPrato.length > 0 ? `O teu prato: ${noPrato.map((o) => o.nome.trim()).join(', ')}. Toca para ver a lista` : 'O teu prato está vazio'}>
              <Animated.View
                style={{
                  width: PRATO,
                  height: PRATO,
                  borderRadius: PRATO / 2,
                  backgroundColor: '#fff',
                  borderWidth: 6,
                  borderColor: '#EDEDED',
                  alignItems: 'center',
                  justifyContent: 'center',
                  transform: [{ scale: salto }],
                }}>
                {/* Base à esquerda (metade), proteína e acompanhamentos à direita (um quarto cada) */}
                <View style={{ width: PRATO - 24, height: PRATO - 24, borderRadius: (PRATO - 24) / 2, overflow: 'hidden', flexDirection: 'row', gap: 2 }}>
                  <Zona itens={zonas.base} largura={MEIO - 1} altura={PRATO - 24} rotulo="base" />
                  <View style={{ gap: 2 }}>
                    <Zona itens={zonas.proteina} largura={MEIO - 1} altura={MEIO - 1} rotulo="proteína" />
                    <Zona itens={zonas.acompanhamento} largura={MEIO - 1} altura={MEIO - 1} rotulo="acomp." />
                  </View>
                </View>
              </Animated.View>
            </Pressable>
            {temBebidas &&
              (bebida ? (
                <View accessible accessibilityLabel={`No tabuleiro: ${bebida.nome.trim()}`}>
                  <Bebida tipo={tipoBebida} opcao={bebida} escolhida={false} vazia={false} escala={0.7} />
                </View>
              ) : (
                <View
                  accessible
                  accessibilityLabel="Sem bebida"
                  style={{ width: 44, height: 64, borderRadius: 10, borderWidth: 1.5, borderStyle: 'dashed', borderColor: '#CFCFCF', alignItems: 'center', justifyContent: 'center' }}>
                  <Text style={{ fontSize: 9, color: '#9A9A9A' }}>bebida</Text>
                </View>
              ))}
          </View>
          <View style={{ flex: 1, gap: 4 }}>
            <Text style={{ fontSize: 22, fontWeight: '800', color: cores.texto }}>{formatarKz(p.total)}</Text>
            <Text style={{ fontSize: 12, color: cores.textoSuave }}>
              {todos.length === 0 ? 'o teu prato' : todos.length === 1 ? '1 item' : `${todos.length} itens`}
              {todos.length > 0 ? (verLista ? ' · esconder' : ' · ver') : ''}
            </Text>
            {restam && <Text style={{ fontSize: 12, fontWeight: '700', color: cores.aviso }}>{restam}</Text>}
          </View>
        </View>
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
