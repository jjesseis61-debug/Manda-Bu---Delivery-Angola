// Balcão de panelas do «Servir o prato» (grupo B do teste com grupo de controlo).
// Só desenho e textos: as regras de escolha, o preço e a validação continuam em opcoes.ts e no servidor.
import type { ComponentePrato, GrupoOpcoes, Opcao } from './tipos';

export type Recipiente = 'panela' | 'barro' | 'tigela' | 'copo' | 'lata';
/** Que parte do prato o grupo enche (as bebidas vão para o tabuleiro, ao lado) */
export type TipoGrupo = 'base' | 'proteina' | 'acompanhamento' | 'bebida';

const semAcentos = (t: string) =>
  t
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

const BEBIDA = /bebid|sumo|refri|gasosa|agua|coca|fanta|sprite|pepsi|batido|cha\b|cafe|cerveja|cuca|nocal|blue/;

/**
 * O tipo vem do nome do grupo (é o que a cozinha escreve: «Base», «Proteína», «Sumo Natural»).
 * Sem pista no nome: escolha única é base, escolha múltipla é acompanhamento.
 */
export function tipoDoGrupo(grupo: Pick<GrupoOpcoes, 'nome' | 'maximo'>): TipoGrupo {
  const n = semAcentos(grupo.nome);
  if (BEBIDA.test(n)) return 'bebida';
  if (/acompanh|guarni|extra|salada|molho|sobremesa/.test(n)) return 'acompanhamento';
  if (/prote|carne|peixe|frango|galinha|marisco/.test(n)) return 'proteina';
  if (/base|arroz|funj|funge|massa|amido|hidrato/.test(n)) return 'base';
  return grupo.maximo > 1 ? 'acompanhamento' : 'base';
}

/**
 * Onde a opção está servida no balcão (Rogers: o que já se vê na cantina e em casa):
 * bebidas em copo (sumo natural) ou lata (gasosa, água); guisados em panela de barro;
 * bases e proteínas em panela; acompanhamentos em tigela.
 */
export function recipienteDaOpcao(grupo: Pick<GrupoOpcoes, 'nome' | 'maximo'>, opcao: Pick<Opcao, 'nome'>): Recipiente {
  const tipo = tipoDoGrupo(grupo);
  const n = semAcentos(opcao.nome);
  if (tipo === 'bebida') return /sumo|batido|natural|cha\b|cafe/.test(n) && !/lata|garrafa/.test(n) ? 'copo' : 'lata';
  if (/feij|muamba|calulu|kizaka|quizaca|moamba|mufete|muteta/.test(n)) return 'barro';
  return tipo === 'acompanhamento' ? 'tigela' : 'panela';
}

export type Passo = { chave: string; titulo: string; grupo: GrupoOpcoes | null; tipo: TipoGrupo | null };

/** Um passo por grupo, pela ordem da cozinha; depois «Ingredientes» (se se pode tirar algum) e as bebidas no fim */
export function passosDoBalcao(grupos: GrupoOpcoes[], componentes: ComponentePrato[]): Passo[] {
  const comida: Passo[] = [];
  const bebidas: Passo[] = [];
  for (const g of grupos) {
    const tipo = tipoDoGrupo(g);
    (tipo === 'bebida' ? bebidas : comida).push({ chave: g.id, titulo: g.nome.trim(), grupo: g, tipo });
  }
  if (componentes.length > 0) comida.push({ chave: 'ingredientes', titulo: 'Ingredientes', grupo: null, tipo: null });
  return [...comida, ...bebidas];
}

/** O passo já tem o que precisa para seguir (o mínimo do grupo; os opcionais estão sempre feitos) */
export function passoFeito(passo: Passo, escolhidas: string[]): boolean {
  if (!passo.grupo) return true;
  return passo.grupo.opcoes.filter((o) => escolhidas.includes(o.id)).length >= passo.grupo.minimo;
}

const primeiraMaiuscula = (t: string) => (t ? t[0].toLocaleUpperCase('pt-PT') + t.slice(1) : t);
const primeiraMinuscula = (t: string) => (t && t.slice(1) !== t.slice(1).toLocaleUpperCase('pt-PT') ? t[0].toLocaleLowerCase('pt-PT') + t.slice(1) : t);

