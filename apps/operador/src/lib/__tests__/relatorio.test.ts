import { avaliarCmv, margemPct, htmlRelatorio, indicadores, linhasCsvRelatorio, periodoRel, quemPagaConvida, variacao, type RelatorioDetalhado, type ResumoCozinha } from '../relatorio';

const resumo = (over: Partial<ResumoCozinha> = {}): ResumoCozinha => ({
  pedidos: 2, vendas_brutas: 6000, desconto_convite: 500, saldo_convida: 0, descontos: 500, vendas_liquidas: 5500,
  pago_pacote: 0, valor_empresa: 0, taxas_entrega: 1000, ticket_medio: 3000, cancelados: 1, cancelados_valor: 3000,
  cancelados_cliente: 0, cancelados_cozinha: 1, clientes: 2, clientes_novos: 2, avaliacao_media: 4.5, avaliacoes: 2,
  a_horas_pct: 100, comissao_percent: 10, comissao: 600, a_receber_cozinha: 5400, ...over,
});

const rel: RelatorioDetalhado = {
  cozinha: 'Viana', inicio: '2026-11-01', fim: '2026-11-11',
  resumo: resumo(), anterior: resumo({ pedidos: 1, vendas_brutas: 4000, a_receber_cozinha: 3600, ticket_medio: 4000 }),
  por_dia: [{ dia: '2026-11-10', pedidos: 1, vendas: 2000 }, { dia: '2026-11-11', pedidos: 1, vendas: 4000 }],
  por_hora: [{ hora: 12, pedidos: 2, vendas: 6000 }], por_dia_semana: null,
  pratos: [{ cardapio_id: 'c', nome: 'Calulu <b>', qtd: 3, receita: 6000, pct: 100 }],
  opcoes_montados: [], montado_valor_medio: null, sem_vendas: ['Sem saída'],
  pagamentos: [{ metodo: 'Dinheiro', pedidos: 2, valor: 6500 }], tempo_medio_min: 35, agendados: 0, grupo_empresa: 0,
  cancelamentos_motivos: [{ motivo: 'Acabou um ingrediente', n: 1 }], estafetas: [], preparadores: [],
  zonas: [{ zona: 'Viana', pedidos: 2, vendas: 6000 }], estrelas: { '5': 1, '4': 1 }, reclamacoes: 0, reclamacoes_abertas: 0,
  convida: { pedidos_com_desconto: 1, comissoes_geradas: 100 },
};

test('períodos no dia de Luanda (perto da meia-noite UTC já é amanhã)', () => {
  const agora = new Date('2026-11-11T23:30:00Z'); // 12/11 em Luanda
  expect(periodoRel('hoje', agora)).toEqual(['2026-11-12', '2026-11-12']);
  expect(periodoRel('ontem', agora)).toEqual(['2026-11-11', '2026-11-11']);
  expect(periodoRel('7', agora)).toEqual(['2026-11-06', '2026-11-12']);
  expect(periodoRel('mes', agora)).toEqual(['2026-11-01', '2026-11-12']);
  expect(periodoRel('mes_anterior', agora)).toEqual(['2026-10-01', '2026-10-31']);
  expect(periodoRel('mes_anterior', new Date('2026-03-05T10:00:00Z'))).toEqual(['2026-02-01', '2026-02-28']);
  expect(periodoRel('datas', agora, '2026-01-01', '2026-12-31')).toEqual(['2026-01-01', '2026-12-31']);
  expect(periodoRel('datas', agora, '2025-01-01', '2026-12-31')).toBeNull();
  expect(periodoRel('datas', agora, '2026-11-10', '2026-11-01')).toBeNull();
});

test('variação face ao período anterior', () => {
  expect(variacao(6000, 4000)).toBe('▲ 50%');
  expect(variacao(3000, 4000)).toBe('▼ 25%');
  expect(variacao(10, 10)).toBe('=');
  expect(variacao(10, 0)).toBe('');
  expect(variacao(null, 5)).toBe('');
});

test('indicadores mostram comissão e o valor a receber pela cozinha', () => {
  const i = indicadores(rel);
  expect(i.find((x) => x.rotulo === 'A receber pela cozinha')).toEqual({ rotulo: 'A receber pela cozinha', valor: '5.400 Kz', variacao: '▲ 50%' });
  expect(i.find((x) => x.rotulo.startsWith('Comissão'))?.valor).toBe('600 Kz');
});

test('CSV e PDF: dados certos e texto escapado', () => {
  const csv = linhasCsvRelatorio(rel);
  expect(csv).toContainEqual(['A receber pela cozinha (Kz)', 5400, 3600]);
  expect(csv).toContainEqual(['Calulu <b>', 3, 6000, 100]);
  const html = htmlRelatorio(rel, 'Rita', new Date('2026-11-11T20:00:00Z'));
  expect(html).toContain('Calulu &lt;b&gt;');
  expect(html).toContain('Acabou um ingrediente');
  expect(html).not.toContain('Estafetas'); // secções sem dados ficam de fora
});

test('quem paga o Convida, por cozinha', () => {
  expect(quemPagaConvida(resumo({ convida_cozinha_percent: 0 }))).toMatch(/plataforma/);
  expect(quemPagaConvida(resumo({ convida_cozinha_percent: 100 }))).toMatch(/pagos pela cozinha/);
  expect(quemPagaConvida(resumo({ convida_cozinha_percent: 50 }))).toMatch(/50% pagos pela cozinha, o resto pela plataforma/);
  const i = indicadores({ ...rel, resumo: resumo({ convida_cozinha_percent: 100, convida_a_cargo_cozinha: 500 }) });
  expect(i.find((x) => x.rotulo.startsWith('Descontos Convida'))?.rotulo).toBe('Descontos Convida (cozinha paga 500 Kz)');
});

test('margem de uma dose e avaliação do custo da comida', () => {
  expect(margemPct(5000, 3500)).toBe(30);
  expect(margemPct(2000, null)).toBeNull();
  expect(avaliarCmv(30)).toBe('bom');
  expect(avaliarCmv(40)).toBe('atencao');
  expect(avaliarCmv(60)).toBe('alto');
  expect(avaliarCmv(null)).toBeNull();
});

test('CSV e PDF levam a rentabilidade e as doses quando existem', () => {
  const rent = {
    vendas_comida: 6000, cmv: 3600, cobertura_pct: 100, cmv_pct: 60, margem_bruta: 2400, despesas: 1000,
    despesas_por_categoria: [], compras: 0, a_receber_cozinha: 5400, resultado: 800,
    pratos: [{ nome: 'Calulu', qtd: 3, receita: 6000, custo: 3600, completo: true, margem: 2400, margem_pct: 40 }],
    doses: [{ nome: 'Calulu', dias: 2, lancadas: 6, vendidas: 5, sobras: 1, dias_esgotou: 1, hora_media_esgotou: '13:20', desperdicio: 1200 }],
  };
  const csv = linhasCsvRelatorio(rel, rent);
  expect(csv).toContainEqual(['Resultado aproximado (Kz)', 800]);
  expect(csv).toContainEqual(['Calulu', 2, 6, 5, 1, 1, '13:20', 1200]);
  const html = htmlRelatorio(rel, 'Rita', new Date('2026-11-11T20:00:00Z'), rent);
  expect(html).toContain('Rentabilidade');
  expect(html).toContain('1 de 2 dias');
});
