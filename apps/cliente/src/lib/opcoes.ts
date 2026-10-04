// Regras do prato montável (I9) do lado da app: só para guiar o cliente e mostrar o preço.
// O servidor volta a validar tudo e calcula o preço a pagar (orcamento_pedido).
import type { ComponentePrato, GrupoOpcoes, OpcaoEscolhida } from './tipos';

/** Escolher uma opção: num grupo de escolha única troca a anterior; nos outros liga/desliga até ao máximo */
export function alternar(grupo: GrupoOpcoes, escolhidas: string[], opcaoId: string): string[] {
  const doGrupo = new Set(grupo.opcoes.map((o) => o.id));
  if (escolhidas.includes(opcaoId)) return escolhidas.filter((id) => id !== opcaoId);
  if (grupo.maximo === 1) return [...escolhidas.filter((id) => !doGrupo.has(id)), opcaoId];
  if (escolhidas.filter((id) => doGrupo.has(id)).length >= grupo.maximo) return escolhidas;
  return [...escolhidas, opcaoId];
}

/** Grupos que ainda não têm o mínimo de escolhas (o botão fica desligado até estarem completos) */
export function gruposEmFalta(grupos: GrupoOpcoes[], escolhidas: string[]): string[] {
  return grupos
    .filter((g) => g.opcoes.filter((o) => escolhidas.includes(o.id)).length < g.minimo)
    .map((g) => g.nome);
}

/**
 * Grupos obrigatórios sem nenhuma opção disponível (ex.: acabaram todas as bases): o prato não se pode montar,
 * porque o servidor recusaria o pedido. A app mostra-o como esgotado em vez de o deixar adicionar.
 */
export function gruposEsgotados(grupos: GrupoOpcoes[]): string[] {
  return grupos.filter((g) => g.minimo > 0 && g.opcoes.length === 0).map((g) => g.nome);
}

/** Opções escolhidas pela ordem dos grupos, com o preço extra */
export function opcoesEscolhidas(grupos: GrupoOpcoes[], escolhidas: string[]): OpcaoEscolhida[] {
  return grupos.flatMap((g) =>
    g.opcoes.filter((o) => escolhidas.includes(o.id)).map(({ id, nome, preco_extra }) => ({ id, nome, preco_extra })),
  );
}

/** Preço do prato montado: prato + extras das opções − valor dos ingredientes tirados (nunca abaixo de 0) */
export function precoMontado(preco: number, opcoes: OpcaoEscolhida[], tirados: ComponentePrato[] = []): number {
  return Math.max(0, preco + opcoes.reduce((s, o) => s + o.preco_extra, 0) - tirados.reduce((s, c) => s + c.valor, 0));
}

/** Preço mais baixo possível: o prato com a opção mais barata de cada grupo obrigatório ("desde ...") */
export function precoMinimo(preco: number, grupos: GrupoOpcoes[]): number {
  return grupos.reduce((total, g) => {
    const baratas = g.opcoes.map((o) => o.preco_extra).sort((a, b) => a - b).slice(0, g.minimo);
    return total + baratas.reduce((s, v) => s + v, 0);
  }, preco);
}

/** "Escolhe 1", "Até 2 (opcional)", "De 1 a 3" */
export function regraGrupo(g: GrupoOpcoes): string {
  if (g.minimo === g.maximo) return `Escolhe ${g.minimo}`;
  if (g.minimo === 0) return g.maximo === 1 ? 'Opcional' : `Até ${g.maximo} (opcional)`;
  return `De ${g.minimo} a ${g.maximo}`;
}

/** Duas linhas do carrinho só se juntam se forem o mesmo prato com as mesmas opções e os mesmos ingredientes tirados */
export function chaveLinha(itemId: string, opcoes: OpcaoEscolhida[], tirados: ComponentePrato[] = []): string {
  return [itemId, ...opcoes.map((o) => o.id).sort(), ...tirados.map((c) => `-${c.produto_id}`).sort()].join('|');
}
