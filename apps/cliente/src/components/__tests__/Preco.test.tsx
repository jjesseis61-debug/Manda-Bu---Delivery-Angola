/// <reference types="jest" />
import { render } from '@testing-library/react-native';

import { Preco } from '@/components/Preco';
import { percentagemDesconto } from '@/lib/formatar';

test('percentagem de desconto', () => {
  expect(percentagemDesconto(4000, 3200)).toBe(20);
  expect(percentagemDesconto(3000, 2000)).toBe(33);
  expect(percentagemDesconto(3000, 3000)).toBe(0);
  expect(percentagemDesconto(0, 100)).toBe(0);
});

test('com campanha: preço novo, antigo riscado e percentagem', () => {
  const r = render(<Preco preco={4000} promo={3200} />);
  expect(r.getByText('3.200 Kz')).toBeTruthy();
  const antigo = r.getByText('4.000 Kz');
  expect(antigo.props.style).toMatchObject({ textDecorationLine: 'line-through' });
  expect(r.getByText('20% menos')).toBeTruthy();
  expect(r.getByLabelText('3.200 Kz, antes 4.000 Kz, 20% menos')).toBeTruthy();
});

test('sem campanha: só o preço; pratos para montar: desde', () => {
  const r = render(<Preco preco={4000} />);
  expect(r.getByText('4.000 Kz')).toBeTruthy();
  expect(r.queryByText(/menos/)).toBeNull();
  const d = render(<Preco preco={4000} desde={2500} promo={3000} />);
  expect(d.getByText('desde 2.500 Kz')).toBeTruthy();
  expect(d.queryByText(/menos/)).toBeNull();
});

test('preço em destaque (prato em campanha): novo, antigo riscado e percentagem numa linha', () => {
  const { PrecoDestaque } = jest.requireActual('@/components/Preco');
  const r = render(<PrecoDestaque preco={9000} promo={7200} />);
  expect(r.getByText('7.200 Kz')).toBeTruthy();
  expect(r.getByText('9.000 Kz').props.style).toMatchObject({ textDecorationLine: 'line-through' });
  expect(r.getByText('20% menos')).toBeTruthy();
  expect(r.getByLabelText('7.200 Kz, antes 9.000 Kz, 20% menos')).toBeTruthy();
});
