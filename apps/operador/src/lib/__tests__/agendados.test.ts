import { agrupar, diaLuanda, estadoAlerta, faltam, horaMinLuanda, instanteLuanda, intervaloDo, linhasCsvAgendados, linkRota, paragensDoMapa, resumoPorZona, linkWhatsapp, listaProducao, nomeDia, comoPedido } from '../agendados';
import type { AgendadoOperador } from '../tipos';

function agendado(over: Partial<AgendadoOperador>): AgendadoOperador {
  return {
    pedido_id: 'a1b2c3d4-0000-0000-0000-000000000000',
    criado_em: '2026-11-11T10:00:00Z',
    agendado_para: '2026-11-12T11:00:00Z',
    estado: 'pendente',
    cozinha_id: 'k1',
    cozinha_nome: 'Viana',
    cliente_nome: 'Ana Maria',
    cliente_telefone: '923000111',
    itens: [],
    subtotal: 2000,
    taxa_entrega: 500,
    desconto_indicacao: 0,
    credito_indicacao_usado: 0,
    pago_pacote: 0,
    valor_empresa: 0,
    a_pagar: 2500,
    observacoes: null,
    ponto_tipo: 'residencial',
    ponto_lat: -8.9,
    ponto_lng: 13.2,
    ponto_referencia: 'Rua 1',
    zona_nome: 'Viana',
    empresa: false,
    grupo: false,
    atribuido_a_nome: null,
    na_fila: false,
    alerta_em: '2026-11-12T08:00:00Z',
    ...over,
  };
}

test('dia e hora de Luanda (UTC+1), também perto da meia-noite', () => {
  expect(diaLuanda('2026-11-11T23:30:00Z')).toBe('2026-11-12');
  expect(horaMinLuanda('2026-11-11T23:30:00Z')).toBe('00:30');
});

test('períodos: hoje, amanhã, 7 dias e datas', () => {
  const agora = new Date('2026-11-11T23:30:00Z'); // já é dia 12 em Luanda
  expect(intervaloDo('hoje', agora)).toEqual({ inicio: '2026-11-12', fim: '2026-11-12' });
  expect(intervaloDo('amanha', agora)).toEqual({ inicio: '2026-11-13', fim: '2026-11-13' });
  expect(intervaloDo('semana', agora)).toEqual({ inicio: '2026-11-12', fim: '2026-11-18' });
  expect(intervaloDo('datas', agora, '2026-11-20')).toEqual({ inicio: '2026-11-20', fim: '2026-11-20' });
  expect(intervaloDo('datas', agora, '2026-11-20', '2026-11-19')).toBeNull();
  expect(intervaloDo('datas', agora, '20/11')).toBeNull();
  expect(nomeDia('2026-11-13', agora)).toBe('Amanhã');
});

test('agrupa por dia e hora com totais', () => {
  const g = agrupar([
    agendado({ pedido_id: '1', agendado_para: '2026-11-12T11:30:00Z', a_pagar: 1000 }),
    agendado({ pedido_id: '2', agendado_para: '2026-11-12T11:00:00Z', a_pagar: 2000 }),
    agendado({ pedido_id: '3', agendado_para: '2026-11-13T09:00:00Z', a_pagar: 500 }),
  ]);
  expect(g).toHaveLength(2);
  expect(g[0].dia).toBe('2026-11-12');
  expect(g[0].horas).toHaveLength(1);
  expect(g[0].horas[0].hora).toBe(12);
  expect(g[0].horas[0].pedidos.map((p) => p.pedido_id)).toEqual(['2', '1']);
  expect(g[0].total).toBe(3000);
  expect(g[1].pedidos).toBe(1);
});

test('lista de produção soma pratos, opções e ingredientes a tirar', () => {
  const l = listaProducao([
    agendado({
      itens: [
        { nome: 'Serve o teu próprio prato (Arroz, Frango; sem cebola)', qtd: 2, preco_unitario: 1500, opcoes: [{ nome: 'Arroz' }, { nome: 'Frango' }], componentes_excluidos: ['x'] },
      ],
    }),
    agendado({
      itens: [
        { nome: 'Serve o teu próprio prato (Arroz)', qtd: 1, preco_unitario: 700, opcoes: [{ nome: 'Arroz' }] },
        { nome: 'Calulu', qtd: 1, preco_unitario: 3000 },
      ],
    }),
  ]);
  expect(l[0]).toEqual({
    prato: 'Serve o teu próprio prato',
    qtd: 3,
    opcoes: [{ nome: 'Arroz', qtd: 3 }, { nome: 'Frango', qtd: 2 }],
    sem: [{ nome: 'cebola', qtd: 2 }],
  });
  expect(l[1]).toEqual({ prato: 'Calulu', qtd: 1, opcoes: [], sem: [] });
});

