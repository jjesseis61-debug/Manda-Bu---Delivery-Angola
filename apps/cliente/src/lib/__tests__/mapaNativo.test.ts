import { googleDisponivel } from '../mapaNativo';

describe('googleDisponivel', () => {
  it('no Android o Google Maps só está disponível com a chave no build', () => {
    expect(googleDisponivel('android', { mapaGoogle: true })).toBe(true);
    expect(googleDisponivel('android', { mapaGoogle: false })).toBe(false);
    expect(googleDisponivel('android', undefined)).toBe(false);
  });

  it('no iOS usa-se o Apple Maps, sem chave', () => {
    expect(googleDisponivel('ios', undefined)).toBe(true);
  });

  // Sem Google, a app mostra o OpenStreetMap (grátis); o interruptor `mapa_google` é que decide.
});
