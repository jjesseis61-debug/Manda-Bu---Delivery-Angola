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
  });

  it('ignora notificações desconhecidas ou sem pedido', () => {
    expect(rotaDaNotificacao({ codigo: 'N9' })).toBeNull();
    expect(rotaDaNotificacao({ codigo: 'N99' })).toBeNull();
    expect(rotaDaNotificacao(undefined)).toBeNull();
  });
});
