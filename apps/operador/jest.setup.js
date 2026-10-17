// Mock oficial do AsyncStorage (módulo nativo não existe em ambiente de teste).
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);
