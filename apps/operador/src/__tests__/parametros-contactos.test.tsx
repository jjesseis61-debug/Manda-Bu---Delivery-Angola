/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Parametros from '@/app/parametros';
import { alterarParametros, lerFuncionalidades, lerParametros } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerParametros: jest.fn(),
  lerFuncionalidades: jest.fn(),
  alterarParametros: jest.fn(),
  alterarFuncionalidade: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: [] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

beforeEach(() => {
  jest.clearAllMocks();
  (lerParametros as jest.Mock).mockResolvedValue({
    ...Object.fromEntries(
      [
        'ganho_por_pedido', 'ganho_por_pedido_embaixador', 'ganho_por_pedido_ouro', 'bonus_boas_vindas',
        'duracao_dias', 'desconto_indicado', 'limite_verificacao_semanal',
        'levantamento_minimo', 'limite_parcelamento', 'limiar_embaixador', 'limiar_ouro', 'raio_mesmo_local_m',
        'max_indicados_por_local', 'max_descontos_por_local', 'desconto_subtotal_minimo', 'alerta_contas_por_aparelho', 'tamanho_top',
        'limiar_intervalos', 'tamanho_intervalo', 'pessoas_como_tu_min', 'pessoas_como_tu_max',
        'contador_minimo', 'prazo_avaliacao_dias', 'avaliacoes_minimo', 'tempo_entrega_min',
        'tolerancia_entrega_min', 'alerta_agendado_horas', 'selos_necessarios',
        'despromocao_carencia_dias', 'despromocao_margem_pct',
      ].map((k) => [k, 10]),
    ),
    contacto_telefone: null, contacto_whatsapp: null, contacto_email: null,
    contacto_horario: null, contacto_morada: 'Rua Antiga',
    despromocao_activa: true,
  });
  (lerFuncionalidades as jest.Mock).mockResolvedValue([]);
});

test('parâmetros: valida e guarda os contactos (em branco apaga)', async () => {
  const ecra = renderRouter({ parametros: Parametros }, { initialUrl: '/parametros' });
  await waitFor(() => expect(ecra.getByLabelText('Email')).toBeTruthy());
  fireEvent.changeText(ecra.getByLabelText('Email'), 'sem-arroba');
  expect(ecra.getByText(/Verifica: Email/)).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Email'), ' ola@mandabue.ao ');
  fireEvent.changeText(ecra.getByLabelText('Telefone'), '+244 923 000 000');
  fireEvent.changeText(ecra.getByLabelText('Morada da loja'), '');
  expect(ecra.queryByText(/Verifica:/)).toBeNull();
  fireEvent.press(ecra.getByText('Guardar parâmetros'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Confirmar'));
  });
  expect(alterarParametros).toHaveBeenCalledWith({
    contacto_email: 'ola@mandabue.ao', contacto_telefone: '+244 923 000 000', contacto_morada: null,
  });
});

test('parâmetros: desligar a descida de nível envia um booleano', async () => {
  const ecra = renderRouter({ parametros: Parametros }, { initialUrl: '/parametros' });
  const rotulo = 'Descida suave de nível do embaixador (semanal, um degrau de cada vez)';
  await waitFor(() => expect(ecra.getByLabelText(rotulo)).toBeTruthy());
  fireEvent(ecra.getByLabelText(rotulo), 'valueChange', false);
  fireEvent.press(ecra.getByText('Guardar parâmetros'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Confirmar'));
  });
  expect(alterarParametros).toHaveBeenCalledWith({ despromocao_activa: false });
});
