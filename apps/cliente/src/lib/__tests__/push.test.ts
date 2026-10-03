/// <reference types="jest" />
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);
jest.mock('../supabase', () => ({ supabase: {} }));

import { rotaDaNotificacao } from '../push';

describe('rotaDaNotificacao', () => {
  it('abre o ecrã de cada notificação', () => {
    expect(rotaDaNotificacao({ codigo: 'N3' })).toBe('/convida');
    expect(rotaDaNotificacao({ codigo: 'N7' })).toBe('/destaques');
    expect(rotaDaNotificacao({ codigo: 'N8' })).toBe('/levantar');
    expect(rotaDaNotificacao({ codigo: 'N9', pedido_id: 'abc' })).toBe('/avaliar/abc');
    expect(rotaDaNotificacao({ codigo: 'N10', codigo_grupo: 'G-ABC123' })).toBe('/grupo/G-ABC123');
    expect(rotaDaNotificacao({ codigo: 'N11', codigo_grupo: 'G-ABC123' })).toBe('/grupo/G-ABC123');
    expect(rotaDaNotificacao({ codigo: 'N13' })).toBe('/pacotes');
    expect(rotaDaNotificacao({ codigo: 'N16', pedido_id: 'p1' })).toBe('/pedido/p1');
    expect(rotaDaNotificacao({ codigo: 'N16' })).toBeNull();
    expect(rotaDaNotificacao({ codigo: 'N14' })).toBe('/pacotes');
  });

  it('ignora notificações desconhecidas ou sem pedido', () => {
    expect(rotaDaNotificacao({ codigo: 'N9' })).toBeNull();
    expect(rotaDaNotificacao({ codigo: 'N99' })).toBeNull();
    expect(rotaDaNotificacao(undefined)).toBeNull();
  });
});
