/// <reference types="jest" />
jest.mock('@react-native-async-storage/async-storage', () => ({
  getItem: jest.fn(),
  setItem: jest.fn(),
}));

import { modoEstafetaInicial } from '../preferencias';

describe('modoEstafetaInicial', () => {
  it('quem não entrega nunca fica em modo estafeta', () => {
    expect(modoEstafetaInicial({ entregar: false, gerir: true, guardado: null, forcado: false })).toBe(false);
    expect(modoEstafetaInicial({ entregar: false, gerir: false, guardado: true, forcado: true })).toBe(false);
  });

  it('o atalho "As minhas entregas" força o modo ligado', () => {
    expect(modoEstafetaInicial({ entregar: true, gerir: true, guardado: false, forcado: true })).toBe(true);
  });

  it('respeita a escolha guardada antes do default', () => {
    expect(modoEstafetaInicial({ entregar: true, gerir: false, guardado: false, forcado: false })).toBe(false);
    expect(modoEstafetaInicial({ entregar: true, gerir: true, guardado: true, forcado: false })).toBe(true);
  });

  it('default: ligado para o estafeta puro, desligado para quem também gere', () => {
    expect(modoEstafetaInicial({ entregar: true, gerir: false, guardado: null, forcado: false })).toBe(true);
    expect(modoEstafetaInicial({ entregar: true, gerir: true, guardado: null, forcado: false })).toBe(false);
  });
});
