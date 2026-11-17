/// <reference types="jest" />
jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('../supabase', () => ({ supabase: {} }));

import AsyncStorage from '@react-native-async-storage/async-storage';

import { restaurarCarrinho, VALIDADE_CARRINHO_MS } from '../carrinho';
import { formatarKz } from '../formatar';
import { entregaVisitante, guardarDestino, guardarZonaVisitante, lerDestino, lerZonaVisitante, limparDestino, ordenarCozinhasVisitante, rotuloZona, textoConviteVisitante } from '../visitante';

const linha = { chave: 'm', item: { id: 'm', nome: 'Muamba', preco: 2500 }, qtd: 2, opcoes: [], tirados: [] };

describe('carrinho guardado 24 h', () => {
  const agora = 1_800_000_000_000;
  it('repõe dentro do prazo, com a cozinha', () => {
    const g = restaurarCarrinho(JSON.stringify({ em: agora - 1000, linhas: [linha], cozinha: { id: 'k', nome: 'Viana' } }), agora);
    expect(g?.linhas).toHaveLength(1);
    expect(g?.cozinha).toEqual({ id: 'k', nome: 'Viana' });
  });
  it('passado o prazo, vazio ou estragado: não repõe', () => {
    expect(restaurarCarrinho(JSON.stringify({ em: agora - VALIDADE_CARRINHO_MS - 1, linhas: [linha], cozinha: null }), agora)).toBeNull();
    expect(restaurarCarrinho(JSON.stringify({ em: agora, linhas: [], cozinha: null }), agora)).toBeNull();
    expect(restaurarCarrinho('{isto não é json', agora)).toBeNull();
    expect(restaurarCarrinho(null, agora)).toBeNull();
  });
  it('deita fora linhas mal formadas', () => {
    const g = restaurarCarrinho(JSON.stringify({ em: agora, linhas: [linha, { chave: 'x', qtd: 0 }, null], cozinha: null }), agora);
    expect(g?.linhas).toEqual([linha]);
  });
});

describe('destino depois de entrar', () => {
  beforeEach(() => AsyncStorage.clear());
  it('guarda o carrinho como destino e lê-o até ser limpo', async () => {
    await guardarDestino('/carrinho');
    expect(await lerDestino()).toBe('/carrinho');
    expect(await lerDestino()).toBe('/carrinho');
    await limparDestino();
    expect(await lerDestino()).toBeNull();
  });
  it('passadas 24 h deixa de valer', async () => {
    await guardarDestino('/carrinho');
    expect(await lerDestino(Date.now() + 25 * 60 * 60 * 1000)).toBeNull();
  });
  it('o Convida também é destino (criar conta para ganhar)', async () => {
    await guardarDestino('/convida');
    expect(await lerDestino()).toBe('/convida');
  });
  it('só aceita destinos conhecidos', async () => {
    await AsyncStorage.setItem('manda-bue:depois-de-entrar', JSON.stringify({ destino: '/levantar', em: Date.now() }));
    expect(await lerDestino()).toBeNull();
  });
});

describe('texto do convite', () => {
  it('mostra o desconto e o mínimo', () => {
    expect(textoConviteVisitante({ desconto: 500, minimo: 2000 }, formatarKz)).toBe('🎁 Convite aplicado: −500 Kz no teu 1.º pedido (pedido a partir de 2.000 Kz).');
    expect(textoConviteVisitante({ desconto: 500, minimo: 0 }, formatarKz)).toBe('🎁 Convite aplicado: −500 Kz no teu 1.º pedido.');
    expect(textoConviteVisitante(null, formatarKz)).toBeNull();
  });
});

describe('entrega do bairro', () => {
  const zona = { id: 'z', nome: 'Talatona', taxa: 500, entrega_gratis_acima: 10000 };
  it('soma a taxa e diz quanto falta para ser grátis', () => {
    expect(entregaVisitante(zona, 6000)).toEqual({ taxa: 500, total: 6500, falta: 4000 });
  });
  it('a partir do limiar a entrega é grátis', () => {
    expect(entregaVisitante(zona, 10000)).toEqual({ taxa: 0, total: 10000, falta: null });
  });
  it('sem entrega grátis configurada, nunca falta nada', () => {
    expect(entregaVisitante({ ...zona, entrega_gratis_acima: null }, 50000)).toEqual({ taxa: 500, total: 50500, falta: null });
  });
  it('rótulo do bairro', () => {
    expect(rotuloZona(zona, formatarKz)).toBe('Talatona · entrega 500 Kz');
    expect(rotuloZona({ ...zona, taxa: 0 }, formatarKz)).toBe('Talatona · entrega grátis');
  });
  it('o bairro fica guardado 24 h', async () => {
    await guardarZonaVisitante(zona);
    expect(await lerZonaVisitante()).toEqual(zona);
    expect(await lerZonaVisitante(Date.now() + 25 * 60 * 60 * 1000)).toBeNull();
    await guardarZonaVisitante(null);
    expect(await lerZonaVisitante()).toBeNull();
  });
});

it('cozinhas de um só prato vão para o fim, o resto mantém a ordem (mais perto primeiro)', () => {
  const c = (id: string, pratos: number) => ({ id, nome: id, pratos, distancia_km: null, foto_url: null });
  expect(ordenarCozinhasVisitante([c('a', 1), c('b', 4), c('c', 1), c('d', 2)]).map((x) => x.id)).toEqual(['b', 'd', 'a', 'c']);
});
