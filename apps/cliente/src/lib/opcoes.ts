// Regras do prato montável (I9) do lado da app: só para guiar o cliente e mostrar o preço.
// O servidor volta a validar tudo e calcula o preço a pagar (orcamento_pedido).
import type { GrupoOpcoes, OpcaoEscolhida } from './tipos';

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

/** Opções escolhidas pela ordem dos grupos, com o preço extra */
export function opcoesEscolhidas(grupos: GrupoOpcoes[], escolhidas: string[]): OpcaoEscolhida[] {
  return grupos.flatMap((g) =>
    g.opcoes.filter((o) => escolhidas.includes(o.id)).map(({ id, nome, preco_extra }) => ({ id, nome, preco_extra })),
  );
}

export function precoMontado(preco: number, opcoes: OpcaoEscolhida[]): number {
  return preco + opcoes.reduce((s, o) => s + o.preco_extra, 0);
}

/** "Escolhe 1", "Até 2 (opcional)", "De 1 a 3" */
export function regraGrupo(g: GrupoOpcoes): string {
  if (g.minimo === g.maximo) return `Escolhe ${g.minimo}`;
  if (g.minimo === 0) return g.maximo === 1 ? 'Opcional' : `Até ${g.maximo} (opcional)`;
  return `De ${g.minimo} a ${g.maximo}`;
}

/** Duas linhas do carrinho só se juntam se forem o mesmo prato com as mesmas opções */
export function chaveLinha(itemId: string, opcoes: OpcaoEscolhida[]): string {
  return [itemId, ...opcoes.map((o) => o.id).sort()].join('|');
}
