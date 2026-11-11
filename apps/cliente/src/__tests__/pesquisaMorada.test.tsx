/// <reference types="jest" />
import { act, fireEvent, render } from '@testing-library/react-native';

import { PesquisaMorada } from '@/components/PesquisaMorada';

const zonas = [{ id: 'z1', nome: 'Maianga', taxa: 500, centro_lat: -8.83, centro_lng: 13.23 }];

beforeEach(() => jest.useFakeTimers());
afterEach(() => jest.useRealTimers());

test('mostra o bairro logo e as ruas do mapa depois de parar de escrever; escolher move o pino', async () => {
  globalThis.fetch = jest.fn(async () => ({
    ok: true,
    json: async () => ({
      features: [
        { geometry: { coordinates: [13.231, -8.832] }, properties: { osm_id: 9, name: 'Rua Major Kanhangulo', district: 'Maianga', city: 'Luanda', countrycode: 'AO' } },
      ],
    }),
  })) as unknown as typeof fetch;
  const aoEscolher = jest.fn();
  const ecra = render(<PesquisaMorada zonas={zonas} aoEscolher={aoEscolher} />);
  fireEvent.changeText(ecra.getByLabelText('Procurar rua, bairro ou sítio conhecido'), 'maia');
  expect(ecra.getByText(/Maianga/)).toBeTruthy();
  expect(globalThis.fetch).not.toHaveBeenCalled(); // ainda a escrever
  await act(async () => {
    jest.advanceTimersByTime(700);
  });
  expect(globalThis.fetch).toHaveBeenCalledTimes(1);
  expect(ecra.getByText('Rua Major Kanhangulo')).toBeTruthy();
  fireEvent.press(ecra.getByText('Rua Major Kanhangulo'));
  expect(aoEscolher).toHaveBeenCalledWith(expect.objectContaining({ lat: -8.832, lng: 13.231 }));
});

test('sem rede: continua a mostrar os bairros e explica', async () => {
  globalThis.fetch = jest.fn(async () => {
    throw new Error('offline');
  }) as unknown as typeof fetch;
  const ecra = render(<PesquisaMorada zonas={zonas} aoEscolher={jest.fn()} />);
  fireEvent.changeText(ecra.getByLabelText('Procurar rua, bairro ou sítio conhecido'), 'maianga');
  await act(async () => {
    jest.advanceTimersByTime(700);
  });
  expect(ecra.getByText(/Maianga/)).toBeTruthy();
  expect(ecra.getByText(/Marca o ponto tocando no mapa/)).toBeTruthy();
});
