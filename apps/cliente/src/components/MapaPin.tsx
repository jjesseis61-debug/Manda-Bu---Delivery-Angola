import { StyleSheet, View } from 'react-native';
import MapView, { Marker, type MapPressEvent } from 'react-native-maps';

import { raio } from '@/lib/tema';

export type Coordenadas = { latitude: number; longitude: number };

/** Pin no mapa: toca no mapa ou arrasta o pin para marcar o ponto de entrega */
export function MapaPin({ ponto, aoMudar }: { ponto: Coordenadas; aoMudar: (p: Coordenadas) => void }) {
  return (
    <View style={estilos.caixa}>
      <MapView
        style={StyleSheet.absoluteFill}
        region={{ ...ponto, latitudeDelta: 0.01, longitudeDelta: 0.01 }}
        onPress={(e: MapPressEvent) => aoMudar(e.nativeEvent.coordinate)}>
        <Marker coordinate={ponto} draggable onDragEnd={(e) => aoMudar(e.nativeEvent.coordinate)} />
      </MapView>
    </View>
  );
}

const estilos = StyleSheet.create({
  caixa: { height: 260, borderRadius: raio, overflow: 'hidden' },
});
