/// <reference types="jest" />
import { taxaAusencia, veredictoCompromisso, type GrupoCompromisso } from '@/lib/compromisso';

jest.mock('@/lib/supabase', () => ({ supabase: {} }));
const g = (agendados: number, ausentes: number): GrupoCompromisso => ({ agendados, confirmados: 0, com_ausencia: ausentes, entregues: 0, cancelados: 0 });

test('taxa de ausência', () => {
  expect(taxaAusencia(g(50, 5))).toBe(10);
  expect(taxaAusencia(g(0, 0))).toBeNull();
});

test('veredicto: poucos dados, sem diferença, a pergunta ajuda, a pergunta não ajuda', () => {
  expect(veredictoCompromisso(g(10, 1), g(60, 6)).texto).toMatch(/Ainda poucos agendados/);
  expect(veredictoCompromisso(g(50, 5), g(50, 5)).claro).toBe(false);
  const ajuda = veredictoCompromisso(g(50, 3), g(50, 8));
  expect(ajuda).toMatchObject({ claro: true, vencedor: 'A' });
  expect(ajuda.texto).toBe('A pergunta reduz as ausências: 6% contra 16% (−10 pontos).');
  expect(veredictoCompromisso(g(50, 8), g(50, 3))).toMatchObject({ claro: true, vencedor: 'B' });
});
