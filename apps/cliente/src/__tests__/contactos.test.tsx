/// <reference types="jest" />
import { fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';
import { Linking } from 'react-native';

import Contactos from '@/app/contactos';
import { lerContactos } from '@/lib/api';

jest.mock('@/lib/api', () => ({ lerContactos: jest.fn() }));

beforeEach(() => {
  jest.clearAllMocks();
  jest.spyOn(Linking, 'openURL').mockResolvedValue(true);
});

test('contactos: gerais e de cada cozinha, com ligar, WhatsApp e email', async () => {
  (lerContactos as jest.Mock).mockResolvedValue({
    geral: { telefone: '+244 923 000 000', whatsapp: '923000001', email: 'ola@mandabue.ao', horario: 'Seg a Sáb, 8h às 20h', morada: null },
    cozinhas: [{ id: 'k1', nome: 'Cozinha do Kilamba', estado: 'pausada', telefone: '923111222', whatsapp: null, horario: '10h às 22h' }],
  });
  const ecra = renderRouter({ contactos: Contactos }, { initialUrl: '/contactos' });
  await waitFor(() => expect(ecra.getByText('Seg a Sáb, 8h às 20h')).toBeTruthy());
  expect(ecra.getByText('Cozinha do Kilamba (em pausa)')).toBeTruthy();
  expect(ecra.queryByText('Morada')).toBeNull();
  fireEvent.press(ecra.getByText('Ligar +244 923 000 000'));
  expect(Linking.openURL).toHaveBeenCalledWith('tel:+244923000000');
  fireEvent.press(ecra.getByText('WhatsApp'));
  expect(Linking.openURL).toHaveBeenCalledWith('https://wa.me/244923000001');
  fireEvent.press(ecra.getByText('Email ola@mandabue.ao'));
  expect(Linking.openURL).toHaveBeenCalledWith('mailto:ola@mandabue.ao');
  fireEvent.press(ecra.getByText('Ligar 923111222'));
  expect(Linking.openURL).toHaveBeenCalledWith('tel:923111222');
});

test('contactos: sem contactos gerais preenchidos', async () => {
  (lerContactos as jest.Mock).mockResolvedValue({
    geral: { telefone: null, whatsapp: null, email: null, horario: null, morada: null }, cozinhas: [],
  });
  const ecra = renderRouter({ contactos: Contactos }, { initialUrl: '/contactos' });
  await waitFor(() => expect(ecra.getByText('Os contactos gerais ainda não estão disponíveis.')).toBeTruthy());
});
