/// <reference types="jest" />
jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
jest.mock('../supabase', () => ({ supabase: {} }));

import AsyncStorage from '@react-native-async-storage/async-storage';

import { restaurarCarrinho, VALIDADE_CARRINHO_MS } from '../carrinho';
import { formatarKz } from '../formatar';
import { guardarDestino, lerDestino, limparDestino, textoConviteVisitante } from '../visitante';

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
