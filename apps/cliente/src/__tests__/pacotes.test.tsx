/// <reference types="jest" />
import { act, fireEvent, renderRouter, waitFor } from 'expo-router/testing-library';
import { Text } from 'react-native';

import Pacotes from '@/app/pacotes';
import { aderirPacote, lerPacotes, meuPacote, pacotesAMinhaVolta } from '@/lib/api';

jest.mock('@/lib/api', () => ({
  lerPacotes: jest.fn(),
  meuPacote: jest.fn(),
  pacotesAMinhaVolta: jest.fn(),
  aderirPacote: jest.fn(),
  cancelarAdesaoPacote: jest.fn(),
  pausarPacote: jest.fn(),
}));
let mockLigada = true;
// Função estável, como na app (senão o ecrã voltava a carregar a cada render)
const mockSessao = { carregado: true, ligada: () => mockLigada };
jest.mock('@/lib/sessao', () => ({ useSessao: () => mockSessao }));

const almoco = {
  id: 'p1',
  nome: 'Almoço do Mês',
  descricao: null,
  refeicoes: 20,
  refeicoes_oferta: 2,
  valor_refeicao: 2500,
  preco: 50000,
  validade_dias: 30,
  pausa_max_dias: 5,
  entrega_gratis: true,
};

function abrir() {
  return renderRouter({ pacotes: Pacotes, inicio: () => <Text>Início</Text> }, { initialUrl: '/pacotes' });
}

beforeEach(() => {
  mockLigada = true;
  (lerPacotes as jest.Mock).mockResolvedValue([almoco]);
  (pacotesAMinhaVolta as jest.Mock).mockResolvedValue({ no_meu_local: 4, na_minha_zona: 12, poupanca_media_mes: 4200 });
});

test('mostra os benefícios e a prova social, e adere com o método escolhido', async () => {
  let aderiu = false;
  (meuPacote as jest.Mock).mockImplementation(async () =>
    aderiu ? { adesao_id: 'a1', pacote: 'Almoço do Mês', estado: 'pendente', metodo: 'unitel_money', preco: 50000 } : null,
  );
  (aderirPacote as jest.Mock).mockImplementation(async () => {
    aderiu = true;
    return 'a1';
  });
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('Almoço do Mês')).toBeTruthy());
  expect(ecra.getByText(/22 refeições: 20 \+ 2 de oferta/)).toBeTruthy();
  expect(ecra.getByText(/Poupas 5.000 Kz/)).toBeTruthy();
  expect(ecra.getByText(/4 colegas do teu local de trabalho/)).toBeTruthy();

  fireEvent.press(ecra.getByText('Unitel Money'));
  await act(async () => {
    fireEvent.press(ecra.getByText('Aderir com Unitel Money'));
  });
  expect(aderirPacote).toHaveBeenCalledWith('p1', 'unitel_money');
  expect(ecra.getByText(/à espera do pagamento/)).toBeTruthy();
});

test('pacote em curso: refeições por usar e validade', async () => {
  (meuPacote as jest.Mock).mockResolvedValue({
    adesao_id: 'a1', pacote: 'Almoço do Mês', estado: 'activa', metodo: 'loja', refeicoes_total: 22,
    refeicoes_restantes: 15, preco: 50000, entrega_gratis: true, inicio: '2026-10-01', fim: '2026-10-30',
    pausa_restante: 5, em_vigor: true, poupanca: 1500,
  });
  const ecra = abrir();
  await waitFor(() => expect(ecra.getByText('15 refeições')).toBeTruthy());
  expect(ecra.getByText('Pausar 1 dia')).toBeTruthy();
  expect(ecra.queryByText(/Aderir com/)).toBeNull();
});

test('com o interruptor desligado volta ao início', () => {
  mockLigada = false;
  const ecra = abrir();
  expect(ecra.getPathname()).toBe('/inicio');
});
