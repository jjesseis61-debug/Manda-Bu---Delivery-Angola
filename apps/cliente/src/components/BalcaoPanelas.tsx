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
  textoSeguinte,
} from '@/lib/balcaoPanelas';
import { formatarKz } from '@/lib/formatar';
import { emojiOpcao } from '@/lib/opcoes';
import { cores, espaco, raio } from '@/lib/tema';
import type { ComponentePrato, GrupoOpcoes, Opcao } from '@/lib/tipos';

const TAMANHO = 80;
const DENTRO = 58;
/** Cor de fundo do balcão (madeira clara) por baixo das panelas */
const MADEIRA = '#F2E6D8';

const ESTILO_RECIPIENTE: Record<Recipiente, { fundo: string; aro: string; asas: string | null }> = {
  panela: { fundo: '#C9CDD1', aro: '#8D9297', asas: '#3A3A3A' },
  barro: { fundo: '#9B5530', aro: '#6E3417', asas: '#5A2A10' },
  tigela: { fundo: '#F7F3EE', aro: '#D9D2C8', asas: null },
};

function Conteudo({ opcao, tamanho }: { opcao: Opcao; tamanho: number }) {
  return opcao.foto_url ? (
    <Image source={{ uri: opcao.foto_url }} style={{ width: tamanho, height: tamanho, borderRadius: tamanho / 2 }} accessibilityIgnoresInvertColors />
  ) : (
    <View style={{ width: tamanho, height: tamanho, borderRadius: tamanho / 2, backgroundColor: '#FFF8F0', alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ fontSize: tamanho * 0.5 }}>{emojiOpcao(opcao.nome)}</Text>
    </View>
  );
}

