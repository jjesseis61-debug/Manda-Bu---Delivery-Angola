/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import OtpCodigos from '@/app/otp-codigos';
import { lerFuncionalidades, otpLimpar, otpMarcarEntregue, otpPendentes } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  otpPendentes: jest.fn(),
  otpMarcarEntregue: jest.fn().mockResolvedValue(undefined),
  otpLimpar: jest.fn().mockResolvedValue(undefined),
  lerFuncionalidades: jest.fn(),
}));
jest.mock('@/lib/sessao', () => ({
  useSessao: () => ({ carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: [] }, pode: () => true }),
}));

const pendente = () => ({
  id: 'o1',
  telefone: '+244924000111',
  codigo: '123456',
  criado_em: new Date().toISOString(),
  expira_em: new Date(Date.now() + 600000).toISOString(),
});

beforeEach(() => {
  jest.clearAllMocks();
  (lerFuncionalidades as jest.Mock).mockResolvedValue([{ chave: 'otp_manual', activa: true }]);
  (otpPendentes as jest.Mock).mockResolvedValue([pendente()]);
});

test('mostra o código pendente e o número', async () => {
  const ecra = renderRouter({ 'otp-codigos': OtpCodigos }, { initialUrl: '/otp-codigos' });
  await waitFor(() => expect(ecra.getByText('123456')).toBeTruthy());
  expect(ecra.getByText('+244924000111')).toBeTruthy();
  expect(ecra.getByText('WhatsApp')).toBeTruthy();
});

test('marcar como entregue chama o servidor com o id', async () => {
  const ecra = renderRouter({ 'otp-codigos': OtpCodigos }, { initialUrl: '/otp-codigos' });
  await waitFor(() => expect(ecra.getByText('123456')).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getByText('Marcar como entregue'));
  });
  expect(otpMarcarEntregue).toHaveBeenCalledWith('o1');
});

test('avisa quando o serviço está desligado', async () => {
  (lerFuncionalidades as jest.Mock).mockResolvedValue([{ chave: 'otp_manual', activa: false }]);
  (otpPendentes as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ 'otp-codigos': OtpCodigos }, { initialUrl: '/otp-codigos' });
  await waitFor(() => expect(ecra.getByText(/serviço de OTP manual está desligado/)).toBeTruthy());
});