test('alerta: por confirmar depois da hora do alerta; urgente na fila; nada se confirmado', () => {
  const antes = new Date('2026-11-12T07:59:00Z');
  const depois = new Date('2026-11-12T08:01:00Z');
  expect(estadoAlerta(agendado({}), antes)).toBeNull();
  expect(estadoAlerta(agendado({}), depois)).toBe('por_confirmar');
  expect(estadoAlerta(agendado({ na_fila: true }), depois)).toBe('urgente');
  expect(estadoAlerta(agendado({ na_fila: true, estado: 'confirmado' }), depois)).toBeNull();
});

test('faltam, WhatsApp e talão', () => {
  const agora = new Date('2026-11-12T08:00:00Z');
  expect(faltam('2026-11-12T11:20:00Z', agora)).toBe('faltam 3 h 20 min');
  expect(faltam('2026-11-12T08:45:00Z', agora)).toBe('faltam 45 min');
  expect(faltam('2026-11-12T07:00:00Z', agora)).toBe('já passou a hora');
  expect(linkWhatsapp('923 000 111', 'olá')).toBe('https://wa.me/244923000111?text=ol%C3%A1');
  expect(linkWhatsapp(null, 'x')).toBeNull();
  expect(comoPedido(agendado({})).hora_prometida).toBe('2026-11-12T11:00:00Z');
});

describe('agendados fase 2', () => {
  it('instanteLuanda converte dia e hora de Luanda (UTC+1)', () => {
    expect(instanteLuanda('2026-11-12', '12:30')).toBe('2026-11-12T11:30:00.000Z');
    expect(instanteLuanda('2026-11-12', '25:00')).toBeNull();
    expect(instanteLuanda('12/11/2026', '12:30')).toBeNull();
  });
  it('CSV: cabeçalho e uma linha por pedido', () => {
    const l = linhasCsvAgendados([agendado({ itens: [{ nome: 'Calulu', qtd: 2, preco_unitario: 2000 }] as never })]);
    expect(l[0][0]).toBe('Dia');
    expect(l[1]).toEqual(['2026-11-12', '12:00', 'A1B2C3', 'pendente', 'Viana', 'Ana Maria', '923000111', '2x Calulu', null, 'Rua 1', 'Viana', 2500]);
  });
});

describe('mapa do dia', () => {
  const a1 = agendado({ pedido_id: 'p1', agendado_para: '2026-11-12T12:00:00Z', cliente_nome: 'Ana Maria', zona_nome: 'Viana', ponto_lat: -8.9, ponto_lng: 13.3 });
  const a2 = agendado({ pedido_id: 'p2', agendado_para: '2026-11-12T11:00:00Z', cliente_nome: 'Rui', zona_nome: 'Viana', ponto_lat: -8.8, ponto_lng: 13.2 });
  const semGeo = agendado({ pedido_id: 'p3', ponto_lat: null, ponto_lng: null, zona_nome: 'Talatona' });
  const cancelado = agendado({ pedido_id: 'p4', estado: 'cancelado' });
  it('paragens por hora, só com coordenadas e sem cancelados', () => {
    const p = paragensDoMapa([a1, a2, semGeo, cancelado], new Set(['p1']));
    expect(p.map((x) => x.id)).toEqual(['p2', 'p1']);
    expect(p[0].rotulo).toBe('12:00 · Rui');
    expect(p[1].alerta).toBe(true);
  });
  it('resumo por zona com a primeira e a última hora', () => {
    expect(resumoPorZona([a1, a2, semGeo, cancelado])).toEqual([
      { zona: 'Viana', pedidos: 2, de: '12:00', ate: '13:00' },
      { zona: 'Talatona', pedidos: 1, de: '12:00', ate: '12:00' },
    ]);
  });
  it('rota no Google Maps: paragens por ordem, a última é o destino', () => {
    const url = linkRota(paragensDoMapa([a1, a2]))!;
    expect(url).toContain('destination=-8.9%2C13.3');
    expect(url).toContain('waypoints=-8.8%2C13.2');
    expect(linkRota([])).toBeNull();
  });
});
