/// <reference types="jest" />
import { veredictoExperiencia, type GrupoExperiencia } from '@/lib/experiencias';

jest.mock('@/lib/supabase', () => ({ supabase: {} }));

const g = (dias_visita: number, conversao_pct: number): GrupoExperiencia => ({
  clientes: 50, dias_visita, visitas: dias_visita, dias_com_pedido: Math.round((dias_visita * conversao_pct) / 100), conversao_pct,
  pedidos: 0, valor_medio: null, mediana_segundos: null,
});

test('com poucos dados não há conclusão', () => {
  const v = veredictoExperiencia(g(40, 30), g(120, 10));
  expect(v).toEqual({ vencedor: null, claro: false, texto: 'Ainda poucos dados (A: 40, B: 120 visitas). Espera até cada grupo ter pelo menos 100.' });
});

test('diferença pequena: fica a fotografia média, sem vencedor claro', () => {
  const v = veredictoExperiencia(g(150, 20), g(150, 21.5));
  expect(v.vencedor).toBe('B');
  expect(v.claro).toBe(false);
  expect(v.texto).toBe('Sem diferença clara (1,5 pontos). Fica a fotografia média: gasta menos dados e mostra mais pratos.');
});

test('vencedor claro para cada lado', () => {
  expect(veredictoExperiencia(g(150, 20), g(150, 26))).toEqual({
    vencedor: 'B', claro: true, texto: 'A fotografia média converte mais: +6 pontos (26% contra 20%).',
  });
  expect(veredictoExperiencia(g(150, 31.2), g(150, 25))).toEqual({
    vencedor: 'A', claro: true, texto: 'A fotografia grande converte mais: +6,2 pontos (31,2% contra 25%).',
  });
});
