import { lerResposta, normalizar, procurarBairros, procurarNoMapa } from '../pesquisaMorada';

const zonas = [
  { id: 'z1', nome: 'Maianga', taxa: 500, centro_lat: -8.83, centro_lng: 13.23 },
  { id: 'z2', nome: 'Viana', taxa: 700, centro_lat: -8.9, centro_lng: 13.37 },
  { id: 'z3', nome: 'Sem centro', taxa: 700, centro_lat: null, centro_lng: null },
];

test('bairros: sem acentos nem maiúsculas, só os que têm centro no mapa', () => {
  expect(normalizar('Viána ')).toBe('viana');
  expect(procurarBairros('maian', zonas).map((r) => r.zonaId)).toEqual(['z1']);
  expect(procurarBairros('VIA', zonas)[0]).toMatchObject({ nome: 'Viana', zonaId: 'z2', lat: -8.9, lng: 13.37 });
  expect(procurarBairros('sem', zonas)).toEqual([]);
  expect(procurarBairros('m', zonas)).toEqual([]);
});

test('resposta do mapa: nome legível, só Angola, sem repetidos', () => {
  const r = lerResposta({
    features: [
      { geometry: { coordinates: [13.24, -8.82] }, properties: { osm_id: 1, name: 'Largo do Kinaxixi', district: 'Ingombota', city: 'Luanda', countrycode: 'AO' } },
      { geometry: { coordinates: [13.24, -8.82] }, properties: { osm_id: 2, name: 'Largo do Kinaxixi', district: 'Ingombota', city: 'Luanda', countrycode: 'AO' } },
      { geometry: { coordinates: [13.25, -8.81] }, properties: { osm_id: 3, street: 'Rua da Missão', housenumber: '12', city: 'Luanda', countrycode: 'AO' } },
      { geometry: { coordinates: [-9.1, 38.7] }, properties: { osm_id: 4, name: 'Rua da Missão', city: 'Lisboa', countrycode: 'PT' } },
      { properties: { name: 'Sem coordenadas' } },
    ],
  });
  expect(r).toHaveLength(2);
  expect(r[0]).toMatchObject({ nome: 'Largo do Kinaxixi', detalhe: 'Ingombota, Luanda', lat: -8.82, lng: 13.24 });
  expect(r[1]).toMatchObject({ nome: 'Rua da Missão 12', detalhe: 'Luanda' });
});

test('pesquisa no mapa: só a partir de 3 letras, limitada a Angola e perto do ponto', async () => {
  const pedidos: string[] = [];
  globalThis.fetch = jest.fn(async (url: string) => {
    pedidos.push(url);
    return { ok: true, json: async () => ({ features: [] }) };
  }) as unknown as typeof fetch;
  expect(await procurarNoMapa('ru')).toEqual([]);
  expect(pedidos).toHaveLength(0);
  await procurarNoMapa('Rua da Missão', { lat: -8.9, lng: 13.37 });
  expect(pedidos[0]).toContain('q=Rua%20da%20Miss%C3%A3o');
  expect(pedidos[0]).toContain('bbox=11.6,-18.1,24.1,-4.3');
  expect(pedidos[0]).toContain('lat=-8.9000&lon=13.3700');
});
