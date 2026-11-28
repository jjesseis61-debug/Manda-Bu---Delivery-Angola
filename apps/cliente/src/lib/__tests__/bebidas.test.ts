/// <reference types="jest" />
import { bebidaSugerida, carrinhoTemBebida, eCategoriaBebida, textoBebidaSugerida } from '@/lib/bebidas';
import type { ItemCardapio } from '@/lib/tipos';

const item = (id: string, nome: string, categoria: string | null, preco: number, pedidos_mes = 0, minimo_montavel: number | null = null): ItemCardapio => ({
  id, nome, categoria, preco, pedidos_mes, minimo_montavel, descricao: null, foto_url: null, do_dia: false, cozinha_id: 'k', prato_base_id: null,
});
const linha = (i: ItemCardapio, opcoes: string[] = []) => ({ item: i, opcoes: opcoes.map((n, k) => ({ id: String(k), nome: n, preco_extra: 0 })) });

const muamba = item('m', 'Muamba', 'Pratos', 3500);
const gasosa = item('g', 'Gasosa de laranja', 'Bebidas', 500, 0);
const agua = item('a', 'Água 0,5 l', 'Bebidas', 300, 0);
const cola = item('c', 'Cola', 'Refrigerantes', 600, 12);

test('categorias de bebidas', () => {
  expect(eCategoriaBebida('Bebidas')).toBe(true);
  expect(eCategoriaBebida('Refrigerantes')).toBe(true);
  expect(eCategoriaBebida('Sumos naturais')).toBe(true);
  expect(eCategoriaBebida('Pratos do dia')).toBe(false);
  expect(eCategoriaBebida(null)).toBe(false);
});

test('o carrinho já tem bebida: prato de bebidas ou sumo/gasosa no tabuleiro do prato montado', () => {
  expect(carrinhoTemBebida([linha(muamba)])).toBe(false);
  expect(carrinhoTemBebida([linha(muamba), linha(gasosa)])).toBe(true);
  expect(carrinhoTemBebida([linha(muamba, ['Arroz', 'Sumo de Ananás'])])).toBe(true);
});

test('sugere a mais pedida (prova social verdadeira); em empate a mais barata; nada se já tem bebida', () => {
  expect(bebidaSugerida([muamba, gasosa, agua, cola], [linha(muamba)])?.id).toBe('c');
  expect(bebidaSugerida([muamba, gasosa, agua], [linha(muamba)])?.id).toBe('a');
  expect(bebidaSugerida([muamba, gasosa], [linha(muamba), linha(gasosa)])).toBeNull();
  expect(bebidaSugerida([muamba, gasosa], [])).toBeNull();
  expect(bebidaSugerida([muamba], [linha(muamba)])).toBeNull();
});

test('texto da linha: «a mais pedida» só quando é verdade', () => {
  expect(textoBebidaSugerida(gasosa, '500 Kz')).toBe('Falta a bebida? Gasosa de laranja · 500 Kz');
  expect(textoBebidaSugerida(cola, '600 Kz')).toBe('Falta a bebida? Cola · 600 Kz · a mais pedida');
});
