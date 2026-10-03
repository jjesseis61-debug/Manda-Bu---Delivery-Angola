/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';

import CaixaEcra from '@/app/caixa';
import { abrirCaixa, caixasRecentes, conferirComprovativo, fecharCaixa, lerCozinhas, resumoCaixa } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  caixasRecentes: jest.fn(),
  lerCozinhas: jest.fn(),
  resumoCaixa: jest.fn(),
  abrirCaixa: jest.fn(),
  registarSangria: jest.fn(),
  fecharCaixa: jest.fn(),
  conferirComprovativo: jest.fn(),
}));
jest.mock('@/lib/fotos', () => ({ enderecoComprovativo: jest.fn() }));
const mockSessao = { carregado: true, sessao: {}, funcionario: { id: 'f1', cozinhas_equipa: ['c1'] }, pode: () => true };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const cozinha = { id: 'c1', nome: 'Cozinha da Alexandra' };

test('sem caixa aberta avisa e abre o Balcão com o troco inicial', async () => {
  (caixasRecentes as jest.Mock).mockResolvedValue([]);
  (lerCozinhas as jest.Mock).mockResolvedValue([cozinha]);
  const ecra = renderRouter({ caixa: CaixaEcra }, { initialUrl: '/caixa' });
  await waitFor(() => expect(ecra.getByText('Não há nenhuma caixa aberta.')).toBeTruthy());
  fireEvent.press(ecra.getByText('Abrir caixa'));
  fireEvent.changeText(ecra.getByDisplayValue(''), '5.000 Kz');
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Abrir caixa')[1]);
  });
  expect(abrirCaixa).toHaveBeenCalledWith('c1', 'Balcão', 5000);
});

test('mostra o que deve estar na caixa e fecha com a diferença', async () => {
  (caixasRecentes as jest.Mock).mockResolvedValue([
    { id: 'x1', posto: 'Balcão', data: '2026-10-03', cozinha_id: 'c1', troco_inicial: 5000, funcionario_nome: 'Jesse', fechamento: null },
  ]);
  (lerCozinhas as jest.Mock).mockResolvedValue([cozinha]);
  (resumoCaixa as jest.Mock).mockResolvedValue({
    caixa_id: 'x1', posto: 'Balcão', troco_inicial: 5000, dinheiro_vendas: 2000, pedidos: 1,
    dinheiro_pacotes: 40000, pacotes: 1, sangrias: 1500, lista_sangrias: [], esperado: 45500, aberta_por: 'Jesse',
    electronico: 0, comprovativos: [], por_conferir: 0, rejeitados: 0, valor_rejeitado: 0,
  });
  const ecra = renderRouter({ caixa: CaixaEcra }, { initialUrl: '/caixa' });
  await waitFor(() => expect(ecra.getByText('Deve estar na caixa')).toBeTruthy());
  fireEvent.press(ecra.getByText('Fechar caixa'));
  fireEvent.changeText(ecra.getAllByDisplayValue('')[0], '45000');
  await waitFor(() => expect(ecra.getByText(/Faltam/)).toBeTruthy());
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Fechar caixa')[0]);
  });
  expect(fecharCaixa).toHaveBeenCalledWith('x1', 45000, null);
});

test('pagamentos electrónicos: confere cada um, rejeita com nota e só depois fecha', async () => {
  (caixasRecentes as jest.Mock).mockResolvedValue([
    { id: 'x1', posto: 'Balcão', data: '2026-10-03', cozinha_id: 'c1', troco_inicial: 0, funcionario_nome: 'Jesse', fechamento: null },
  ]);
  (lerCozinhas as jest.Mock).mockResolvedValue([cozinha]);
  const k = (id: string, referencia: string) => ({
    id, pedido_id: 'p-' + id, cliente_nome: 'Ana', metodo: 'Multicaixa Express', valor: 3000, referencia,
    caminho: `p-${id}/1.jpg`, estado: 'por_conferir', nota: null, registado_por: 'Estafeta', criado_em: '2026-10-03T12:00:00Z',
  });
  (resumoCaixa as jest.Mock).mockResolvedValue({
    caixa_id: 'x1', posto: 'Balcão', troco_inicial: 0, dinheiro_vendas: 0, pedidos: 2, dinheiro_pacotes: 0, pacotes: 0,
    sangrias: 0, lista_sangrias: [], esperado: 0, aberta_por: 'Jesse',
    electronico: 6000, comprovativos: [k('k1', 'MCX 4471'), k('k2', 'MCX 4472')], por_conferir: 2, rejeitados: 0, valor_rejeitado: 0,
  });
  const ecra = renderRouter({ caixa: CaixaEcra }, { initialUrl: '/caixa' });
  await waitFor(() => expect(ecra.getByText('Faltam conferir 2.')).toBeTruthy());
  expect(ecra.getByText('Referência: MCX 4471')).toBeTruthy();
  await act(async () => {
    fireEvent.press(ecra.getAllByText('Confere')[0]);
  });
  expect(conferirComprovativo).toHaveBeenCalledWith('k1', true);
  fireEvent.press(ecra.getAllByText('Rejeitar…')[1]);
  fireEvent.changeText(ecra.getAllByDisplayValue('')[0], 'Não aparece no extracto');
  await act(async () => {
    fireEvent.press(ecra.getByText('Rejeitar pagamento'));
  });
  expect(conferirComprovativo).toHaveBeenCalledWith('k2', false, 'Não aparece no extracto');
  // com pagamentos por conferir o fecho fica bloqueado
  fireEvent.press(ecra.getByText('Fechar caixa'));
  expect(ecra.getByText('Confere os pagamentos electrónicos antes de fechar a caixa.')).toBeTruthy();
});
