/// <reference types="jest" />
import { fireEvent, render } from '@testing-library/react-native';
import { useState } from 'react';

import { LinhaDoPedido } from '@/components/LinhaDoPedido';
import type { LinhaCarrinho } from '@/lib/carrinho';

const item = { id: 'm', nome: 'Serve o teu prato', preco: 2000, descricao: null, categoria: null, foto_url: null, do_dia: false, cozinha_id: 'k', prato_base_id: null, pedidos_mes: 0 };

function Teste({ linha, aoMudar = jest.fn() }: { linha: LinhaCarrinho; aoMudar?: (q: number) => void }) {
  const [aberta, setAberta] = useState(false);
  return <LinhaDoPedido linha={linha} aberta={aberta} aoTocarPrato={() => setAberta((a) => !a)} aoMudar={aoMudar} />;
}

test('prato montado: o tabuleiro pequeno com o prato e a bebida; tocar no prato mostra os preços', () => {
  const linha = {
    chave: 'a',
    item,
    qtd: 1,
    tirados: [],
    opcoes: [
      { id: 'ar', nome: 'Arroz', preco_extra: 0, zona: 'base' as const, recipiente: 'panela' as const },
      { id: 'fr', nome: 'Frango grelhado', preco_extra: 1500, zona: 'proteina' as const, recipiente: 'travessa' as const },
      { id: 'pu', nome: 'Pudim', preco_extra: 800, zona: 'sobremesa' as const, recipiente: 'taca' as const },
      { id: 'co', nome: 'Coca-Cola', preco_extra: 500, zona: 'bebida' as const, recipiente: 'lata' as const },
    ],
  } as LinhaCarrinho;
  const aoMudar = jest.fn();
  const ecra = render(<Teste linha={linha} aoMudar={aoMudar} />);
  expect(ecra.getByLabelText('No tabuleiro: Coca-Cola')).toBeTruthy();
  expect(ecra.getByLabelText('Sobremesa: Pudim')).toBeTruthy();
  expect(ecra.queryByText('+1.500 Kz')).toBeNull();
  fireEvent.press(ecra.getByLabelText('Prato de Serve o teu prato: Arroz, Frango grelhado, Pudim, Coca-Cola. Toca para ver os preços'));
  expect(ecra.getByText('+1.500 Kz')).toBeTruthy();
  expect(ecra.getByText('2.000 Kz')).toBeTruthy();
  fireEvent.press(ecra.getByLabelText('Mais'));
  expect(aoMudar).toHaveBeenCalledWith(2);
});

test('prato do dia (sem opções): a fotografia enche o prato e não há lista', () => {
  const ecra = render(<Teste linha={{ chave: 'b', item: { ...item, nome: 'Muamba' }, qtd: 2, tirados: [], opcoes: [] } as LinhaCarrinho} />);
  expect(ecra.getByLabelText('Muamba')).toBeTruthy();
  expect(ecra.queryByText(/Toca para ver/)).toBeNull();
});
