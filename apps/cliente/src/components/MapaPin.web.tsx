import { Text, View } from 'react-native';

import { cores, raio } from '@/lib/tema';

export type Coordenadas = { latitude: number; longitude: number };

/** Na web não há mapa nativo: usa-se "A minha localização" e mostra-se a coordenada */
export function MapaPin({ ponto }: { ponto: Coordenadas; aoMudar: (p: Coordenadas) => void }) {
  return (
    <View style={{ height: 120, borderRadius: raio, backgroundColor: cores.fundoSuave, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ color: cores.textoSuave }}>
        Ponto: {ponto.latitude.toFixed(5)}, {ponto.longitude.toFixed(5)}
      </Text>
    </View>
  );
}
