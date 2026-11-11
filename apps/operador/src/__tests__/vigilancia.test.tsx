/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import Vigilancia from '@/app/vigilancia';
import { decidirCasoConvida, lerCasosConvida } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerCasosConvida: jest.fn(),
  abrirVigilancia: jest.fn(),
  decidirCasoConvida: jest.fn(),
  vigiarDeNovo: jest.fn(),
  painelVigilancia: jest.fn().mockResolvedValue({
    dias: 14,
    em_verificacao: { n: 2, valor: 780, mais_antigo: '2026-11-09T10:00:00Z' },
    anulados: { n: 3, valor: 1170, por_motivo: [{ motivo: 'mesmo_dispositivo', n: 3, valor: 1170 }] },
    levantamentos: { n: 1, valor: 2500, pedidos: 1, aprovados: 0, mais_antigo: '2026-11-10T10:00:00Z' },
    serie: [
      { dia: '2026-11-10', contas: 1, ligacoes: 0, ganhos: 1, pico: false },
      { dia: '2026-11-11', contas: 8, ligacoes: 6, ganhos: 0, pico: true },
    ],
    medias: { contas: 0.6, ligacoes: 0.4, ganhos: 0.1 },
    topo: [{ cliente_id: 'a', nome: 'Carla', codigo: 'MB-1234', nivel: 'embaixador', ganhos: 4, valor: 2340, indicados: 4, anulados: 0, so_um_pedido: 3 }],
    aparelhos_partilhados: 1,
  }),
  aparelhosPartilhados: jest.fn().mockResolvedValue([
    {
      chave: 'android-xyz', plataforma: 'android', modelo: 'Tecno Spark', contas: 3, ultimo_em: '2026-11-10T10:00:00Z',
      clientes: [
        { cliente_id: 'a', nome: 'Rui', telefone: '923000111', convidado_por: null, pedidos: 2 },
        { cliente_id: 'b', nome: 'Rita', telefone: null, convidado_por: 'Rui', pedidos: 1 },
      ],
    },
  ]),
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

test('mostra os telemóveis com várias contas (só alerta)', async () => {
  (lerCasosConvida as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ vigilancia: Vigilancia }, { initialUrl: '/vigilancia' });
  await waitFor(() => expect(ecra.getByText('Telemóveis com várias contas (1)')).toBeTruthy());
  expect(ecra.getByText(/3 contas · Tecno Spark/)).toBeTruthy();
  expect(ecra.getByText(/convidado por Rui/)).toBeTruthy();
});

test('painel de vigilância: espera, anulados por motivo, levantamentos e picos', async () => {
  (lerCasosConvida as jest.Mock).mockResolvedValue([]);
  const ecra = renderRouter({ vigilancia: Vigilancia }, { initialUrl: '/vigilancia' });
  await waitFor(() => expect(ecra.getByText('Painel de vigilância')).toBeTruthy());
  expect(ecra.getByText('2 · 780 Kz')).toBeTruthy();
  expect(ecra.getByText(/Mesmo telemóvel/)).toBeTruthy();
  expect(ecra.getByText('1 · 2.500 Kz')).toBeTruthy();
  expect(ecra.getByText(/1 dia\(s\) com pico/)).toBeTruthy();
  expect(ecra.getByText(/3 só com 1 pedido/)).toBeTruthy();
});
