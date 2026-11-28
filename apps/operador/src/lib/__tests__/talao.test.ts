import { detalharItem, htmlTalaoCozinha, htmlTalaoEntrega, numeroCurto } from '../talao';
import type { PedidoOperador } from '../tipos';

const pedido = {
  pedido_id: 'a1b2c3d4-0000-4000-8000-000000000000',
  criado_em: '2026-11-09T00:13:00Z',
  estado: 'pendente',
  cozinha_id: 'k',
  cliente_nome: 'Jacob Jesse',
  cliente_telefone: '926155806',
  itens: [
    {
      nome: 'Serve o teu próprio prato (Arroz, Frango, Feijão)', qtd: 1, preco_unitario: 5000,
      opcoes: [{ nome: 'Arroz' }, { nome: 'Frango' }, { nome: 'Feijão' }],
    },
    { nome: 'Muamba (Funge; sem Cebola, Jindungo)', qtd: 2, preco_unitario: 2000, opcoes: [{ nome: 'Funge' }], componentes_excluidos: ['p1', 'p2'] },
    { nome: 'Calulu (peixe, carne seca)', qtd: 1, preco_unitario: 3000 },
  ],
  subtotal: 12000, taxa_entrega: 800, desconto_indicacao: 1000, credito_indicacao_usado: 0, a_pagar: 11800,
  observacoes: 'Sem cebola <por favor>', hora_prometida: '2026-11-09T00:58:00Z', pagador_distinto: null,
  ponto_entrega_id: 'pe', ponto_tipo: 'residencial', ponto_lat: null, ponto_lng: null, ponto_referencia: 'Casa', zona_nome: 'Maianga',
  atribuido_a: null, atribuido_a_nome: null, atribuido_a_mim: false, minha: false,
} as PedidoOperador;

test('separa o nome, as opções e os ingredientes tirados; nomes com parêntesis ficam intactos', () => {
  expect(detalharItem(pedido.itens[0])).toEqual({ nome: 'Serve o teu próprio prato', opcoes: ['Arroz', 'Frango', 'Feijão'], sem: [] });
  expect(detalharItem(pedido.itens[1])).toEqual({ nome: 'Muamba', opcoes: ['Funge'], sem: ['Cebola', 'Jindungo'] });
  expect(detalharItem(pedido.itens[2])).toEqual({ nome: 'Calulu (peixe, carne seca)', opcoes: [], sem: [] });
});

test('número curto do pedido', () => {
  expect(numeroCurto(pedido.pedido_id)).toBe('A1B2C3');
});

test('talão da cozinha: opções uma por linha, o que tirar e as observações, sem preços', () => {
  const html = htmlTalaoCozinha(pedido);
  expect(html).toContain('COZINHA');
  expect(html).toContain('#A1B2C3');
  expect(html).toContain('<div class="op">- Frango</div>');
  expect(html).toContain('SEM Cebola');
  expect(html).toContain('Sem cebola &lt;por favor&gt;'); // escapado
  expect(html).not.toContain('Kz');
});

test('talão de entrega: morada, telefone, valores e o que receber', () => {
  const html = htmlTalaoEntrega(pedido);
  expect(html).toContain('ENTREGA');
  expect(html).toContain('Casa · Casa · Maianga');
  expect(html).toContain('+244 926155806');
  expect(html).toContain('4.000 Kz'); // 2 × 2.000
  expect(html).toContain('−1.000 Kz');
  expect(html).toContain('A RECEBER');
  expect(html).toContain('11.800 Kz');
});
