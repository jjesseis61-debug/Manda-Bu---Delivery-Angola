// Balcão de panelas do «Servir o prato» (grupo B do teste com grupo de controlo).
// Só desenho e textos: as regras de escolha, o preço e a validação continuam em opcoes.ts e no servidor.
import type { ComponentePrato, GrupoOpcoes, Opcao, Recipiente } from './tipos';

export type { Recipiente };
/**
 * Onde vai cada coisa: base, proteína e acompanhamento no prato; sopa, pão e molho ao lado do prato;
 * sobremesa e fruta no prato de sobremesa; bebidas no tabuleiro.
 */
export type TipoGrupo = 'base' | 'proteina' | 'acompanhamento' | 'lado' | 'sobremesa' | 'bebida';

const semAcentos = (t: string) =>
  t
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();

const BEBIDA = /bebid|sumo|refri|gasosa|agua|coca|fanta|sprite|pepsi|batido|cha\b|cafe|cerveja|cuca|nocal|blue/;
const SOBREMESA = /sobremesa|doce|fruta|pudim|mousse|gelado|cocada|bolo/;
const LADO = /sopa|caldo|\bpao\b|\bpaes\b|broa|molho|jindungo|picante|piri/;
const FRUTA = /fruta|banana|papaia|mamao|melancia|ananas|abacaxi|manga|laranja|tangerina|maca\b|uva|melao|goiaba|maracuja/;

/** Recipientes que dizem, por si, onde a comida vai (os outros seguem o nome do grupo) */
const ZONA_DO_RECIPIENTE: Partial<Record<Recipiente, TipoGrupo>> = {
  copo: 'bebida',
  lata: 'bebida',
  taca: 'sobremesa',
  fruteira: 'sobremesa',
  malga: 'lado',
  cesto: 'lado',
  molheira: 'lado',
  travessa: 'proteina',
  saladeira: 'acompanhamento',
  tigela: 'acompanhamento',
};

type GrupoBase = Pick<GrupoOpcoes, 'nome' | 'maximo'> & { recipiente?: Recipiente | null };

/**
 * O tipo vem do recipiente escolhido pela cozinha ou do nome do grupo (é o que a cozinha escreve:
 * «Base», «Proteína», «Sobremesa»). Sem pista: escolha única é base, escolha múltipla é acompanhamento.
 */
export function tipoDoGrupo(grupo: GrupoBase): TipoGrupo {
  const pelo = grupo.recipiente ? ZONA_DO_RECIPIENTE[grupo.recipiente] : undefined;
  if (pelo) return pelo;
  const n = semAcentos(grupo.nome);
  if (BEBIDA.test(n)) return 'bebida';
  if (SOBREMESA.test(n)) return 'sobremesa';
  if (LADO.test(n)) return 'lado';
  if (/acompanh|guarni|extra|salada/.test(n)) return 'acompanhamento';
  if (/prote|carne|peixe|frango|galinha|marisco/.test(n)) return 'proteina';
  if (/base|arroz|funj|funge|massa|amido|hidrato/.test(n)) return 'base';
  return grupo.maximo > 1 ? 'acompanhamento' : 'base';
}

/**
 * Onde a opção está servida no balcão (Rogers: o que já se vê na cantina e em casa). A escolha da
 * cozinha (na opção, ou no grupo) vem primeiro; sem ela, pelo nome: batata frita em cartucho,
 * grelhados em travessa, guisados em panela de barro, salada em saladeira, sopa em malga, pão no cesto,
 * molho na molheira, sobremesa em taça, fruta na fruteira, sumo em copo e gasosa em lata.
 */
export function recipienteDaOpcao(grupo: GrupoBase, opcao: Pick<Opcao, 'nome'> & { recipiente?: Recipiente | null }): Recipiente {
  if (opcao.recipiente) return opcao.recipiente;
  if (grupo.recipiente) return grupo.recipiente;
  const tipo = tipoDoGrupo(grupo);
  const n = semAcentos(opcao.nome);
  if (tipo === 'bebida') return /sumo|batido|natural|cha\b|cafe/.test(n) && !/lata|garrafa/.test(n) ? 'copo' : 'lata';
  if (/batata|mandioca|banana|inhame|chips|fritas/.test(n) && /frit|chips/.test(n)) return 'cartucho';
  if (/feij|muamba|calulu|kizaka|quizaca|moamba|mufete|muteta/.test(n)) return 'barro';
  if (/sopa|caldo/.test(n)) return 'malga';
  if (/\bpao\b|\bpaes\b|broa|pao de/.test(n)) return 'cesto';
  if (/molho|jindungo|piri/.test(n)) return 'molheira';
  if (/salada/.test(n)) return 'saladeira';
  if (tipo === 'sobremesa') return FRUTA.test(n) ? 'fruteira' : 'taca';
  if (/pudim|mousse|gelado|cocada|bolo/.test(n)) return 'taca';
  if (tipo === 'proteina' && /grelh|assad|churras|espetad|frit|brasa/.test(n)) return 'travessa';
  if (tipo === 'lado') return 'tigela';
  return tipo === 'acompanhamento' ? 'tigela' : 'panela';
}

