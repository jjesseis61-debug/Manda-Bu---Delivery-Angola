// Recipientes do balcão e o tabuleiro com o prato servido (balcão, linhas do pedido).
// Tudo desenhado na app, sem imagens para descarregar (Prahalad: poupa dados); a fotografia da comida
// aparece dentro do recipiente, ou o emoji quando não há fotografia.
import { Animated, Image, Pressable, Text, View } from 'react-native';

import type { Recipiente, TipoGrupo } from '@/lib/balcaoPanelas';
import { emojiOpcao } from '@/lib/opcoes';
import { cores } from '@/lib/tema';

/** O que se desenha: o nome (para o emoji) e a fotografia */
export type Desenho = { id: string; nome: string; foto_url?: string | null };

export const TAMANHO = 104;
const MADEIRA = '#F2E6D8';

/** Fotografia (ou emoji, sem fotografia), com o recorte pedido */
export function Comida({ opcao, largura, altura, raioCanto }: { opcao: Desenho; largura: number | `${number}%`; altura: number | `${number}%`; raioCanto: number }) {
  return opcao.foto_url ? (
    <Image source={{ uri: opcao.foto_url }} resizeMode="cover" style={{ width: largura, height: altura, borderRadius: raioCanto }} accessibilityIgnoresInvertColors />
  ) : (
    <View style={{ width: largura, height: altura, borderRadius: raioCanto, backgroundColor: '#FFF8F0', alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ fontSize: typeof altura === 'number' ? Math.max(10, altura * 0.45) : 22 }}>{emojiOpcao(opcao.nome)}</Text>
    </View>
  );
}

