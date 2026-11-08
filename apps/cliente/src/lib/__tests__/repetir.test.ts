import { montarRepeticao, reverMontado } from '../repetir';
import type { GrupoOpcoes, ItemCardapio, ItemOrcamento } from '../tipos';

const serve: ItemCardapio = {
  id: 'serve', nome: 'Serve o teu próprio prato', descricao: null, categoria: null, preco: 0, foto_url: null, do_dia: false,
  cozinha_id: 'viana', prato_base_id: null, pedidos_mes: 0, minimo_montavel: 500,
} as ItemCardapio;
const sumo: ItemCardapio = { ...serve, id: 'sumo', nome: 'Sumo', preco: 300, minimo_montavel: null };

const grupos: GrupoOpcoes[] = [
  { id: 'g1', cardapio_id: 'serve', nome: 'Base', minimo: 0, maximo: 3, ordem: 1,
    opcoes: [{ id: 'arroz', nome: 'Arroz', preco_extra: 1000, ordem: 1 }] },
  { id: 'g2', cardapio_id: 'serve', nome: 'Acompanhamentos', minimo: 0, maximo: 3, ordem: 2,
    opcoes: [{ id: 'salada', nome: 'Salada', preco_extra: 700, ordem: 1 }] },
];
const pedidoServe = (opcoes: ItemOrcamento['opcoes']): ItemOrcamento => ({
  cardapio_id: 'serve', nome: 'Serve o teu próprio prato', qtd: 1, preco_unitario: 1700, opcoes,
});

describe('reverMontado', () => {
  test('todas as opções ainda há: volta tal e qual', () => {
    const r = reverMontado(serve, grupos, pedidoServe([
      { id: 'arroz', nome: 'Arroz', preco_extra: 1000 }, { id: 'salada', nome: 'Salada', preco_extra: 700 },
    ]));
    expect(r).toEqual({ opcoes: [{ id: 'arroz', nome: 'Arroz', preco_extra: 1000 }, { id: 'salada', nome: 'Salada', preco_extra: 700 }] });
  });

  test('uma opção acabou: vai rever, MESMO acima do mínimo (o arroz sozinho chega aos 500)', () => {
    const r = reverMontado(serve, grupos, pedidoServe([
      { id: 'arroz', nome: 'Arroz', preco_extra: 1000 }, { id: 'frango', nome: 'Frango', preco_extra: 3000 },
    ]));
    expect(r).toEqual({ pendente: { itemId: 'serve', nome: 'Serve o teu próprio prato', qtd: 1, escolhidas: ['arroz'], tirados: [], faltaram: ['Frango'] } });
  });

  test('pedido antigo sem opções gravadas (prato vazio): vai rever em vez de entrar a 0 Kz', () => {
    const r = reverMontado(serve, grupos, pedidoServe(undefined));
    expect('pendente' in r).toBe(true);
  });

  test('ficou abaixo do valor mínimo (regras mudaram): vai rever', () => {
    const barato: GrupoOpcoes[] = [{ ...grupos[1], opcoes: [{ id: 'banana', nome: 'Banana pão', preco_extra: 300, ordem: 1 }] }];
    const r = reverMontado(serve, barato, pedidoServe([{ id: 'banana', nome: 'Banana pão', preco_extra: 300 }]));
    expect(r).toEqual({ pendente: expect.objectContaining({ escolhidas: ['banana'], faltaram: [] }) });
  });
});

jest.mock('../api', () => ({
  lerItemCardapio: jest.fn(async (id: string) => ({ serve: mockServe(), sumo: mockSumo() } as Record<string, unknown>)[id] ?? null),
  lerOpcoes: jest.fn(async () => mockGrupos()),
  lerComponentes: jest.fn(async () => []),
  lerCozinhaPublica: jest.fn(async () => ({ nome: 'Viana' })),
}));
function mockServe() { return serve; }
function mockSumo() { return sumo; }
function mockGrupos() { return grupos; }

describe('montarRepeticao', () => {
  test('separa o que volta ao carrinho, o que vai rever e o que já não existe', async () => {
    const r = await montarRepeticao([
      { cardapio_id: 'sumo', nome: 'Sumo', qtd: 2, preco_unitario: 300 },
      pedidoServe([{ id: 'arroz', nome: 'Arroz', preco_extra: 1000 }, { id: 'frango', nome: 'Frango', preco_extra: 3000 }]),
      { cardapio_id: 'apagado', nome: 'Calulu', qtd: 1, preco_unitario: 2000 },
    ]);
    expect(r.linhas.map((l) => [l.item.id, l.qtd])).toEqual([['sumo', 2]]);
    expect(r.aMontar).toEqual([expect.objectContaining({ itemId: 'serve', faltaram: ['Frango'], escolhidas: ['arroz'] })]);
    expect(r.faltam).toEqual(['Calulu']);
    expect(r.cozinha).toEqual({ id: 'viana', nome: 'Viana' });
  });

  test('prato montado intacto volta com as opções (já não volta vazio)', async () => {
    const r = await montarRepeticao([pedidoServe([{ id: 'salada', nome: 'Salada', preco_extra: 700 }])]);
    expect(r.aMontar).toEqual([]);
    expect(r.linhas[0].opcoes).toEqual([{ id: 'salada', nome: 'Salada', preco_extra: 700 }]);
  });
});
