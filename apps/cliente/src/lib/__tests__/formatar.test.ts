/// <reference types="jest" />

import {
  formatarKz,
  textoEntregaGratis,
  formatarMedia,
  formatarTelefone,
  horaLuanda,
  mensagemGrupo,
  tempoEmFalta,
  mensagemCodigo,
  mensagemConvite,
  mensagemPartilhaPrato,
  minutosSegundos,
  textoPediram,
  mensagemErro,
  normalizarCodigo,
  telefoneInternacional,
  textoAmigo,
  textoAmigosEmFalta,
  textoRegras,
  valorDestaque,
} from '../formatar';
import type { Parametros } from '../tipos';

const parametros: Parametros = {
  ganho_por_pedido: 100,
  duracao_dias: 60,
  desconto_indicado: 500,
  limite_verificacao_semanal: 10000,
  levantamento_minimo: 2000,
  limite_parcelamento: 20000,
  contador_minimo: 10,
  limiar_pediram: 20,
  tamanho_top: 10,
};

describe('formatarKz', () => {
  it('usa o ponto como separador de milhares', () => {
    expect(formatarKz(1300)).toBe('1.300 Kz');
    expect(formatarKz(1234567)).toBe('1.234.567 Kz');
    expect(formatarKz(500)).toBe('500 Kz');
    expect(formatarKz(0)).toBe('0 Kz');
  });
  it('arredonda e trata valores negativos e vazios', () => {
    expect(formatarKz(99.6)).toBe('100 Kz');
    expect(formatarKz(-2500)).toBe('−2.500 Kz');
    expect(formatarKz(null)).toBe('0 Kz');
  });
});

describe('textoAmigo (C1)', () => {
  it('mostra os dias restantes', () => {
    expect(textoAmigo('Ana', 'activo', 23)).toBe('Ana · 23 dias');
    expect(textoAmigo('Ana', 'activo', 1)).toBe('Ana · último dia');
  });
  it('distingue à espera do 1.º pedido e período terminado', () => {
    expect(textoAmigo('Ana', 'aguarda_primeiro_pedido', null)).toBe('Ana · à espera do 1.º pedido');
    expect(textoAmigo('Ana', 'expirado', null)).toBe('Ana · terminou');
  });
});

describe('minutosSegundos (contagem do OTP)', () => {
  it('formata minutos:segundos com dois dígitos', () => {
    expect(minutosSegundos(600)).toBe('10:00');
    expect(minutosSegundos(125)).toBe('2:05');
    expect(minutosSegundos(9)).toBe('0:09');
  });
  it('nunca é negativo', () => {
    expect(minutosSegundos(-5)).toBe('0:00');
  });
});

describe('mensagemConvite (N1)', () => {
  it('leva a marca, o código, o desconto em vigor e o link', () => {
    expect(mensagemConvite('MB-4821', 500, 'mandabue://convite/MB-4821')).toBe(
      '🍲 Peço na Cozinha da Alexandra e recomendo! Usa o meu código MB-4821 e ganhas 500 Kz de desconto no teu 1.º pedido. 👉 mandabue://convite/MB-4821',
    );
  });
  it('usa o valor dos parâmetros, não um valor fixo', () => {
    expect(mensagemConvite('MB-4821', 800, 'x')).toContain('ganhas 800 Kz de desconto');
  });
  it('inclui o pedido mínimo quando há um', () => {
    expect(mensagemConvite('MB-4821', 1000, 'x', 5000)).toContain('em pedidos acima de 5.000 Kz');
  });
  it('omite o mínimo quando é 0', () => {
    expect(mensagemConvite('MB-4821', 1000, 'x', 0)).not.toContain('em pedidos acima de');
  });
});

describe('textoRegras (4.13)', () => {
  it('preenche as frases com os parâmetros', () => {
    const regras = textoRegras({ ...parametros, desconto_subtotal_minimo: 5000 });
    expect(regras[0]).toBe(
      'Ganhas 100 Kz por cada pedido entregue e pago dos amigos que convidares, a partir do 2.º pedido deles, durante 60 dias a contar do primeiro. Não há limite de ganhos.',
    );
    expect(textoRegras({ ...parametros, comissao_primeiro_pedido: true })[0]).toBe(
      'Ganhas 100 Kz por cada pedido entregue e pago dos amigos que convidares, durante 60 dias a contar do primeiro pedido deles. Não há limite de ganhos.',
    );
    expect(regras[1]).toBe(
      'O teu amigo também ganha: 500 Kz de desconto no primeiro pedido, válido apenas para contas novas e pedidos a partir de 5.000 Kz.',
    );
    expect(textoRegras(parametros)[1]).toBe('O teu amigo também ganha: 500 Kz de desconto no primeiro pedido, válido apenas para contas novas.');
    expect(regras[2]).toContain('a partir de 2.000 Kz, sem taxas');
    expect(regras[2]).not.toContain('válido durante');
    expect(textoRegras({ ...parametros, validade_saldo_meses: 12 })[2]).toContain('O saldo é válido durante 12 meses.');
    expect(regras[3]).toContain('mais de 10.000 Kz numa semana');
    // A regra das contas falsas fica no fim, dita como garantia de justiça e não como ameaça
    expect(regras.at(-1)).toMatch(/^Para ser justo para todos/);
  });
});

