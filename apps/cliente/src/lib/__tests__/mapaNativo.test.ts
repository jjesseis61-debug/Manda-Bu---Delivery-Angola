import { mapaDisponivel } from '../mapaNativo';

describe('mapaDisponivel', () => {
  it('no Android só há mapa com a chave do Google Maps no build', () => {
    expect(mapaDisponivel('android', { mapaGoogle: true })).toBe(true);
    expect(mapaDisponivel('android', { mapaGoogle: false })).toBe(false);
    expect(mapaDisponivel('android', undefined)).toBe(false);
  });

  it('no iOS usa-se o Apple Maps, sem chave', () => {
    expect(mapaDisponivel('ios', undefined)).toBe(true);
  });
});
