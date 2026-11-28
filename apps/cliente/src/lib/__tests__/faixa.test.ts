const mockRpc = jest.fn();
jest.mock('@/lib/supabase', () => ({ supabase: { rpc: (...a: unknown[]) => mockRpc(...a) } }));

import { fraseBairro, frasesFaixa, lerPontualidade, terceiraFrase, type Pontualidade } from '@/lib/faixa';

const cumpre: Pontualidade = { entregas: 40, a_tempo_pct: 95, tempo_min: 45, cumpre: true };
const naoCumpre: Pontualidade = { entregas: 12, a_tempo_pct: 100, tempo_min: 45, cumpre: false };

describe('faixa de confiança', () => {
  it('começa em B: Problema? Resolvemos (liga à ajuda)', () => {
    expect(terceiraFrase(null)).toEqual({ icone: '🤝', texto: 'Problema? Resolvemos', ajuda: true });
    expect(terceiraFrase(naoCumpre).texto).toBe('Problema? Resolvemos');
  });

  it('passa a A só quando o servidor diz que se cumpre', () => {
    expect(terceiraFrase(cumpre)).toEqual({ icone: '⏱️', texto: 'Na tua porta em ~45 min' });
    expect(terceiraFrase({ ...cumpre, tempo_min: null }).texto).toBe('Problema? Resolvemos');
  });

  it('pedido agendado não promete tempo', () => {
    expect(terceiraFrase(cumpre, true).texto).toBe('Na hora que escolheres');
  });

  it('prova social só com número', () => {
    expect(fraseBairro(null)).toBeNull();
    expect(fraseBairro(0)).toBeNull();
    expect(fraseBairro(1)?.texto).toBe('1 pedido hoje no teu bairro');
    expect(fraseBairro(12, 'Talatona')?.texto).toBe('12 pedidos hoje no Talatona');
  });

  it('as duas primeiras são fixas e a 3.ª alterna com o bairro', () => {
    const bairro = fraseBairro(8);
    const a = frasesFaixa(cumpre, bairro, 0);
    const b = frasesFaixa(cumpre, bairro, 1);
    expect(a.map((f) => f.texto)).toEqual(['Pagas na entrega', 'Comida de casa', 'Na tua porta em ~45 min']);
    expect(b[2].texto).toBe('8 pedidos hoje no teu bairro');
    expect(frasesFaixa(null, null, 1)[2].texto).toBe('Problema? Resolvemos');
  });

  it('erro ou falta de rede na leitura dá null (fica B)', async () => {
    mockRpc.mockResolvedValueOnce({ data: cumpre, error: null });
    await expect(lerPontualidade()).resolves.toEqual(cumpre);
    mockRpc.mockResolvedValueOnce({ data: null, error: { message: 'x' } });
    await expect(lerPontualidade()).resolves.toBeNull();
    mockRpc.mockRejectedValueOnce(new Error('rede'));
    await expect(lerPontualidade()).resolves.toBeNull();
  });
});