describe('normalizarCodigo', () => {
  it('aceita variações e devolve MB-dddd', () => {
    expect(normalizarCodigo(' mb-4821 ')).toBe('MB-4821');
    expect(normalizarCodigo('MB4821')).toBe('MB-4821');
    expect(normalizarCodigo('4821')).toBe('MB-4821');
    expect(normalizarCodigo('MB-48210')).toBe('MB-48210');
  });
  it('recusa o que não é um código', () => {
    expect(normalizarCodigo('MB-48')).toBeNull();
    expect(normalizarCodigo('ABC-1234')).toBeNull();
    expect(normalizarCodigo('')).toBeNull();
    expect(normalizarCodigo(null)).toBeNull();
  });
});

describe('telefoneInternacional', () => {
  it('converte números angolanos para +244', () => {
    expect(telefoneInternacional('923 456 789')).toBe('+244923456789');
    expect(telefoneInternacional('+244 923-456-789')).toBe('+244923456789');
    expect(telefoneInternacional('00244923456789')).toBe('+244923456789');
  });
  it('recusa números que não são de telemóvel angolano', () => {
    expect(telefoneInternacional('22 123 4567')).toBeNull();
    expect(telefoneInternacional('92345678')).toBeNull();
  });
});

describe('mensagens de erro', () => {
  it('traduz os códigos do servidor', () => {
    expect(mensagemCodigo('proprio_codigo')).toBe('Não podes usar o teu próprio código.');
    expect(mensagemCodigo('limite_local')).toBe('Este convite já foi usado o número máximo de vezes nesta morada.');
    expect(mensagemCodigo('sem_compra_propria')).toBe('Para levantar o saldo, faz primeiro um pedido teu (entregue e pago).');
    expect(mensagemErro({ message: 'item_indisponivel' })).toBe('Um dos pratos já não está disponível. Actualiza o carrinho.');
  });
  it('traduz a recusa do valor mínimo do prato montado (não parece erro de ligação)', () => {
    expect(mensagemErro(new Error('abaixo_do_minimo'))).toMatch(/valor mínimo/);
    expect(mensagemErro(new Error('agendamento_invalido'))).toMatch(/20 minutos e 14 dias/);
  });
  it('tem uma mensagem genérica para erros desconhecidos', () => {
    expect(mensagemErro(new Error('boom'))).toBe('Não foi possível concluir. Verifica a ligação e tenta outra vez.');
  });
});

describe('destaques (C3)', () => {
  it('valor exacto, em intervalo ou escondido', () => {
    expect(valorDestaque(12000, null, null)).toBe('12.000 Kz');
    expect(valorDestaque(null, 10000, 20000)).toBe('10.000–20.000 Kz');
    expect(valorDestaque(null, null, null)).toBeNull();
  });

  it('amigos em falta para o top, no singular e no plural', () => {
    expect(textoAmigosEmFalta(1, 10)).toBe('Falta 1 amigo para entrares no top 10.');
    expect(textoAmigosEmFalta(3, 10)).toBe('Faltam 3 amigos para entrares no top 10.');
  });
});

describe('avaliações (C10)', () => {
  it('média com vírgula e plural', () => {
    expect(formatarMedia(4.5, 12)).toBe('4,5 · 12 avaliações');
    expect(formatarMedia(5, 1)).toBe('5,0 · 1 avaliação');
  });
});

