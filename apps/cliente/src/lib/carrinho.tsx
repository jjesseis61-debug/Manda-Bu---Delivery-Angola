import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';

import type { ItemCardapio } from './tipos';

export type LinhaCarrinho = { item: ItemCardapio; qtd: number };

/** Pedido de grupo em curso (C13): o checkout usa o ponto do grupo em vez do endereço */
export type GrupoCarrinho = { grupoId: string; codigo: string; hora: string };

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
};

const Contexto = createContext<Carrinho | null>(null);

export function CarrinhoProvider({ children }: { children: ReactNode }) {
  const [linhas, setLinhas] = useState<LinhaCarrinho[]>([]);
  const [grupo, setGrupo] = useState<GrupoCarrinho | null>(null);

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
      definirGrupo: setGrupo,
    }),
    [linhas, grupo],
  );

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useCarrinho(): Carrinho {
  const c = useContext(Contexto);
  if (!c) throw new Error('useCarrinho fora de CarrinhoProvider');
  return c;
}
