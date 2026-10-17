import { extrairCoordenadas } from '../coordenadas';

describe('extrairCoordenadas', () => {
  it('lê coordenadas soltas coladas do Google Maps', () => {
    expect(extrairCoordenadas('-8.944707, 13.376525')).toEqual([-8.944707, 13.376525]);
    expect(extrairCoordenadas('-8.944707,13.376525')).toEqual([-8.944707, 13.376525]);
  });

  it('lê de um link com ?q=', () => {
    expect(extrairCoordenadas('https://www.google.com/maps/search/?api=1&query=-8.94,13.37')).toEqual([-8.94, 13.37]);
  });

  it('prefere o ponto exacto (!3d!4d) ao centro do mapa (@)', () => {
    const url = 'https://www.google.com/maps/place/X/@-8.90,13.20,17z/data=!3d-8.944707!4d13.376525';
    expect(extrairCoordenadas(url)).toEqual([-8.944707, 13.376525]);
  });

  it('lê de /@lat,lng quando não há ponto exacto', () => {
    expect(extrairCoordenadas('https://www.google.com/maps/@-8.944707,13.376525,15z')).toEqual([-8.944707, 13.376525]);
  });

  it('rejeita texto sem coordenadas e links curtos', () => {
    expect(extrairCoordenadas('')).toBeNull();
    expect(extrairCoordenadas('Vila Chinesa, Viana')).toBeNull();
    expect(extrairCoordenadas('https://maps.app.goo.gl/abc123')).toBeNull();
  });

  it('rejeita valores fora do intervalo', () => {
    expect(extrairCoordenadas('200, 500')).toBeNull();
  });
});
