import { StyleSheet, View } from 'react-native';
import MapView, { Marker } from 'react-native-maps';

import { regiaoPara } from '@/lib/mapa';
import { raio } from '@/lib/tema';
import type { Ponto } from '@/lib/tipos';

export type Marcador = Ponto & { titulo: string; cor: string };

/** Mapa só de leitura com um ou mais marcadores (cozinha; estafeta e destino) */
export function MapaPontos({ marcadores, altura = 220 }: { marcadores: Marcador[]; altura?: number }) {
  return (
    <View style={[estilos.caixa, { height: altura }]}>
      <MapView style={StyleSheet.absoluteFill} region={regiaoPara(marcadores)} scrollEnabled={false} zoomEnabled={false}>
        {marcadores.map((m) => (
          <Marker key={m.titulo} coordinate={{ latitude: m.lat, longitude: m.lng }} title={m.titulo} pinColor={m.cor} />
        ))}
      </MapView>
    </View>
  );
}

const estilos = StyleSheet.create({
  caixa: { borderRadius: raio, overflow: 'hidden' },
});
