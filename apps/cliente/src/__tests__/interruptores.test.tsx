/// <reference types="jest" />
import { renderRouter } from 'expo-router/testing-library';
import { Text } from 'react-native';

import ComoFunciona from '@/app/como-funciona';
import { useSessao } from '@/lib/sessao';
import type { Parametros } from '@/lib/tipos';

jest.mock('@/lib/sessao', () => ({ useSessao: jest.fn() }));
const mockSessao = useSessao as jest.Mock;

const parametros: Parametros = {
  ganho_por_pedido: 100,
  duracao_dias: 60,
  desconto_indicado: 500,
  limite_verificacao_semanal: 10000,
  levantamento_minimo: 2000,
  limite_parcelamento: 10000,
  contador_minimo: 10,
  tamanho_top: 10,
};

function sessao(carregado: boolean, ligadas: string[]) {
  return { carregado, parametros: carregado ? parametros : null, ligada: (c: string) => ligadas.includes(c) };
}

function abrir() {
  return renderRouter(
    { 'como-funciona': ComoFunciona, inicio: () => <Text>Início</Text> },
    { initialUrl: '/como-funciona' },
  );
}

test('aberto por link, espera pelos interruptores em vez de voltar ao início', () => {
  mockSessao.mockReturnValue(sessao(false, []));
  const ecra = abrir();
  expect(ecra.getPathname()).toBe('/como-funciona');

  expect(ecra.queryByText('Início')).toBeNull();
});

test('depois de carregar, com o interruptor ligado, mostra o ecrã', () => {
  mockSessao.mockReturnValue(sessao(true, ['indicacao']));
  const ecra = abrir();
  expect(ecra.getPathname()).toBe('/como-funciona');
  expect(ecra.getByText(/Ganhas 100/)).toBeTruthy();
});

test('com o interruptor desligado, volta ao início depois de carregar', () => {
  mockSessao.mockReturnValue(sessao(true, []));
  const ecra = abrir();
  expect(ecra.getPathname()).toBe('/inicio');
});
