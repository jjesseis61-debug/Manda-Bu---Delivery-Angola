/// <reference types="jest" />
import { urlComoChegar, haQuantoTempo, regiaoPara } from '../mapa';
import { alternar, chaveLinha, gruposEmFalta, gruposEsgotados, opcoesEscolhidas, precoMinimo, precoMontado, regraGrupo } from '../opcoes';
import type { GrupoOpcoes } from '../tipos';

const base: GrupoOpcoes = {
  id: 'g1', cardapio_id: 'm', nome: 'Base', minimo: 1, maximo: 1, ordem: 1,
  opcoes: [{ id: 'funge', nome: 'Funge', preco_extra: 0, ordem: 1 }, { id: 'arroz', nome: 'Arroz', preco_extra: 0, ordem: 2 }],
};
const extras: GrupoOpcoes = {
  id: 'g2', cardapio_id: 'm', nome: 'Extras', minimo: 0, maximo: 2, ordem: 2,
  opcoes: [
    { id: 'ovo', nome: 'Ovo', preco_extra: 200, ordem: 1 },
    { id: 'banana', nome: 'Banana', preco_extra: 300, ordem: 2 },
    { id: 'salada', nome: 'Salada', preco_extra: 150, ordem: 3 },
  ],
};

describe('prato montável', () => {
  it('escolha única troca a anterior; escolha múltipla pára no máximo', () => {
    expect(alternar(base, ['funge'], 'arroz')).toEqual(['arroz']);
    expect(alternar(extras, ['ovo', 'banana'], 'salada')).toEqual(['ovo', 'banana']);
    expect(alternar(extras, ['ovo'], 'ovo')).toEqual([]);
  });

  it('grupo obrigatório sem opções disponíveis esgota o prato; um opcional vazio não', () => {
    expect(gruposEsgotados([{ ...base, opcoes: [] }, extras])).toEqual(['Base']);
    expect(gruposEsgotados([base, { ...extras, opcoes: [] }])).toEqual([]);
  });

  it('preço = prato + extras de cada opção (como no servidor)', () => {
    const escolhidas = opcoesEscolhidas([base, extras], ['arroz', 'ovo', 'banana']);
    expect(precoMontado(7500, escolhidas)).toBe(8000);
    expect(precoMontado(7500, [])).toBe(7500);
  });

  it('ingredientes tirados descontam no preço e separam as linhas do carrinho', () => {
    const cebola = { cardapio_id: 'm', produto_id: 'cebola', nome: 'Cebola', quantidade: 50, unidade: 'g', valor: 25 };
    expect(precoMontado(4000, [], [cebola])).toBe(3975);
    expect(precoMontado(10, [], [{ ...cebola, valor: 50 }])).toBe(0);
    expect(chaveLinha('m', [], [cebola])).not.toBe(chaveLinha('m', []));
  });

  it('"desde": o prato com a opção mais barata de cada grupo obrigatório', () => {
    const proteina = { ...base, id: 'g3', nome: 'Proteína',
      opcoes: [{ id: 'frango', nome: 'Frango', preco_extra: 3000, ordem: 1 }, { id: 'peixe', nome: 'Peixe', preco_extra: 500, ordem: 2 }] };
    const bases = { ...base, opcoes: [{ id: 'arroz', nome: 'Arroz', preco_extra: 1000, ordem: 1 }, { id: 'batata', nome: 'Batata', preco_extra: 550, ordem: 2 }] };
    expect(precoMinimo(0, [bases, proteina])).toBe(1050);
  });

  it('o botão só liga com os grupos obrigatórios escolhidos', () => {
    expect(gruposEmFalta([base, extras], ['ovo'])).toEqual(['Base']);
    expect(gruposEmFalta([base, extras], ['funge'])).toEqual([]);
  });

  it('preço = prato + extras, opções pela ordem dos grupos', () => {
    const o = opcoesEscolhidas([base, extras], ['banana', 'arroz']);
    expect(o.map((x) => x.nome)).toEqual(['Arroz', 'Banana']);
    expect(precoMontado(2500, o)).toBe(2800);
  });

  it('a mesma combinação junta-se na mesma linha do carrinho, por qualquer ordem', () => {
    const a = opcoesEscolhidas([base, extras], ['funge', 'ovo']);
    const b = opcoesEscolhidas([extras, base], ['ovo', 'funge']);
    expect(chaveLinha('m', a)).toBe(chaveLinha('m', b));
    expect(chaveLinha('m', a)).not.toBe(chaveLinha('m', []));
  });

  it('descreve a regra de cada grupo', () => {
    expect(regraGrupo(base)).toBe('Escolhe 1');
    expect(regraGrupo(extras)).toBe('Até 2 (opcional)');
  });
});

describe('mapa', () => {
  it('link de navegação do Google Maps até à cozinha', () => {
    expect(urlComoChegar({ lat: -8.917, lng: 13.186 })).toBe('https://www.google.com/maps/dir/?api=1&destination=-8.917,13.186');
  });

  it('a região mostra o estafeta e o destino', () => {
    const r = regiaoPara([{ lat: -8.9, lng: 13.18 }, { lat: -8.92, lng: 13.18 }]);
    expect(r.latitude).toBeCloseTo(-8.91);
    expect(r.latitudeDelta).toBeGreaterThan(0.02);
  });

  it('há quanto tempo foi a última posição', () => {
    const agora = Date.parse('2026-10-02T12:00:00Z');
    expect(haQuantoTempo('2026-10-02T11:59:40Z', agora)).toBe('há 20 s');
    expect(haQuantoTempo('2026-10-02T11:57:00Z', agora)).toBe('há 3 min');
  });
});
