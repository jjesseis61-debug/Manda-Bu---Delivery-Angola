import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';

import { chaveLinha, precoMontado } from './opcoes';
import type { ComponentePrato, ItemCardapio, OpcaoEscolhida } from './tipos';

/** Uma linha por prato e combinação de opções (I9: o mesmo prato montado de outra forma é outra linha) */
export type LinhaCarrinho = { chave: string; item: ItemCardapio; qtd: number; opcoes: OpcaoEscolhida[]; tirados: ComponentePrato[] };

/** Pedido de grupo em curso (C13): o checkout usa o ponto do grupo em vez do endereço */
export type GrupoCarrinho = { grupoId: string; codigo: string; hora: string; cozinhaId: string; cozinhaNome: string };

/** Cozinha escolhida (I8, com multi_cozinha): o carrinho só tem pratos de uma cozinha */
export type CozinhaCarrinho = { id: string; nome: string };

/**
 * "Pedir de novo" de um prato montado que mudou (uma opção acabou, ou já não cumpre as regras):
 * em vez de entrar no carrinho alterado em silêncio, o cliente revê-o no ecrã de montar,
 * já com o que ainda há, e decide (troca a opção, segue sem ela, ou tira o prato).
 */
export type PendenteMontar = {
  itemId: string;
  nome: string;
  qtd: number;
  /** Ids das opções do pedido anterior que ainda estão disponíveis */
  escolhidas: string[];
  /** Ids dos ingredientes que tinha tirado */
  tirados: string[];
  /** Nomes das opções que já não há */
  faltaram: string[];
};

/** Fila do "Pedir de novo": pratos a rever, um de cada vez, e os pratos que ficaram de fora */
export type Repeticao = { fila: PendenteMontar[]; faltam: string[] };

type Carrinho = {
  linhas: LinhaCarrinho[];
  quantidade: number;
  /** Só para mostrar no cardápio; o valor a pagar vem sempre do orçamento do servidor */
  totalEstimado: number;
  adicionar: (item: ItemCardapio, opcoes?: OpcaoEscolhida[], tirados?: ComponentePrato[], qtd?: number) => void;
  alterar: (chave: string, qtd: number) => void;
  /** Quantas unidades deste prato há no carrinho, com quaisquer opções */
  quantidadeDe: (itemId: string) => number;
  limpar: () => void;
  grupo: GrupoCarrinho | null;
  definirGrupo: (g: GrupoCarrinho | null) => void;
  cozinha: CozinhaCarrinho | null;
  /** Mudar de cozinha esvazia o carrinho (os pratos são de outra cozinha) */
  definirCozinha: (c: CozinhaCarrinho | null) => void;
  /** Repõe o carrinho com estas linhas e cozinha (usado por "Pedir de novo") */
  repor: (novas: LinhaCarrinho[], coz: CozinhaCarrinho | null) => void;
  /** Cozinha dos pratos a escolher: a do grupo, se houver; senão a escolhida */
  cozinhaActual: CozinhaCarrinho | null;
  /** "Pedir de novo": pratos montados a rever no ecrã de montar, à vez */
  repeticao: Repeticao | null;
  definirRepeticao: (r: Repeticao | null) => void;
  /** Tira o prato que acabou de ser revisto e devolve o seguinte (ou null quando a fila acaba) */
  avancarFila: () => PendenteMontar | null;
};

const Contexto = createContext<Carrinho | null>(null);

// O carrinho fica guardado 24 h neste telemóvel/navegador: quem chega por um link sem conta
// monta o carrinho, entra (SMS) e encontra-o igual; quem fecha a app a meio também.
// Os preços guardados são só para mostrar: o servidor recalcula tudo no orçamento.
const CHAVE_CARRINHO = 'manda-bue:carrinho';
export const VALIDADE_CARRINHO_MS = 24 * 60 * 60 * 1000;
type CarrinhoGuardado = { em: number; linhas: LinhaCarrinho[]; cozinha: CozinhaCarrinho | null };

/** Carrinho guardado, se ainda dentro do prazo e bem formado */
export function restaurarCarrinho(bruto: string | null, agora = Date.now()): Omit<CarrinhoGuardado, 'em'> | null {
  if (!bruto) return null;
  try {
    const g = JSON.parse(bruto) as CarrinhoGuardado;
    if (typeof g.em !== 'number' || agora - g.em > VALIDADE_CARRINHO_MS || !Array.isArray(g.linhas)) return null;
    const linhas = g.linhas.filter(
      (l) => l && typeof l.chave === 'string' && l.item && typeof l.item.id === 'string' && typeof l.qtd === 'number' && l.qtd > 0,
    );
    if (linhas.length === 0) return null;
    return { linhas, cozinha: g.cozinha && typeof g.cozinha.id === 'string' ? g.cozinha : null };
  } catch {
    return null;
  }
}