/** Copo de sumo ou lata de gasosa, vistos de frente */
export function Bebida({ tipo, opcao, escolhida, vazia, escala = 1 }: { tipo: 'copo' | 'lata'; opcao: Desenho | null; escolhida: boolean; vazia: boolean; escala?: number }) {
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
          borderWidth: escolhida ? 3 : Math.max(1, 2 * escala),
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

/** Forma de cada recipiente visto de cima: largura, altura, cantos e cores */
type Forma = { l: number; a: number; raio: number; fundo: string; aro: string; aroEstilo?: 'solid' | 'dashed'; asas?: string; dentro: [number, number, number] };
const FORMAS: Record<Exclude<Recipiente, 'copo' | 'lata' | 'cartucho' | 'taca' | 'molheira'>, Forma> = {
  panela: { l: 104, a: 104, raio: 52, fundo: '#C9CDD1', aro: '#8D9297', asas: '#3A3A3A', dentro: [78, 78, 39] },
  barro: { l: 104, a: 104, raio: 52, fundo: '#9B5530', aro: '#6E3417', asas: '#5A2A10', dentro: [78, 78, 39] },
  tigela: { l: 104, a: 104, raio: 52, fundo: '#F7F3EE', aro: '#D9D2C8', dentro: [78, 78, 39] },
  saladeira: { l: 104, a: 104, raio: 52, fundo: 'rgba(196,228,238,0.8)', aro: '#8FC1D3', dentro: [80, 80, 40] },
  malga: { l: 96, a: 96, raio: 48, fundo: '#FFF3E0', aro: '#B86B2E', asas: '#B86B2E', dentro: [70, 70, 35] },
  travessa: { l: 128, a: 84, raio: 42, fundo: '#FFFFFF', aro: '#D9D2C8', dentro: [104, 62, 31] },
  cesto: { l: 120, a: 86, raio: 22, fundo: '#C8955A', aro: '#8B5A2B', aroEstilo: 'dashed', dentro: [94, 60, 14] },
  fruteira: { l: 124, a: 84, raio: 42, fundo: '#E6F2DC', aro: '#7FA86A', dentro: [98, 60, 30] },
};

/**
 * Recipiente do balcão com a comida lá dentro (ou vazio, quando hoje não há). escala = 1 no balcão;
 * mais pequeno no tabuleiro.
 */
export function RecipienteDesenhado({ tipo, opcao, escolhida = false, vazia = false, escala = 1 }: { tipo: Recipiente; opcao: Desenho; escolhida?: boolean; vazia?: boolean; escala?: number }) {
  const aro = (cor: string) => (escolhida ? cores.marca : cor);
  const largAro = (escolhida ? 5 : 4) * Math.max(escala, 0.4);
  const vazio = (l: number, a: number, r: number) => (
    <View style={{ width: l, height: a, borderRadius: r, backgroundColor: '#B9BEC3', alignItems: 'center', justifyContent: 'center' }}>
      {escala >= 0.8 && <Text style={{ fontSize: 13, fontWeight: '700', color: '#5F6368' }}>vazia</Text>}
    </View>
  );
  const conteudo = (l: number, a: number, r: number) => (vazia ? vazio(l, a, r) : <Comida opcao={opcao} largura={l} altura={a} raioCanto={r} />);

  if (tipo === 'copo' || tipo === 'lata') {
    return (
      <View style={{ height: TAMANHO * escala, justifyContent: 'center' }}>
        <Bebida tipo={tipo} opcao={opcao} escolhida={escolhida} vazia={vazia} escala={1.05 * escala} />
      </View>
    );
  }

  if (tipo === 'cartucho') {
    // Cartucho de papel às riscas, com as batatas a sair por cima
    const l = 80 * escala;
    return (
      <View style={{ width: l + 8 * escala, height: TAMANHO * escala, alignItems: 'center' }}>
        <View style={{ zIndex: 1 }}>{conteudo(l - 10 * escala, 48 * escala, 18 * escala)}</View>
        <View
          style={{
            marginTop: -12 * escala,
            width: l,
            height: 64 * escala,
            flexDirection: 'row',
            overflow: 'hidden',
            borderBottomLeftRadius: 30 * escala,
            borderBottomRightRadius: 30 * escala,
            borderTopLeftRadius: 4,
            borderTopRightRadius: 4,
            borderWidth: escolhida ? 3 : 1,
            borderColor: aro('#9E1B1B'),
          }}>
          {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => (
            <View key={i} style={{ flex: 1, backgroundColor: i % 2 === 0 ? '#C62828' : '#FFFFFF' }} />
          ))}
        </View>
      </View>
    );
  }

  if (tipo === 'taca') {
    // Taça de sobremesa com pé
    const d = 80 * escala;
    return (
      <View style={{ width: d + 8 * escala, height: TAMANHO * escala, alignItems: 'center', justifyContent: 'flex-end' }}>
        <View style={{ width: d, height: d, borderRadius: d / 2, backgroundColor: '#FFFFFF', borderWidth: largAro, borderColor: aro('#E3BF8F'), alignItems: 'center', justifyContent: 'center' }}>
          {conteudo(d - 18 * escala, d - 18 * escala, (d - 18 * escala) / 2)}
        </View>
        <View style={{ width: 10 * escala, height: 10 * escala, backgroundColor: '#E3BF8F' }} />
        <View style={{ width: 44 * escala, height: 5 * escala, borderRadius: 3, backgroundColor: '#E3BF8F' }} />
      </View>
    );
  }

  if (tipo === 'molheira') {
    // Molheira pequena com bico
    const l = 76 * escala;
    const a = 58 * escala;
    return (
      <View style={{ width: l + 22 * escala, height: TAMANHO * escala, alignItems: 'center', justifyContent: 'center', flexDirection: 'row' }}>
        <View style={{ width: l, height: a, borderRadius: a / 2, backgroundColor: '#FFFFFF', borderWidth: largAro, borderColor: aro('#D9D2C8'), alignItems: 'center', justifyContent: 'center' }}>
          {conteudo(a - 12 * escala, a - 12 * escala, (a - 12 * escala) / 2)}
        </View>
        <View style={{ width: 18 * escala, height: 12 * escala, marginLeft: -4, borderTopRightRadius: 10, borderBottomRightRadius: 4, backgroundColor: '#D9D2C8' }} />
      </View>
    );
  }

  const f = FORMAS[tipo];
  const [dl, da, dr] = f.dentro;
  const asa = 18 * escala;
  return (
    <View style={{ width: f.l * escala + (f.asas ? 20 * escala : 0), height: TAMANHO * escala, alignItems: 'center', justifyContent: 'center' }}>
      {f.asas && (
        <>
          <View style={{ position: 'absolute', left: 0, top: (TAMANHO * escala) / 2 - asa / 2, width: asa, height: asa * 0.9, borderRadius: 6, backgroundColor: f.asas }} />
          <View style={{ position: 'absolute', right: 0, top: (TAMANHO * escala) / 2 - asa / 2, width: asa, height: asa * 0.9, borderRadius: 6, backgroundColor: f.asas }} />
        </>
      )}
      <View
        style={{
          width: f.l * escala,
          height: f.a * escala,
          borderRadius: f.raio * escala,
          backgroundColor: f.fundo,
          borderWidth: largAro,
          borderStyle: escolhida ? 'solid' : (f.aroEstilo ?? 'solid'),
          borderColor: aro(f.aro),
          alignItems: 'center',
          justifyContent: 'center',
        }}>
        {conteudo(dl * escala, da * escala, dr * escala)}
      </View>
    </View>
  );
}

