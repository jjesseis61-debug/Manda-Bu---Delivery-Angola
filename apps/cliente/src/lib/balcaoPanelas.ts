// Balcão de panelas do «Servir o prato» (grupo B do teste com grupo de controlo).
// Só desenho e textos: as regras de escolha, o preço e a validação continuam em opcoes.ts e no servidor.
import type { ComponentePrato, GrupoOpcoes, Opcao } from './tipos';

export type Recipiente = 'panela' | 'barro' | 'tigela';

const semAcentos = (t: string) =>
  t
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

/**
 * Onde a opção está servida no balcão (Rogers: o que já se vê na cantina e em casa):
 * guisados de panela de barro (feijão, muamba, calulu, kizaka), acompanhamentos de escolha
 * múltipla em tigelas, o resto em panelas de metal.
 */
export function recipienteDaOpcao(grupo: Pick<GrupoOpcoes, 'maximo'>, opcao: Pick<Opcao, 'nome'>): Recipiente {
  if (/feij|muamba|calulu|kizaka|quizaca|moamba|mufete|muteta/.test(semAcentos(opcao.nome))) return 'barro';
  return grupo.maximo > 1 ? 'tigela' : 'panela';
}

export type Passo = { chave: string; titulo: string; grupo: GrupoOpcoes | null };

/** Um passo por grupo, pela ordem da cozinha; no fim «Ingredientes» quando se pode tirar algum */
export function passosDoBalcao(grupos: GrupoOpcoes[], componentes: ComponentePrato[]): Passo[] {
  const passos: Passo[] = grupos.map((g) => ({ chave: g.id, titulo: g.nome, grupo: g }));
  if (componentes.length > 0) passos.push({ chave: 'ingredientes', titulo: 'Ingredientes', grupo: null });
  return passos;
}

/** O passo já tem o que precisa para seguir (o mínimo do grupo; os opcionais estão sempre feitos) */
export function passoFeito(passo: Passo, escolhidas: string[]): boolean {
  if (!passo.grupo) return true;
  return passo.grupo.opcoes.filter((o) => escolhidas.includes(o.id)).length >= passo.grupo.minimo;
}

const primeiraMaiuscula = (t: string) => (t ? t[0].toLocaleUpperCase('pt-PT') + t.slice(1) : t);
const primeiraMinuscula = (t: string) => (t && t.slice(1) !== t.slice(1).toLocaleUpperCase('pt-PT') ? t[0].toLocaleLowerCase('pt-PT') + t.slice(1) : t);

/** «Arroz ou funje?» quando se escolhe uma entre 2 ou 3; senão o nome do grupo («Acompanhamentos») */
export function perguntaDoPasso(passo: Passo): string {
  const g = passo.grupo;
  if (!g) return 'Queres tirar algum ingrediente?';
  const nomes = g.opcoes.map((o) => o.nome.trim());
  if (g.maximo === 1 && nomes.length >= 2 && nomes.length <= 3) {
    const [primeiro, ...resto] = nomes;
    const outros = resto.map(primeiraMinuscula);
    const lista = outros.length === 1 ? outros[0] : `${outros[0]} ou ${outros[1]}`;
    return `${primeiraMaiuscula(primeiro)}${outros.length === 1 ? ' ou ' : ', '}${lista}?`;
  }
  return primeiraMaiuscula(g.nome.trim());
}

/** Dica por baixo da pergunta: o que o gesto faz e quantas se podem tirar (Bandura: um passo de cada vez) */
export function dicaDoPasso(passo: Passo): string {
  const g = passo.grupo;
  if (!g) return 'Toca para tirar o que não queres. O que tiras não pagas.';
  const regra =
    g.maximo === 1
      ? g.minimo === 0
        ? 'Opcional: só uma.'
        : 'Escolhe uma.'
      : g.minimo === 0
        ? `Até ${g.maximo}, se quiseres.`
        : g.minimo === g.maximo
          ? `Escolhe ${g.minimo}.`
          : `De ${g.minimo} a ${g.maximo}.`;
  return `Toca na panela para tirar uma concha. ${regra}`;
}

/**
 * Pratos que restam hoje, só quando são poucos e é verdade (Cialdini: escassez real, nunca inventada).
 * null quando não há contagem, acabou (o ecrã já diz «Esgotado») ou ainda há muitos.
 */
export function textoRestam(restantes: number | null | undefined, limite = 5): string | null {
  if (restantes == null || restantes <= 0 || restantes > limite) return null;
  return restantes === 1 ? 'Resta 1 prato hoje' : `Restam ${restantes} pratos hoje`;
}

/** Título do botão de baixo enquanto não se chega ao último passo */
export function textoSeguinte(passos: Passo[], indice: number, escolhidas: string[]): string {
  const actual = passos[indice];
  if (actual && !passoFeito(actual, escolhidas)) return `Falta: ${actual.titulo.toLocaleLowerCase('pt-PT')}`;
  const proximo = passos[indice + 1];
  return proximo ? `Seguinte: ${proximo.titulo.toLocaleLowerCase('pt-PT')}` : 'Seguinte';
}
