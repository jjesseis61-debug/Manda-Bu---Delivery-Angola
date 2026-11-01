/// <reference types="jest" />
import AsyncStorage from '@react-native-async-storage/async-storage';

import { mudarEstado } from '../api';
import { enfileirar, lerFila, pedidosNaFila, removerDaFila } from '../filaOffline';
import { semRede, sincronizar } from '../sincronizar';

// Mock da API: controlamos o que mudarEstado faz em cada teste.
jest.mock('../api', () => ({ mudarEstado: jest.fn() }));
const mudarEstadoMock = mudarEstado as jest.MockedFunction<typeof mudarEstado>;

beforeEach(async () => {
  await AsyncStorage.clear();
  mudarEstadoMock.mockReset();
});

describe('fila offline', () => {
  it('enfileira, lê e remove', async () => {
    await enfileirar({ pedido_id: 'p1', tipo: 'em_entrega' });
    await enfileirar({ pedido_id: 'p2', tipo: 'entregue_pago', caixa: 'c1', parcelas: [{ metodo: 'Dinheiro', valor: 6000 }] });
    let fila = await lerFila();
    expect(fila).toHaveLength(2);
    expect((await pedidosNaFila()).has('p2')).toBe(true);
    fila = await removerDaFila(fila[0].id);
    expect(fila).toHaveLength(1);
  });
});

describe('semRede', () => {
  it('reconhece erros de rede', () => {
    expect(semRede({ name: 'TypeError', message: 'Network request failed' })).toBe(true);
    expect(semRede({ message: 'Failed to fetch' })).toBe(true);
    expect(semRede({ name: 'AuthRetryableFetchError', status: 0 })).toBe(true);
  });
  it('não confunde com erro do servidor', () => {
    expect(semRede({ message: 'sem_permissao' })).toBe(false);
    expect(semRede({ message: 'estado_invalido' })).toBe(false);
  });
});

describe('sincronizar', () => {
  it('envia tudo quando há rede e esvazia a fila', async () => {
    await enfileirar({ pedido_id: 'p1', tipo: 'em_entrega' });
    await enfileirar({ pedido_id: 'p2', tipo: 'entregue_pago', caixa: 'c1', parcelas: [{ metodo: 'Dinheiro', valor: 6000 }] });
    mudarEstadoMock.mockResolvedValue(undefined);
    const r = await sincronizar();
    expect(r.feitas).toBe(2);
    expect(r.pendentes).toBe(0);
    expect(await lerFila()).toHaveLength(0);
  });

  it('pára e mantém a fila quando não há rede', async () => {
    await enfileirar({ pedido_id: 'p1', tipo: 'em_entrega' });
    mudarEstadoMock.mockRejectedValue({ name: 'TypeError', message: 'Network request failed' });
    const r = await sincronizar();
    expect(r.feitas).toBe(0);
    expect(r.pendentes).toBe(1); // continua na fila para tentar depois
  });

  it('descarta a acção num erro do servidor (não bloqueia a fila)', async () => {
    await enfileirar({ pedido_id: 'p1', tipo: 'em_entrega' });
    mudarEstadoMock.mockRejectedValue({ message: 'estado_invalido' });
    const r = await sincronizar();
    expect(r.falhadas).toBe(1);
    expect(r.pendentes).toBe(0); // removida para não bloquear
  });
});
