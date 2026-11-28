/// <reference types="jest" />
import { fireEvent, render } from '@testing-library/react-native';

import { validarFicha } from '@/app/rh/[id]';
import { CampoData, CampoHora, SeletorMes } from '@/components/CamposData';
import { anosEntre, biValido, ddmmParaIso, ibanAgrupado, ibanValido, isoParaDDMM, mesVizinho, nifValido, telefoneAngolaValido } from '@/lib/datas';

jest.mock('@/lib/supabase', () => ({ supabase: {} }));
jest.mock('@/lib/sessao', () => ({ useSessao: () => ({ carregado: true, sessao: {}, funcionario: {}, pode: () => true }) }));

test('conversões de datas (só datas reais do calendário)', () => {
  expect(ddmmParaIso('01/09/1988')).toBe('1988-09-01');
  expect(ddmmParaIso('31/02/2026')).toBeNull();
  expect(ddmmParaIso('29/02/2024')).toBe('2024-02-29');
  expect(ddmmParaIso('1988-09-01')).toBeNull();
  expect(isoParaDDMM('2026-11-15')).toBe('15/11/2026');
  expect(anosEntre('1988-09-01', '2026-08-31')).toBe(37);
  expect(anosEntre('1988-09-01', '2026-09-01')).toBe(38);
  expect(mesVizinho('2026-01', -1)).toBe('2025-12');
});

test('documentos angolanos', () => {
  expect(biValido('001234567la041')).toBe(true);
  expect(biValido('01234567LA041')).toBe(false);
  expect(nifValido('5000123456')).toBe(true);
  expect(ibanValido('AO06 0040 0000 1234 5678 9012 3')).toBe(true);
  expect(ibanValido('AO06 0040')).toBe(false);
  expect(ibanAgrupado('ao06004000001234567890123')).toBe('AO06 0040 0000 1234 5678 9012 3');
  expect(telefoneAngolaValido('923 000 000')).toBe(true);
  expect(telefoneAngolaValido('+244923000000')).toBe(true);
  expect(telefoneAngolaValido('22300000')).toBe(false);
});

test('campo de data: escreve-se como em Angola, envia AAAA-MM-DD e mostra por extenso', () => {
  const aoMudar = jest.fn();
  const r = render(<CampoData rotulo="Nascimento" valor="" aoMudar={aoMudar} />);
  fireEvent.changeText(r.getByLabelText('Nascimento (DD/MM/AAAA)'), '01091988');
  expect(aoMudar).toHaveBeenLastCalledWith('1988-09-01', true);
  expect(r.getByDisplayValue('01/09/1988')).toBeTruthy();
  expect(r.getByText('1 de setembro de 1988')).toBeTruthy();
  fireEvent.changeText(r.getByLabelText('Nascimento (DD/MM/AAAA)'), '31022026');
  expect(aoMudar).toHaveBeenLastCalledWith('', false);
  expect(r.getByText('Esta data não existe. Confirma o dia e o mês.')).toBeTruthy();
});

test('campo de data: abre com o valor do servidor e mostra o erro do ecrã', () => {
  const r = render(<CampoData rotulo="Até" valor="2026-09-30" aoMudar={() => undefined} erro="O fim é antes do início." />);
  expect(r.getByDisplayValue('30/09/2026')).toBeTruthy();
  expect(r.getByText('O fim é antes do início.')).toBeTruthy();
});

test('campo de hora com máscara e mês com setas', () => {
  const hora = jest.fn();
  const h = render(<CampoHora rotulo="Hora" valor="" aoMudar={hora} />);
  fireEvent.changeText(h.getByLabelText('Hora (HH:MM)'), '1230');
  expect(hora).toHaveBeenCalledWith('12:30');
  const errada = render(<CampoHora rotulo="Hora" valor="25:00" aoMudar={() => undefined} />);
  expect(errada.getByText('Hora inválida (00:00 a 23:59).')).toBeTruthy();
  const mes = jest.fn();
  const m = render(<SeletorMes valor="2026-01" aoMudar={mes} />);
  expect(m.getByText('janeiro de 2026')).toBeTruthy();
  fireEvent.press(m.getByLabelText('Mês anterior'));
  expect(mes).toHaveBeenCalledWith('2025-12');
});

test('ficha: idade na admissão, datas no futuro e formatos', () => {
  const hoje = '2026-11-21';
  expect(validarFicha({ data_nascimento: '1988-09-01', data_admissao: '1997-11-01' }, hoje).erros.data_admissao).toMatch(/9 anos/);
  expect(validarFicha({ data_nascimento: '2010-01-01', data_admissao: '2026-02-01' }, hoje).avisos.data_admissao).toMatch(/16 anos/);
  expect(validarFicha({ data_nascimento: '1988-09-01', data_admissao: '2020-01-01' }, hoje).erros).toEqual({});
  expect(validarFicha({ data_nascimento: '2027-01-01' }, hoje).erros.data_nascimento).toMatch(/futuro/);
  const f = validarFicha({ bi: '123', nif: 'x', iban: 'AO06 1', emergencia_telefone: '12' }, hoje).erros;
  expect(Object.keys(f).sort()).toEqual(['bi', 'emergencia_telefone', 'iban', 'nif']);
});