/** Sítio da opção no tabuleiro: o recipiente pode mandá-la para o lado do prato (uma sopa num grupo de acompanhamentos) */
export function zonaDaOpcao(grupo: GrupoBase, opcao: Pick<Opcao, 'nome'> & { recipiente?: Recipiente | null }): TipoGrupo {
  const tipo = tipoDoGrupo(grupo);
  if (tipo === 'bebida') return tipo;
  const r = recipienteDaOpcao(grupo, opcao);
  const z = ZONA_DO_RECIPIENTE[r];
  return z === 'lado' || z === 'sobremesa' || z === 'bebida' ? z : tipo;
}

export type Passo = { chave: string; titulo: string; grupo: GrupoOpcoes | null; tipo: TipoGrupo | null };

const ORDEM: Record<TipoGrupo, number> = { base: 0, proteina: 1, acompanhamento: 2, lado: 3, sobremesa: 5, bebida: 6 };

/**
 * Um passo por grupo, pela ordem de uma refeição: base, proteína, acompanhamentos, o que vai ao lado,
 * «Ingredientes» (se se pode tirar algum), sobremesa e fruta, e as bebidas no fim.
 * Dentro do mesmo tipo fica a ordem da cozinha.
 */
export function passosDoBalcao(grupos: GrupoOpcoes[], componentes: ComponentePrato[]): Passo[] {
  const passos: (Passo & { r: number; i: number })[] = grupos.map((g, i) => {
    const tipo = tipoDoGrupo(g);
    return { chave: g.id, titulo: g.nome.trim(), grupo: g, tipo, r: ORDEM[tipo], i };
  });
  if (componentes.length > 0) passos.push({ chave: 'ingredientes', titulo: 'Ingredientes', grupo: null, tipo: null, r: 4, i: 0 });
  return passos.sort((a, b) => a.r - b.r || a.i - b.i).map(({ r: _r, i: _i, ...p }) => p);
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
  if (passo.tipo !== 'bebida' && passo.tipo !== 'lado' && g.maximo === 1 && nomes.length >= 2 && nomes.length <= 3) {
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
    case 'sobremesa':
      return FRUTA.test(semAcentos(g.nome)) && !/sobremesa|doce/.test(semAcentos(g.nome)) ? 'Uma fruta?' : 'E de sobremesa?';
    case 'lado': {
      const n = semAcentos(g.nome);
      if (/sopa|caldo/.test(n)) return 'Uma sopa?';
      if (/pao|broa/.test(n)) return 'Queres pão?';
      if (/molho|jindungo|piri|picante/.test(n)) return 'Que molho queres?';
      return 'Mais alguma coisa ao lado?';
    }
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
    passo.tipo === 'bebida' || passo.tipo === 'lado'
      ? 'Toca para pôr no tabuleiro, ao lado do prato.'
      : passo.tipo === 'sobremesa'
        ? 'Toca para pôr no prato da sobremesa.'
        : passo.tipo === 'acompanhamento'
          ? 'Toca na tigela para servir.'
          : 'Toca para servir no prato.';
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
export function zonasDoPrato(grupos: GrupoOpcoes[], escolhidas: string[]): Record<TipoGrupo, Opcao[]> {
  const zonas: Record<TipoGrupo, Opcao[]> = { base: [], proteina: [], acompanhamento: [], lado: [], sobremesa: [], bebida: [] };
  for (const g of grupos) for (const o of g.opcoes) if (escolhidas.includes(o.id)) zonas[zonaDaOpcao(g, o)].push(o);
  return zonas;
}

/** Peça do prato para desenhar (no balcão e nas linhas do pedido) */
export type PecaPrato = { id: string; nome: string; foto_url?: string | null; zona: TipoGrupo; recipiente: Recipiente };

/** Opções escolhidas com o sítio no prato e o recipiente (vão com a linha do carrinho) */
export function pecasDoPrato(grupos: GrupoOpcoes[], escolhidas: string[]): PecaPrato[] {
  return grupos.flatMap((g) =>
    g.opcoes
      .filter((o) => escolhidas.includes(o.id))
      .map((o) => ({ id: o.id, nome: o.nome, foto_url: o.foto_url ?? null, zona: zonaDaOpcao(g, o), recipiente: recipienteDaOpcao(g, o) })),
  );
}

/** Agrupa as peças pelas zonas (o prato do carrinho não tem os grupos) */
export function zonasDasPecas<T extends { zona?: TipoGrupo }>(pecas: T[]): Record<TipoGrupo, T[]> {
  const zonas: Record<TipoGrupo, T[]> = { base: [], proteina: [], acompanhamento: [], lado: [], sobremesa: [], bebida: [] };
  for (const p of pecas) zonas[p.zona ?? 'acompanhamento'].push(p);
  return zonas;
}