/** «Arroz ou funje?» quando se escolhe uma entre 2 ou 3; senão uma pergunta pelo tipo («E para beber?») */
export function perguntaDoPasso(passo: Passo): string {
  const g = passo.grupo;
  if (!g) return 'Queres tirar algum ingrediente?';
  const nomes = g.opcoes.map((o) => o.nome.trim());
  if (passo.tipo !== 'bebida' && g.maximo === 1 && nomes.length >= 2 && nomes.length <= 3) {
    const [primeiro, ...resto] = nomes;
    const outros = resto.map(primeiraMinuscula);
    const lista = outros.length === 1 ? outros[0] : `${outros[0]} ou ${outros[1]}`;
    return `${primeiraMaiuscula(primeiro)}${outros.length === 1 ? ' ou ' : ', '}${lista}?`;
  }
  switch (passo.tipo) {
    case 'bebida':
      return 'E para beber?';
    case 'base':
      return 'Com que base?';
    case 'proteina':
      return 'Que proteína queres?';
    case 'acompanhamento':
      return 'E para acompanhar?';
    default:
      return primeiraMaiuscula(g.nome.trim());
  }
}

/** Quantas se podem escolher, dito de forma simples */
function regraDoGrupo(g: GrupoOpcoes): string {
  if (g.maximo === 1) return g.minimo === 0 ? 'Só uma, se quiseres.' : 'Escolhe uma.';
  if (g.minimo === 0) return `Até ${g.maximo}, se quiseres.`;
  if (g.minimo === g.maximo) return `Escolhe ${g.minimo}.`;
  return `De ${g.minimo} a ${g.maximo}.`;
}

/** Dica por baixo da pergunta: o gesto certo para o recipiente e a regra (Bandura: um passo de cada vez) */
export function dicaDoPasso(passo: Passo): string {
  const g = passo.grupo;
  if (!g) return 'Toca para tirar o que não queres. O que tiras não pagas.';
  const gesto =
    passo.tipo === 'bebida'
      ? 'Toca para pôr no tabuleiro, ao lado do prato.'
      : passo.tipo === 'acompanhamento'
        ? 'Toca na tigela para servir.'
        : 'Toca na panela para servir uma concha.';
  return `${gesto} ${regraDoGrupo(g)}`;
}

/** Selo de cada opção: «Restam 4» só quando são poucos e é verdade (Cialdini: escassez real, nunca inventada) */
export function textoRestamOpcao(restantes: number | null | undefined, limite = 5): string | null {
  if (restantes == null || restantes <= 0 || restantes > limite) return null;
  return restantes === 1 ? 'Resta 1' : `Restam ${restantes}`;
}

/**
 * Pratos que restam hoje, só quando são poucos e é verdade.
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

/**
 * Opções que acabaram pelo stock (0 unidades) passam para «acabaram»: aparecem vazias e não se escolhem,
 * porque o servidor recusaria o pedido. Igual para a lista e para o balcão.
 */
export function gruposComStock(grupos: GrupoOpcoes[], unidades: Record<string, number>): GrupoOpcoes[] {
  return grupos.map((g) => {
    const sem = g.opcoes.filter((o) => unidades[o.id] === 0);
    if (sem.length === 0) return g;
    return { ...g, opcoes: g.opcoes.filter((o) => unidades[o.id] !== 0), acabaram: [...(g.acabaram ?? []), ...sem] };
  });
}

/** O que vai em cada zona do prato e no tabuleiro, pela ordem dos grupos */
export function zonasDoPrato(grupos: GrupoOpcoes[], escolhidas: string[]): Record<'base' | 'proteina' | 'acompanhamento' | 'bebida', Opcao[]> {
  const zonas: Record<TipoGrupo, Opcao[]> = { base: [], proteina: [], acompanhamento: [], bebida: [] };
  for (const g of grupos) {
    const tipo = tipoDoGrupo(g);
    for (const o of g.opcoes) if (escolhidas.includes(o.id)) zonas[tipo].push(o);
  }
  return zonas;
}
