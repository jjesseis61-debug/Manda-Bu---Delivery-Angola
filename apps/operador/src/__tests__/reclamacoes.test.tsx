/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Estimulos from '@/app/estimulos';
import Reclamacoes from '@/app/reclamacoes';
import { decidirEstimulo, decidirReclamacao, estimulosDoMes, gerarEstimulos, lerReclamacoes } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerReclamacoes: jest.fn(),
  decidirReclamacao: jest.fn(),
  relatorioReclamacoes: jest.fn(),
  pedirNovaAnalise: jest.fn(),
  gerarEstimulos: jest.fn(),
  estimulosDoMes: jest.fn(),
  decidirEstimulo: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: ['c1'] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const reclamacao = {
  id: 'r1', pedido_id: 'p1', criado_em: '2026-10-03T13:00:00Z', origem: 'avaliacao', estrelas: 1,
  texto: 'Chegou muito tarde e frio', cliente_nome: 'Ana Sousa', cozinha: 'Alexandra', estafeta: 'Rui Mateus', estado: 'aberta',
  ia_estado: 'analisada', ia_categoria: 'atraso', ia_gravidade: 'media', ia_procedente: 'sim',
  ia_fundamento: 'Entregue 75 min depois da hora prometida.', ia_resumo: 'Atraso', ia_accao: 'Rever a saída dos pedidos',
  ia_resposta: 'Pedimos desculpa pelo atraso, Ana.', ia_compensacao: 'desconto', ia_nota: null,
  procedente: null, categoria: null, resposta: null, compensacao: null, compensacao_valor: null, decidido_por: null, decidido_em: null,
  factos: {
    pedido: { feito_as: '2026-10-03 12:00', estado: 'entregue_pago', itens: [{ nome: 'Muamba', qtd: 1 }], total_kz: 3000,
              hora_prometida: '12:45', confirmado_as: '12:05', saiu_as: '13:40', entregue_as: '14:00',
              minutos_de_atraso_na_entrega: 75, minutos_ate_entregar: 120, motivo_cancelamento: null },
    alertas: [{ tipo: 'atraso', minutos: 6, motivo_dado: 'Muitos pedidos' }],
    comprovativo_rejeitado: false,
    cliente: { pedidos_90_dias: 5, reclamacoes_90_dias: 0, reclamacoes_com_razao_90_dias: 0 },
  },
};

beforeEach(() => jest.clearAllMocks());

test('reclamação: factos, análise automática e resposta com a sugestão', async () => {
  (lerReclamacoes as jest.Mock).mockResolvedValue([reclamacao]);
  const ecra = renderRouter({ reclamacoes: Reclamacoes }, { initialUrl: '/reclamacoes' });
  await waitFor(() => expect(ecra.getByText('Chegou muito tarde e frio')).toBeTruthy());
  expect(ecra.getByText(/os factos dão razão ao cliente/)).toBeTruthy();
  fireEvent.press(ecra.getByText('Ver factos e responder'));
  expect(ecra.getByText('Entregue 75 min depois da hora prometida')).toBeTruthy();
  expect(ecra.getByText(/motivo dado: Muitos pedidos/)).toBeTruthy();
  expect(ecra.getByDisplayValue('Pedimos desculpa pelo atraso, Ana.')).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Valor (Kz)'), '1000');
  await act(async () => {
    fireEvent.press(ecra.getByText('Responder ao cliente'));
  });
  expect(decidirReclamacao).toHaveBeenCalledWith('r1', true, 'Pedimos desculpa pelo atraso, Ana.', null, 'desconto', 1000);
  expect(ecra.getByText('Resposta enviada ao cliente.')).toBeTruthy();
});

test('sem análise automática o gerente decide na mesma', async () => {
  (lerReclamacoes as jest.Mock).mockResolvedValue([
    { ...reclamacao, ia_estado: 'indisponivel', ia_procedente: null, ia_resposta: null, ia_compensacao: null,
      ia_nota: 'Análise automática não configurada.' },
  ]);
  const ecra = renderRouter({ reclamacoes: Reclamacoes }, { initialUrl: '/reclamacoes' });
  await waitFor(() => expect(ecra.getByText(/Análise automática indisponível/)).toBeTruthy());
  fireEvent.press(ecra.getByText('Ver factos e responder'));
  fireEvent.press(ecra.getByText('Não'));
  fireEvent.changeText(ecra.getByLabelText('Resposta ao cliente'), 'O pedido saiu a horas, Ana.');
  await act(async () => {
    fireEvent.press(ecra.getByText('Responder ao cliente'));
  });
  expect(decidirReclamacao).toHaveBeenCalledWith('r1', false, 'O pedido saiu a horas, Ana.', null, 'nenhuma', null);
});

const estimulo = {
  id: 'e1', tipo: 'funcionario', nome: 'Rui Mateus', cargo: 'Estafeta',
  metricas: { mes: { entregas: 42, pct_a_horas: 90 }, anterior: { entregas: 36, pct_a_horas: 84 } },
  foco: 'pct_a_horas', conquista: null, modelo: null, meta: { metrica: 'pct_a_horas', valor: 95 },
  meta_anterior: { metrica: 'pct_a_horas', valor: 88, atingida: true },
  mensagem: 'Rui, em Setembro, 90% das tuas 42 entregas chegaram a horas.', ia_estado: 'analisada',
  ia_mensagem: 'Rui, 90% a horas em Setembro: o teu cuidado nota-se.', ia_nota: null, bonus_sugerido: 5000, bonus: null,
  mensagem_final: null, estado: 'proposto', decidido_por: null, decidido_em: null,
};

test('estímulos: gera, mostra a evolução e aprova com bónus e mensagem editada', async () => {
  (gerarEstimulos as jest.Mock).mockResolvedValue(1);
  (estimulosDoMes as jest.Mock).mockResolvedValue([estimulo]);
  const ecra = renderRouter({ estimulos: Estimulos }, { initialUrl: '/estimulos' });
  await act(async () => {
    fireEvent.press(ecra.getByText('Gerar ou actualizar propostas'));
  });
  expect(gerarEstimulos).toHaveBeenCalled();
  expect(ecra.getByText('90%  (antes 84%)')).toBeTruthy();
  expect(ecra.getByText(/Meta do mês anterior: 88 % a horas · atingida/)).toBeTruthy();
  expect(ecra.getByText('Próxima meta: 95% a horas')).toBeTruthy();
  expect(ecra.getByDisplayValue('Rui, 90% a horas em Setembro: o teu cuidado nota-se.')).toBeTruthy();
  expect(ecra.getByDisplayValue('5000')).toBeTruthy();
  fireEvent.changeText(ecra.getByLabelText('Bónus (Kz)'), '6000');
  await act(async () => {
    fireEvent.press(ecra.getByText('Aprovar e enviar'));
  });
  expect(decidirEstimulo).toHaveBeenCalledWith('e1', true, 6000, 'Rui, 90% a horas em Setembro: o teu cuidado nota-se.');
});
