/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Vigilancia from '@/app/vigilancia';
import { decidirCasoConvida, lerCasosConvida } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerCasosConvida: jest.fn(),
  abrirVigilancia: jest.fn(),
  decidirCasoConvida: jest.fn(),
  vigiarDeNovo: jest.fn(),
}));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: [] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const caso = {
  id: 'v1', indicador: 'Carla Indicadora', codigo: 'CARLA7', inicio: '2026-09-01', fim: '2026-09-28',
  sinais: { indicados: 4, mesmo_local: 3, telemovel_partilhado: 1, levantamento_para_indicado: 1, so_um_pedido: 3,
            indicados_com_14_dias: 4, maximo_num_dia: 4, ganhos_anulados: 0, ganhos_kz: 400 },
  pontuacao: 16, estado: 'investigado', ia_nota: null, risco: 'alto', resumo: 'Provável rede de contas da mesma família.',
  conclusao: { factos: [{ texto: 'O indicado 4 usou o telemóvel da indicadora.', pedido_id: null }],
               explicacoes_possiveis: ['Família que partilha o telemóvel'], recomendacao: 'Rever os ganhos em verificação.',
               perguntas_ao_funcionario: ['Ligar à indicadora a confirmar quem são os indicados'] },
  passos: [{ ferramenta: 'indicados_do_indicador', entrada: {} }, { ferramenta: 'levantamentos', entrada: {} }],
  investigado_em: '2026-10-03T10:00:00Z', decisao: null, decisao_nota: null, decidido_por: null, decidido_em: null,
  criado_em: '2026-10-03T09:00:00Z',
};

test('vigilância: dossiê do agente, o que confirmar e decisão', async () => {
  (lerCasosConvida as jest.Mock).mockResolvedValue([caso]);
  const ecra = renderRouter({ vigilancia: Vigilancia }, { initialUrl: '/vigilancia' });
  await waitFor(() => expect(ecra.getByText(/Risco alto: Provável rede de contas/)).toBeTruthy());
  expect(ecra.getByText('Carla Indicadora · código CARLA7')).toBeTruthy();
  expect(ecra.getByText(/1 com o mesmo telemóvel · 1 levantamentos para um indicado/)).toBeTruthy();
  fireEvent.press(ecra.getByText('Ver dossiê e decidir'));
  expect(ecra.getByText('O que confirmar')).toBeTruthy();
  expect(ecra.getByText('2. Viu os levantamentos')).toBeTruthy();
  fireEvent.press(ecra.getByText('Suspeita confirmada'));
  fireEvent.changeText(ecra.getByLabelText('Nota (o que se confirmou)'), 'Contas da mesma pessoa. Ganhos anulados.');
  await act(async () => {
    fireEvent.press(ecra.getByText('Guardar decisão'));
  });
  expect(decidirCasoConvida).toHaveBeenCalledWith('v1', 'suspeita_confirmada', 'Contas da mesma pessoa. Ganhos anulados.');
});
