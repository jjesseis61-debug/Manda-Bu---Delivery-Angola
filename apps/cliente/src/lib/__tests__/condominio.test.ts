/// <reference types="jest" />
import { cozinhasComCondominio, textoCondominioFechado, type CondominioAqui } from '../condominio';

jest.mock('../supabase', () => ({ supabase: {} }));
jest.mock('expo-location', () => ({}));

const OUTRAS = [{ cozinha_id: 'a', nome: 'Maianga', publica: false, foto_url: null, historia: null, pratos: 10 }];
const COND: CondominioAqui = {
  condominio_id: 'c', nome: 'Jardim do Éden', cozinha_id: 'k', cozinha: 'Cozinha Jardim', foto_url: null, historia: null,
  aberta: true, reabre_em: null, visivel: true, pratos: 6,
};

describe('cozinha de condomínio', () => {
  it('aberta: só a cozinha do condomínio', () => {
    expect(cozinhasComCondominio(COND, OUTRAS).map((c) => c.cozinha_id)).toEqual(['k']);
  });
  it('fechada, invisível ou fora: as outras cozinhas', () => {
    expect(cozinhasComCondominio({ ...COND, aberta: false }, OUTRAS)).toBe(OUTRAS);
    expect(cozinhasComCondominio({ ...COND, aberta: false, visivel: false }, OUTRAS)).toBe(OUTRAS);
    expect(cozinhasComCondominio(null, OUTRAS)).toBe(OUTRAS);
  });
  it('texto do cartão fechado, com a hora de reabrir', () => {
    const t = textoCondominioFechado({ ...COND, aberta: false, reabre_em: '2026-11-16T17:00:00Z' }, () => '18:00');
    expect(t).toBe('🔒 Cozinha Jardim (Jardim do Éden) está fechada e volta às 18:00. Entretanto podes pedir noutra cozinha.');
    expect(textoCondominioFechado({ ...COND, aberta: false }, () => '')).not.toContain('volta às');
  });
});