/** Uma zona do prato: as fotografias enchem-na (empilhadas quando há mais do que uma); vazia fica tracejada */
function Zona({ itens, largura, altura, rotulo }: { itens: Desenho[]; largura: number; altura: number; rotulo: string | null }) {
  if (itens.length === 0) {
    return (
      <View
        style={{
          width: largura,
          height: altura,
          borderWidth: rotulo ? 1.5 : 0,
          borderStyle: 'dashed',
          borderColor: '#CFCFCF',
          backgroundColor: rotulo ? 'transparent' : '#F6F6F6',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
        {rotulo && <Text style={{ fontSize: 10, color: '#9A9A9A' }}>{rotulo}</Text>}
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

export type PecaDesenho = Desenho & { recipiente?: Recipiente };

type PropsTabuleiro = {
  zonas: Record<TipoGrupo, PecaDesenho[]>;
  /** Diâmetro do prato principal (150 no balcão, 64 numa linha do pedido) */
  prato: number;
  /** Sítios vazios tracejados (no balcão, para se ver o que falta servir) */
  mostrarVazios?: { bebida: boolean; sobremesa: boolean };
  /** Prato sem opções (prato do dia): a fotografia enche o prato todo */
  inteiro?: Desenho | null;
  aoTocar?: () => void;
  rotuloAcessivel?: string;
  salto?: Animated.Value;
};

/**
 * O tabuleiro: o prato com as zonas (base à esquerda; proteína e acompanhamento à direita), e à volta,
 * cada coisa no seu recipiente pequeno: sopa, pão e molho; o prato de sobremesa; a bebida.
 */
export function Tabuleiro({ zonas, prato, mostrarVazios, inteiro, aoTocar, rotuloAcessivel, salto }: PropsTabuleiro) {
  const k = prato / 150;
  const dentro = prato - 24 * k;
  const meio = dentro / 2;
  const comRotulos = !!mostrarVazios;
  const bebida = zonas.bebida[0] ?? null;
  const tipoBebida: 'copo' | 'lata' = bebida?.recipiente === 'copo' ? 'copo' : 'lata';
  const sobremesaD = prato * 0.42;

  const pratoPrincipal = (
    <Animated.View
      style={{
        width: prato,
        height: prato,
        borderRadius: prato / 2,
        backgroundColor: '#fff',
        borderWidth: Math.max(2, 6 * k),
        borderColor: '#EDEDED',
        alignItems: 'center',
        justifyContent: 'center',
        transform: salto ? [{ scale: salto }] : undefined,
      }}>
      <View style={{ width: dentro, height: dentro, borderRadius: dentro / 2, overflow: 'hidden', flexDirection: 'row', gap: inteiro ? 0 : Math.max(1, 2 * k) }}>
        {inteiro ? (
          <Comida opcao={inteiro} largura={dentro} altura={dentro} raioCanto={dentro / 2} />
        ) : (
          <>
            <Zona itens={zonas.base} largura={meio - 1} altura={dentro} rotulo={comRotulos ? 'base' : null} />
            <View style={{ gap: Math.max(1, 2 * k) }}>
              <Zona itens={zonas.proteina} largura={meio - 1} altura={meio - 1} rotulo={comRotulos ? 'proteína' : null} />
              <Zona itens={zonas.acompanhamento} largura={meio - 1} altura={meio - 1} rotulo={comRotulos ? 'acomp.' : null} />
            </View>
          </>
        )}
      </View>
    </Animated.View>
  );

  const temSobremesa = zonas.sobremesa.length > 0;
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-end', gap: 6 * k + 2, backgroundColor: MADEIRA, borderRadius: 14 * k + 2, padding: 6 * k + 2, flexShrink: 1, flexWrap: 'wrap' }}>
      {aoTocar ? (
        <Pressable onPress={aoTocar} accessibilityRole="button" accessibilityLabel={rotuloAcessivel}>
          {pratoPrincipal}
        </Pressable>
      ) : (
        <View accessible={!!rotuloAcessivel} accessibilityLabel={rotuloAcessivel}>
          {pratoPrincipal}
        </View>
      )}
      {zonas.lado.length > 0 && (
        <View style={{ gap: 4 * k, justifyContent: 'flex-end' }}>
          {zonas.lado.map((o) => (
            <View key={o.id} accessible accessibilityLabel={`Ao lado: ${o.nome.trim()}`}>
              <RecipienteDesenhado tipo={o.recipiente ?? 'malga'} opcao={o} escala={0.42 * k} />
            </View>
          ))}
        </View>
      )}
      {(temSobremesa || mostrarVazios?.sobremesa) &&
        (temSobremesa ? (
          <View
            accessible
            accessibilityLabel={`Sobremesa: ${zonas.sobremesa.map((o) => o.nome.trim()).join(', ')}`}
            style={{ width: sobremesaD, height: sobremesaD, borderRadius: sobremesaD / 2, backgroundColor: '#fff', borderWidth: Math.max(1.5, 4 * k), borderColor: '#EDEDED', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', flexDirection: 'row' }}>
            {zonas.sobremesa.map((o) => (
              <Comida key={o.id} opcao={o} largura={(sobremesaD - 10 * k) / zonas.sobremesa.length} altura={sobremesaD - 10 * k} raioCanto={zonas.sobremesa.length === 1 ? (sobremesaD - 10 * k) / 2 : 0} />
            ))}
          </View>
        ) : (
          <View
            accessible
            accessibilityLabel="Sem sobremesa"
            style={{ width: sobremesaD, height: sobremesaD, borderRadius: sobremesaD / 2, borderWidth: 1.5, borderStyle: 'dashed', borderColor: '#CFCFCF', alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ fontSize: 9, color: '#9A9A9A' }}>sobremesa</Text>
          </View>
        ))}
      {bebida ? (
        <View accessible accessibilityLabel={`No tabuleiro: ${bebida.nome.trim()}`}>
          <Bebida tipo={tipoBebida} opcao={bebida} escolhida={false} vazia={false} escala={0.7 * k} />
        </View>
      ) : (
        mostrarVazios?.bebida && (
          <View
            accessible
            accessibilityLabel="Sem bebida"
            style={{ width: 44 * k, height: 64 * k, borderRadius: 10, borderWidth: 1.5, borderStyle: 'dashed', borderColor: '#CFCFCF', alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ fontSize: 9, color: '#9A9A9A' }}>bebida</Text>
          </View>
        )
      )}
    </View>
  );
}