/** Panela, panela de barro ou tigela vista de cima, com a comida lá dentro (ou vazia, quando hoje não há) */
function Recipiente({ tipo, opcao, escolhida, vazia }: { tipo: Recipiente; opcao: Opcao; escolhida: boolean; vazia: boolean }) {
  const e = ESTILO_RECIPIENTE[tipo];
  return (
    <View style={{ width: TAMANHO + 16, height: TAMANHO, alignItems: 'center', justifyContent: 'center' }}>
      {e.asas && (
        <>
          <View style={{ position: 'absolute', left: 0, top: TAMANHO / 2 - 7, width: 14, height: 14, borderRadius: 5, backgroundColor: e.asas }} />
          <View style={{ position: 'absolute', right: 0, top: TAMANHO / 2 - 7, width: 14, height: 14, borderRadius: 5, backgroundColor: e.asas }} />
        </>
      )}
      <View
        style={{
          width: TAMANHO,
          height: TAMANHO,
          borderRadius: TAMANHO / 2,
          backgroundColor: e.fundo,
          borderWidth: escolhida ? 4 : 3,
          borderColor: escolhida ? cores.marca : e.aro,
          alignItems: 'center',
          justifyContent: 'center',
        }}>
        {vazia ? (
          <View style={{ width: DENTRO, height: DENTRO, borderRadius: DENTRO / 2, backgroundColor: '#B9BEC3', alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: '#5F6368' }}>vazia</Text>
          </View>
        ) : (
          <Conteudo opcao={opcao} tamanho={DENTRO} />
        )}
      </View>
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
 * de cima, e o prato em baixo, sempre à vista, a encher a cada concha com a conta ao lado.
 * As escolhas usam as mesmas regras do ecrã em lista; o servidor valida e calcula o preço.
 */
export function BalcaoPanelas(p: Props) {
  const passos = passosDoBalcao(p.grupos, p.componentes);
  const [indice, setIndice] = useState(0);
  const passo = passos[Math.min(indice, passos.length - 1)];
  const ultimo = indice >= passos.length - 1;
  const escolhidasPorOrdem = p.grupos.flatMap((g) => g.opcoes.filter((o) => p.escolhidas.includes(o.id)));
  const restam = textoRestam(p.restantes);

  // Resposta a cada concha (Skinner): o prato dá um pequeno salto quando recebe comida
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
      Animated.timing(salto, { toValue: 1.08, duration: 120, useNativeDriver: true }),
      Animated.spring(salto, { toValue: 1, friction: 4, useNativeDriver: true }),
    ]).start();
  }, [p.escolhidas.length, semMovimento, salto]);

  if (!passo) return null;
  const feitos = passos.map((x) => passoFeito(x, p.escolhidas));

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }} edges={['bottom', 'left', 'right']}>
      {p.caixas}
      {/* Passos: o feito fica verde, o actual a vermelho; toca-se para voltar atrás */}
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: espaco.xs, paddingHorizontal: espaco.l, paddingTop: espaco.s }}>
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
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: espaco.l, gap: espaco.m, paddingBottom: espaco.xl }}>
        {indice === 0 && p.topo}
        <View style={{ gap: 2 }}>
          <Text style={{ fontSize: 18, fontWeight: '800', color: cores.texto }}>{perguntaDoPasso(passo)}</Text>
          <Text style={{ fontSize: 13, color: cores.textoSuave }}>{dicaDoPasso(passo)}</Text>
        </View>

        {passo.grupo ? (
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', rowGap: espaco.m, backgroundColor: MADEIRA, borderRadius: raio, paddingVertical: espaco.m }}>
            {passo.grupo.opcoes.length === 0 && (passo.grupo.acabaram ?? []).length === 0 && (
              <Text style={{ padding: espaco.m, color: cores.textoSuave }}>Hoje não há nada nesta parte do balcão.</Text>
            )}
            {passo.grupo.opcoes.map((o) => {
              const g = passo.grupo as GrupoOpcoes;
              const escolhida = p.escolhidas.includes(o.id);
              const noGrupo = g.opcoes.filter((x) => p.escolhidas.includes(x.id)).length;
              const cheio = !escolhida && g.maximo > 1 && noGrupo >= g.maximo;
              return (
                <Pressable
                  key={o.id}
                  accessibilityRole={g.maximo === 1 ? 'radio' : 'checkbox'}
                  accessibilityState={{ checked: escolhida, disabled: cheio }}
                  accessibilityHint={escolhida ? 'Toca para devolver à panela' : 'Toca para pôr no prato'}
                  onPress={() => p.aoEscolher(g, o.id)}
                  style={{ width: '33.33%', alignItems: 'center', gap: 2, opacity: cheio ? 0.45 : 1 }}>
                  <Recipiente tipo={recipienteDaOpcao(g, o)} opcao={o} escolhida={escolhida} vazia={false} />
                  <Text style={{ fontSize: 13, fontWeight: '700', color: cores.texto, textAlign: 'center' }} numberOfLines={2}>
                    {o.nome.trim()}
                  </Text>
                  <Text style={{ fontSize: 12, color: cores.textoSuave }}>{o.preco_extra > 0 ? `+${formatarKz(o.preco_extra)}` : 'incluído'}</Text>
                  {escolhida && (
                    <View style={{ backgroundColor: cores.marca, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 1 }}>
                      <Text style={{ color: '#fff', fontSize: 11, fontWeight: '800' }}>🥄 no prato</Text>
                    </View>
                  )}
                </Pressable>
              );
            })}
            {(passo.grupo.acabaram ?? []).map((o) => (
              <View
                key={o.id}
                accessible
                accessibilityLabel={`${o.nome.trim()}: hoje não há`}
                style={{ width: '33.33%', alignItems: 'center', gap: 2 }}>
                <Recipiente tipo={recipienteDaOpcao(passo.grupo as GrupoOpcoes, o)} opcao={o} escolhida={false} vazia />
                <Text style={{ fontSize: 13, fontWeight: '700', color: cores.textoSuave, textAlign: 'center' }} numberOfLines={2}>
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

      {/* O prato, na mão do cliente: enche a cada concha, com a conta ao lado */}
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.m, padding: espaco.m, borderTopWidth: 2, borderTopColor: '#E0D3C3', backgroundColor: '#FFF8F0' }}>
        <Animated.View
          accessible
          accessibilityLabel={escolhidasPorOrdem.length > 0 ? `O teu prato: ${escolhidasPorOrdem.map((o) => o.nome.trim()).join(', ')}` : 'O teu prato está vazio'}
          style={{
            width: 92,
            height: 92,
            borderRadius: 46,
            backgroundColor: '#fff',
            borderWidth: 6,
            borderColor: '#EDEDED',
            alignItems: 'center',
            justifyContent: 'center',
            transform: [{ scale: salto }],
          }}>
          {escolhidasPorOrdem.length === 0 ? (
            <Text style={{ fontSize: 11, color: cores.textoSuave }}>vazio</Text>
          ) : (
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 2, width: 70 }}>
              {escolhidasPorOrdem.slice(0, 6).map((o) => (
                <Conteudo key={o.id} opcao={o} tamanho={escolhidasPorOrdem.length > 4 ? 20 : 26} />
              ))}
            </View>
          )}
        </Animated.View>
        <View style={{ flex: 1, gap: 4 }}>
          <Text style={{ fontSize: 19, fontWeight: '800', color: cores.texto }}>{formatarKz(p.total)}</Text>
          <Text style={{ fontSize: 12, color: cores.textoSuave }} numberOfLines={1}>
            {escolhidasPorOrdem.length > 0 ? escolhidasPorOrdem.map((o) => o.nome.trim().toLocaleLowerCase('pt-PT')).join(' + ') : 'o teu prato'}
          </Text>
          {restam && <Text style={{ fontSize: 12, fontWeight: '700', color: cores.aviso }}>{restam}</Text>}
          {ultimo ? (
            <Botao titulo={p.tituloAdicionar} desactivado={p.adicionarDesactivado} aoCarregar={p.aoAdicionar} />
          ) : (
            <Botao titulo={textoSeguinte(passos, indice, p.escolhidas)} desactivado={!feitos[indice]} aoCarregar={() => setIndice((i) => i + 1)} />
          )}
          {p.rodape}
        </View>
      </View>
    </SafeAreaView>
  );
}
