// Mock do maplibre para os testes (jest não transpila o ESM nativo da biblioteca).
// Os ecrãs só precisam que os componentes existam e deixem passar os filhos.
const React = require('react');
const { View } = require('react-native');

const Passa = ({ children }) => React.createElement(View, null, children);

module.exports = {
  Map: Passa,
  Camera: () => null,
  Marker: Passa,
};