export function CarrinhoProvider({ children }: { children: ReactNode }) {
  const [linhas, setLinhas] = useState<LinhaCarrinho[]>([]);
  const [grupo, setGrupo] = useState<GrupoCarrinho | null>(null);
  const [cozinha, setCozinha] = useState<CozinhaCarrinho | null>(null);
  const [repeticao, setRepeticao] = useState<Repeticao | null>(null);
  const lido = useRef(false);
  // O que está guardado (sem a data): repor não renova o prazo de 24 h, só uma mudança renova
  const guardado = useRef<string | null>(null);

  // Ao abrir: repõe o carrinho guardado (se o actual ainda estiver vazio)
  useEffect(() => {
    AsyncStorage.getItem(CHAVE_CARRINHO)
      .then((bruto) => {
        const g = restaurarCarrinho(bruto);
        if (g) {
          guardado.current = JSON.stringify({ linhas: g.linhas, cozinha: g.cozinha });
          setLinhas((actual) => (actual.length > 0 ? actual : g.linhas));
          setCozinha((actual) => actual ?? g.cozinha);
        }
      })
      .catch(() => undefined)
      .finally(() => {
        lido.current = true;
      });
  }, []);

  // Guarda a cada mudança (o pedido de grupo não se guarda: é de um momento)
  useEffect(() => {
    if (!lido.current) return;
    const vazio = linhas.length === 0 || grupo !== null;
    const conteudo = vazio ? null : JSON.stringify({ linhas, cozinha });
    if (conteudo === guardado.current) return;
    guardado.current = conteudo;
    const p = vazio
      ? AsyncStorage.removeItem(CHAVE_CARRINHO)
      : AsyncStorage.setItem(CHAVE_CARRINHO, JSON.stringify({ em: Date.now(), linhas, cozinha } satisfies CarrinhoGuardado));
    p.catch(() => undefined);
  }, [linhas, cozinha, grupo]);

  const valor = useMemo<Carrinho>(
    () => ({
      linhas,
      quantidade: linhas.reduce((s, l) => s + l.qtd, 0),
      totalEstimado: linhas.reduce((s, l) => s + l.qtd * precoMontado(l.item.preco, l.opcoes, l.tirados), 0),
      adicionar: (item, opcoes = [], tirados = [], qtd = 1) =>
        setLinhas((actual) => {
          const chave = chaveLinha(item.id, opcoes, tirados);
          const existe = actual.find((l) => l.chave === chave);
          if (existe) return actual.map((l) => (l.chave === chave ? { ...l, qtd: Math.min(l.qtd + qtd, 50) } : l));
          return [...actual, { chave, item, qtd: Math.min(Math.max(qtd, 1), 50), opcoes, tirados }];
        }),
      alterar: (chave, qtd) =>
        setLinhas((actual) =>
          qtd <= 0
            ? actual.filter((l) => l.chave !== chave)
            : actual.map((l) => (l.chave === chave ? { ...l, qtd: Math.min(qtd, 50) } : l)),
        ),
      quantidadeDe: (itemId) => linhas.filter((l) => l.item.id === itemId).reduce((s, l) => s + l.qtd, 0),
      limpar: () => {
        setLinhas([]);
        setGrupo(null);
        setRepeticao(null);
        // O balcão escolhido não fica preso: no próximo pedido volta a ser o mais perto da morada
        setCozinha(null);
      },
      grupo,
      definirGrupo: (g) => {
        // Os pratos do carrinho têm de ser da cozinha do grupo
        if (g && linhas.some((l) => l.item.cozinha_id !== g.cozinhaId)) setLinhas([]);
        setGrupo(g);
      },
      cozinha,
      definirCozinha: (c) => {
        if (c?.id !== cozinha?.id && linhas.length > 0 && !grupo) {
          setLinhas([]);
          setRepeticao(null); // os pratos por rever eram da outra cozinha
        }
        setCozinha(c);
      },
      cozinhaActual: grupo ? { id: grupo.cozinhaId, nome: grupo.cozinhaNome } : cozinha,
      repor: (novas, coz) => {
        setGrupo(null);
        setCozinha(coz);
        setLinhas(novas);
      },
      repeticao,
      definirRepeticao: setRepeticao,
      avancarFila: () => {
        const resto = repeticao?.fila.slice(1) ?? [];
        setRepeticao(resto.length > 0 && repeticao ? { ...repeticao, fila: resto } : null);
        return resto[0] ?? null;
      },
    }),
    [linhas, grupo, cozinha, repeticao],
  );

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useCarrinho(): Carrinho {
  const c = useContext(Contexto);
  if (!c) throw new Error('useCarrinho fora de CarrinhoProvider');
  return c;
}
