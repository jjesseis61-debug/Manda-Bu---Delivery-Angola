/// <reference types="jest" />
import {
  dataLimiteISO,
  dataLimiteTexto,
  erroCondominio,
  linkCondominio,
  reabreDaquiA,
  textoEstadoCozinha,
  textoVagas,
} from '../condominios';

jest.mock('../supabase', () => ({ supabase: {} }));

describe('condomínios', () => {
  it('vagas e estado da lista', () => {
    expect(textoVagas({ activos: 32, pendentes: 0, vagas: 50, lista_aberta: true })).toBe('32/50 membros · lista aberta');
    expect(textoVagas({ activos: 48, pendentes: 2, vagas: 50, lista_aberta: false })).toBe(
      '48/50 membros · 2 à espera de aprovação · lista completa',
    );
    expect(textoVagas({ activos: 10, pendentes: 0, vagas: 50, lista_aberta: false })).toContain('lista fechada');
  });

  it('data limite (DD/MM/AAAA, fim do dia em Luanda) e volta', () => {
    expect(dataLimiteISO('')).toBeNull();
    expect(dataLimiteISO('31/02/2026')).toBeUndefined();
    expect(dataLimiteISO('30-11-2026')).toBeUndefined();
    const iso = dataLimiteISO('30/11/2026') as string;
    expect(iso).toBe('2026-11-30T23:59:59+01:00');
    expect(dataLimiteTexto(iso)).toBe('30/11/2026');
    expect(dataLimiteTexto(null)).toBe('');
  });

  it('reabertura daqui a N horas', () => {
    const agora = new Date('2026-11-16T10:00:00Z');
    expect(reabreDaquiA(2, agora)).toBe('2026-11-16T12:00:00.000Z');
    expect(reabreDaquiA(0, agora)).toBeNull();
    expect(reabreDaquiA(25, agora)).toBeNull();
  });

  it('estado da cozinha e as 12 horas', () => {
    const agora = new Date('2026-11-16T20:00:00Z');
    expect(textoEstadoCozinha({ cozinha_aberta: true, fechada_desde: null }, agora)).toBe('🟢 Aberta');
    expect(textoEstadoCozinha({ cozinha_aberta: false, fechada_desde: '2026-11-16T15:00:00Z' }, agora)).toContain('vêem "fechada"');
    expect(textoEstadoCozinha({ cozinha_aberta: false, fechada_desde: '2026-11-16T07:00:00Z' }, agora)).toContain('invisível');
  });

  it('link e erros amigos', () => {
    expect(linkCondominio('AB12CD34')).toMatch(/\/condominio\/AB12CD34$/);
    expect(erroCondominio({ message: 'lista_cheia' })).toContain('Aumenta as vagas');
    expect(erroCondominio(new Error('outra coisa'))).toBeNull();
  });
});

describe('campanhas', () => {
  it('oferta e quando', () => {
    const { textoOferta, textoQuando } = jest.requireActual('../condominios');
    expect(textoOferta({ tipo: 'percentagem', valor: 20 })).toBe('20% de desconto nos pratos');
    expect(textoOferta({ tipo: 'preco', valor: 1500 })).toBe('Preço especial: 1.500 Kz');
    expect(textoQuando({ dias_semana: [6, 5], hora_inicio: '12:00', hora_fim: '15:00' })).toBe('sex, sáb · 12:00–15:00');
    expect(textoQuando({ dias_semana: null, hora_inicio: null, hora_fim: null })).toBe('todos os dias');
  });
  it('vagas com lista de espera', () => {
    const { textoVagas } = jest.requireActual('../condominios');
    expect(textoVagas({ activos: 50, pendentes: 0, vagas: 50, lista_aberta: false, espera: 4 })).toBe(
      '50/50 membros · 4 em lista de espera · lista completa',
    );
  });
});
