/// <reference types="jest" />
import { diaLuanda, formatarDia, formatarKz, formatarPercentagem, inicioMesLuanda, mensagemErro, paraCsv } from '../formatar';

describe('formatar (operador)', () => {
  it('formata kwanzas', () => {
    expect(formatarKz(12300)).toBe('12.300 Kz');
    expect(formatarKz(-500)).toBe('−500 Kz');
  });

  it('percentagem com vírgula e sem divisão por zero', () => {
    expect(formatarPercentagem(1, 3)).toBe('33,3 %');
    expect(formatarPercentagem(1, 0)).toBe('—');
  });

  it('dia em Luanda (UTC+1) e início do mês', () => {
    const quaseMeiaNoiteUtc = new Date('2026-09-30T23:30:00Z');
    expect(diaLuanda(0, quaseMeiaNoiteUtc)).toBe('2026-10-01');
    expect(diaLuanda(-6, quaseMeiaNoiteUtc)).toBe('2026-09-25');
    expect(inicioMesLuanda(quaseMeiaNoiteUtc)).toBe('2026-10-01');
  });

  it('dia sem fuso horário', () => {
    expect(formatarDia('2026-10-01')).toBe('01/10/2026');
    expect(formatarDia(null)).toBe('');
  });

  it('CSV com ponto e vírgula, vírgula decimal e aspas', () => {
    expect(
      paraCsv([
        ['Nome', 'Valor'],
        ['Calulu; peixe', 12.5],
        ['Diz "olá"', null],
      ]),
    ).toBe('Nome;Valor\n"Calulu; peixe";12,5\n"Diz ""olá""";');
  });

  it('mensagens de erro do servidor', () => {
    expect(mensagemErro({ message: 'sem_permissao' })).toBe('Não tens permissão para esta acção.');
    expect(mensagemErro({ message: 'parcelas_nao_somam_valor_final' })).toBe('Os pagamentos não somam o valor a receber.');
  });
});
