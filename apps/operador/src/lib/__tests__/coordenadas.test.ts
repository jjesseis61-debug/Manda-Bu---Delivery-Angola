import { extrairCoordenadas, geocodarOnline } from '../coordenadas';

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

describe('geocodarOnline', () => {
  afterEach(() => {
    (globalThis.fetch as jest.Mock | undefined)?.mockReset?.();
  });

  it('lê a primeira resposta do Nominatim', async () => {
    globalThis.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => [{ lat: '-9.0768125', lon: '13.4459375' }],
    }) as unknown as typeof fetch;
    await expect(geocodarOnline('Zango 8 mil')).resolves.toEqual([-9.0768125, 13.4459375]);
  });

  it('devolve null quando não há resultados ou a procura é vazia', async () => {
    globalThis.fetch = jest.fn().mockResolvedValue({ ok: true, json: async () => [] }) as unknown as typeof fetch;
    await expect(geocodarOnline('xpto que não existe')).resolves.toBeNull();
    await expect(geocodarOnline('   ')).resolves.toBeNull();
  });
});