describe('pedidos de grupo (C12, C13)', () => {
  it('hora de Luanda', () => {
    expect(horaLuanda('2026-10-01T11:30:00Z')).toBe('12h30');
    expect(horaLuanda('2026-10-01T23:05:00Z')).toBe('00h05');
  });

  it('tempo em falta para o prazo', () => {
    const agora = new Date('2026-10-01T10:00:00Z');
    expect(tempoEmFalta('2026-10-01T10:12:00Z', agora)).toBe('12 min');
    expect(tempoEmFalta('2026-10-01T11:05:00Z', agora)).toBe('1 h 05 min');
    expect(tempoEmFalta('2026-10-01T10:00:30Z', agora)).toBe('menos de 1 min');
    expect(tempoEmFalta('2026-10-01T09:59:00Z', agora)).toBeNull();
  });

  it('mensagem de partilha do grupo', () => {
    expect(mensagemGrupo('12h30', 'Edifício Kilamba', 'mandabue://grupo/G-ABC123')).toBe(
      'Vamos pedir juntos o almoço na Cozinha da Alexandra! Entrega às 12h30 em Edifício Kilamba. Junta o teu pedido: mandabue://grupo/G-ABC123',
    );
  });
});

test('I12: benefícios do pacote', () => {
  const { beneficiosPacote } = require('../formatar') as typeof import('../formatar');
  expect(
    beneficiosPacote({ refeicoes: 20, refeicoes_oferta: 2, valor_refeicao: 2500, preco: 50000, validade_dias: 30, pausa_max_dias: 5, entrega_gratis: true }),
  ).toEqual([
    '22 refeições: 20 + 2 de oferta',
    'Poupas 5.000 Kz no mês',
    'Entrega grátis em todos os pedidos pagos com o pacote',
    'Válido por 30 dias',
    'Pausa até 5 dias (férias, doença)',
    'Reembolso das refeições que não usares',
  ]);
});

describe('mensagemPartilhaPrato', () => {
  it('inclui nome, marca, chamada à ação e link (sem repetir o preço — vem no cartão)', () => {
    const msg = mensagemPartilhaPrato('Choco frito', 'Cozinha da Alexandra', 'https://x/prato?id=1');
    expect(msg).toContain('Choco frito');
    expect(msg).toContain('Cozinha da Alexandra');
    expect(msg).toContain('Instala a app e faz o teu pedido');
    expect(msg).toContain('https://x/prato?id=1');
    expect(msg).not.toContain('Kz');
  });

  it('com código de convite: diz o desconto do amigo e o código, em negrito do WhatsApp', () => {
    const msg = mensagemPartilhaPrato('Choco frito', 'Cozinha da Alexandra', 'https://x/p/1?r=MB-4812', {
      codigo: 'MB-4812',
      desconto: 1000,
      minimo: 5000,
    });
    expect(msg).toContain('*Choco frito*');
    expect(msg).toContain('*MB-4812*');
    expect(msg).toContain('*1.000 Kz de desconto*');
    expect(msg).toContain('a partir de 5.000 Kz');
    expect(msg.endsWith('https://x/p/1?r=MB-4812')).toBe(true);
  });

  it('com desconto 0 volta à mensagem simples', () => {
    const msg = mensagemPartilhaPrato('Choco frito', 'M', 'L', { codigo: 'MB-4812', desconto: 0 });
    expect(msg).toContain('Instala a app');
  });
});

describe('textoPediram', () => {
  it('plural e singular', () => {
    expect(textoPediram(285)).toBe('285 pessoas pediram este mês');
    expect(textoPediram(1)).toBe('1 pessoa pediu este mês');
    expect(textoPediram(20)).toBe('20 pessoas pediram este mês');
  });
});

describe('formatarTelefone', () => {
  it('agrupa número angolano com indicativo', () => {
    expect(formatarTelefone('958077592')).toBe('+244 958 077 592');
    expect(formatarTelefone('244958077592')).toBe('+244 958 077 592');
    expect(formatarTelefone('958 077 592')).toBe('+244 958 077 592');
  });
  it('deixa como está o que não encaixa', () => {
    expect(formatarTelefone('12345')).toBe('12345');
  });
});

describe('textoEntregaGratis', () => {
  it('entrega já grátis', () => {
    expect(textoEntregaGratis({ entrega_gratis: true, entrega_gratis_acima: 10000, falta_entrega_gratis: null })).toBe(
      '🎉 Entrega grátis neste pedido!',
    );
  });
  it('diz quanto falta', () => {
    const t = textoEntregaGratis({ entrega_gratis: false, entrega_gratis_acima: 10000, falta_entrega_gratis: 750 });
    expect(t).toContain('Junta mais');
    expect(t).toContain('depois dos descontos');
  });
  it('sem entrega grátis na zona: nada', () => {
    expect(textoEntregaGratis({ entrega_gratis: false, entrega_gratis_acima: null, falta_entrega_gratis: null })).toBeNull();
    expect(textoEntregaGratis({})).toBeNull();
  });
});
