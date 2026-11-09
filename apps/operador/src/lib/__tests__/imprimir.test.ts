import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';

import { imprimirHtml } from '../exportar';

jest.mock('expo-print', () => ({ printToFileAsync: jest.fn(), printAsync: jest.fn() }));
jest.mock('expo-sharing', () => ({ isAvailableAsync: jest.fn(), shareAsync: jest.fn() }));
jest.mock('expo-file-system', () => ({ File: jest.fn(), Paths: {} }));

const print = Print as jest.Mocked<typeof Print>;
const sharing = Sharing as jest.Mocked<typeof Sharing>;

beforeEach(() => {
  jest.resetAllMocks();
  print.printToFileAsync.mockResolvedValue({ uri: 'file:///talao.pdf', numberOfPages: 1 });
});

test('gera o PDF e manda-o para a janela de impressão', async () => {
  await imprimirHtml('<p>talão</p>');
  expect(print.printAsync).toHaveBeenCalledWith({ uri: 'file:///talao.pdf' });
  expect(sharing.shareAsync).not.toHaveBeenCalled();
});

test('se a impressão directa falhar, abre "Partilhar" com o PDF', async () => {
  print.printAsync.mockRejectedValue(new Error('Cannot find the PrintManager'));
  sharing.isAvailableAsync.mockResolvedValue(true);
  await imprimirHtml('<p>talão</p>');
  expect(sharing.shareAsync).toHaveBeenCalledWith('file:///talao.pdf', expect.objectContaining({ mimeType: 'application/pdf' }));
});

test('cancelar a impressão não é erro', async () => {
  print.printAsync.mockRejectedValue(new Error('Printing did not complete'));
  await expect(imprimirHtml('<p>talão</p>')).resolves.toBeUndefined();
  expect(sharing.shareAsync).not.toHaveBeenCalled();
});

test('sem saída possível, o erro diz o motivo real', async () => {
  print.printAsync.mockRejectedValue(new Error('Cannot find the PrintManager'));
  sharing.isAvailableAsync.mockResolvedValue(false);
  await expect(imprimirHtml('<p>talão</p>')).rejects.toThrow('Não foi possível imprimir: Cannot find the PrintManager');
});
