/// <reference types="jest" />
import { render } from '@testing-library/react-native';
import { HeaderHeightContext } from 'expo-router/react-navigation';
import { KeyboardAvoidingView, ScrollView, Text } from 'react-native';

import { Ecra } from '@/components/ui';

test('o teclado não tapa os campos: reserva o espaço do teclado descontando o cabeçalho', () => {
  const ecra = render(
    <HeaderHeightContext.Provider value={64}>
      <Ecra>
        <Text>Conteúdo</Text>
      </Ecra>
    </HeaderHeightContext.Provider>,
  );
  const kav = ecra.UNSAFE_getByType(KeyboardAvoidingView);
  expect(kav.props.behavior).toBe('padding');
  expect(kav.props.keyboardVerticalOffset).toBe(64);
  expect(ecra.UNSAFE_getByType(ScrollView).props.keyboardShouldPersistTaps).toBe('handled');
});

test('sem cabeçalho, não desconta nada', () => {
  const ecra = render(
    <Ecra>
      <Text>Conteúdo</Text>
    </Ecra>,
  );
  expect(ecra.UNSAFE_getByType(KeyboardAvoidingView).props.keyboardVerticalOffset).toBe(0);
});
