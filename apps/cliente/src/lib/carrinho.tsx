import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';

import type { ItemCardapio } from './tipos';

export type LinhaCarrinho = { item: ItemCardapio; qtd: number };

/** Pedido de grupo em curso (C13): o checkout usa o ponto do grupo em vez do endereço */
export type GrupoCarrinho = { grupoId: string; codigo: string; hora: string; cozinhaId: string; cozinhaNome: string };

/** Cozinha escolhida (I8, com multi_cozinha): o carrinho só tem pratos de uma cozinha */
export type CozinhaCarrinho = { id: string; nome: string };

type Carrinho = {
  linhas: LinhaCarrinho[];
  quantidade: number;
  /** Só para mostrar no cardápio; o valor a pagar vem sempre do orçamento do servidor */
  totalEstimado: number;
  adicionar: (item: ItemCardapio) => void;
  alterar: (itemId: string, qtd: number) => void;
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
      totalEstimado: linhas.reduce((s, l) => s + l.qtd * l.item.preco, 0),
      adicionar: (item) =>
        setLinhas((actual) => {
          const existe = actual.find((l) => l.item.id === item.id);
          if (existe) return actual.map((l) => (l.item.id === item.id ? { ...l, qtd: Math.min(l.qtd + 1, 50) } : l));
          return [...actual, { item, qtd: 1 }];
        }),
      alterar: (itemId, qtd) =>
        setLinhas((actual) =>
          qtd <= 0
            ? actual.filter((l) => l.item.id !== itemId)
            : actual.map((l) => (l.item.id === itemId ? { ...l, qtd: Math.min(qtd, 50) } : l)),
        ),
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
