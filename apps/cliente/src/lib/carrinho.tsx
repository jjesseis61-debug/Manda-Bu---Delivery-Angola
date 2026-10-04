import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';

import { chaveLinha, precoMontado } from './opcoes';
import type { ComponentePrato, ItemCardapio, OpcaoEscolhida } from './tipos';

/** Uma linha por prato e combinação de opções (I9: o mesmo prato montado de outra forma é outra linha) */
export type LinhaCarrinho = { chave: string; item: ItemCardapio; qtd: number; opcoes: OpcaoEscolhida[]; tirados: ComponentePrato[] };

/** Pedido de grupo em curso (C13): o checkout usa o ponto do grupo em vez do endereço */
export type GrupoCarrinho = { grupoId: string; codigo: string; hora: string; cozinhaId: string; cozinhaNome: string };

/** Cozinha escolhida (I8, com multi_cozinha): o carrinho só tem pratos de uma cozinha */
export type CozinhaCarrinho = { id: string; nome: string };

type Carrinho = {
  linhas: LinhaCarrinho[];
  quantidade: number;
  /** Só para mostrar no cardápio; o valor a pagar vem sempre do orçamento do servidor */
  totalEstimado: number;
  adicionar: (item: ItemCardapio, opcoes?: OpcaoEscolhida[], tirados?: ComponentePrato[]) => void;
  alterar: (chave: string, qtd: number) => void;
  /** Quantas unidades deste prato há no carrinho, com quaisquer opções */
  quantidadeDe: (itemId: string) => number;
  limpar: () => void;
  grupo: GrupoCarrinho | null;
  definirGrupo: (g: GrupoCarrinho | null) => void;
  cozinha: CozinhaCarrinho | null;
  /** Mudar de cozinha esvazia o carrinho (os pratos são de outra cozinha) */
  definirCozinha: (c: CozinhaCarrinho | null) => void;
  /** Cozinha dos pratos a escolher: a do grupo, se houver; senão a escolhida */
  cozinhaActual: CozinhaCarrinho | null;
};

const Contexto = createContext<Carrinho | null>(null);

export function CarrinhoProvider({ children }: { children: ReactNode }) {
  const [linhas, setLinhas] = useState<LinhaCarrinho[]>([]);
  const [grupo, setGrupo] = useState<GrupoCarrinho | null>(null);
  const [cozinha, setCozinha] = useState<CozinhaCarrinho | null>(null);

  const valor = useMemo<Carrinho>(
    () => ({
      linhas,
      quantidade: linhas.reduce((s, l) => s + l.qtd, 0),
      totalEstimado: linhas.reduce((s, l) => s + l.qtd * precoMontado(l.item.preco, l.opcoes, l.tirados), 0),
      adicionar: (item, opcoes = [], tirados = []) =>
        setLinhas((actual) => {
          const chave = chaveLinha(item.id, opcoes, tirados);
          const existe = actual.find((l) => l.chave === chave);
          if (existe) return actual.map((l) => (l.chave === chave ? { ...l, qtd: Math.min(l.qtd + 1, 50) } : l));
          return [...actual, { chave, item, qtd: 1, opcoes, tirados }];
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
      },
      grupo,
      definirGrupo: (g) => {
        // Os pratos do carrinho têm de ser da cozinha do grupo
        if (g && linhas.some((l) => l.item.cozinha_id !== g.cozinhaId)) setLinhas([]);
        setGrupo(g);
      },
      cozinha,
      definirCozinha: (c) => {
        if (c?.id !== cozinha?.id && linhas.length > 0 && !grupo) setLinhas([]);
        setCozinha(c);
      },
      cozinhaActual: grupo ? { id: grupo.cozinhaId, nome: grupo.cozinhaNome } : cozinha,
    }),
    [linhas, grupo, cozinha],
  );

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useCarrinho(): Carrinho {
  const c = useContext(Contexto);
  if (!c) throw new Error('useCarrinho fora de CarrinhoProvider');
  return c;
}
