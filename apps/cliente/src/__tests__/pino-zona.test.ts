/// <reference types="jest" />
import { distanciaKm, moradaComPinoLonge, pinoLongeDaZona, textoFicaA } from '@/lib/pinZona';

const zonas = [
  { id: 'mai', nome: 'Maianga', centro_lat: -8.826442, centro_lng: 13.2284 },
  { id: 'via', nome: 'Vila de Viana', centro_lat: -8.911609, centro_lng: 13.370989 },
  { id: 'nova', nome: 'Bairro sem centro', centro_lat: null, centro_lng: null },
];
// Pino da «Casa · Maianga» de um testador: na verdade está em Viana
const pinoViana = { lat: -8.9417412, lng: 13.3718422 };

test('distância entre o centro da Maianga e o pino em Viana (cerca de 20 km)', () => {
  expect(Math.round(distanciaKm({ lat: -8.826442, lng: 13.2284 }, pinoViana))).toBe(20);
});

test('pino em Viana com o bairro Maianga: pergunta e propõe Vila de Viana', () => {
  const r = pinoLongeDaZona(pinoViana, 'mai', zonas);
  expect(r?.zona).toBe('Maianga');
  expect(r?.maisPerto).toEqual({ id: 'via', nome: 'Vila de Viana' });
  expect(Math.round(r!.km)).toBeGreaterThanOrEqual(15);
});

test('pino no bairro certo, ou bairro sem centro: não pergunta', () => {
  expect(pinoLongeDaZona(pinoViana, 'via', zonas)).toBeNull();
  expect(pinoLongeDaZona(pinoViana, 'nova', zonas)).toBeNull();
});

test('morada com o pino longe do bairro: as distâncias dela não contam', () => {
  const morada = (lat: number, lng: number) => ({
    pontos_entrega: { zona_id: 'mai', lat, lng, zonas: { nome: 'Maianga', centro_lat: -8.826442, centro_lng: 13.2284 } },
  });
  expect(moradaComPinoLonge(morada(pinoViana.lat, pinoViana.lng))).toBe(true);
  expect(moradaComPinoLonge(morada(-8.83, 13.235))).toBe(false);
  expect(moradaComPinoLonge({ pontos_entrega: { zona_id: 'mai', zonas: { nome: 'Maianga' } } })).toBe(false); // sem pino
  expect(moradaComPinoLonge(undefined)).toBe(false);
});

test('«fica ao lado» em vez de «fica a 0,0 km»', () => {
  const km = (n: number) => `${n.toFixed(1).replace('.', ',')} km`;
  expect(textoFicaA(0.02, km)).toBe('fica ao lado');
  expect(textoFicaA(1.24, km)).toBe('fica a 1,2 km');
});
