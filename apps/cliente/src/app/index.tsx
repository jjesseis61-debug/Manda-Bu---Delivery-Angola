import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

// Ecrã inicial provisório: os ecrãs da I2 (C1, C2, C4, C6, C7, C8, C11) substituem-no.
export default function Inicio() {
  return (
    <SafeAreaView style={estilos.ecra}>
      <View style={estilos.centro}>
        <Text style={estilos.marca}>Manda Bué</Text>
        <Text style={estilos.subtitulo}>Delivery Angola</Text>
      </View>
    </SafeAreaView>
  );
}

const estilos = StyleSheet.create({
  ecra: {
    flex: 1,
    backgroundColor: '#fff',
  },
  centro: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  marca: {
    fontSize: 32,
    fontWeight: '700',
  },
  subtitulo: {
    fontSize: 16,
    marginTop: 4,
  },
});
