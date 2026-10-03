import { StyleSheet, Text, View } from 'react-native';
import MapView, { Marker, type MapPressEvent } from 'react-native-maps';

import { MAPA_NATIVO } from '@/lib/mapaNativo';
import { cores, raio } from '@/lib/tema';

export type Coordenadas = { latitude: number; longitude: number };

/** Pin no mapa: toca no mapa ou arrasta o pin para marcar o ponto de entrega */
export function MapaPin({ ponto, aoMudar }: { ponto: Coordenadas; aoMudar: (p: Coordenadas) => void }) {
  if (!MAPA_NATIVO) return <SemMapa ponto={ponto} />;
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

/** Sem mapa neste build: o ponto marca-se com "Usar a minha localização" */
function SemMapa({ ponto }: { ponto: Coordenadas }) {
  return (
    <View style={estilos.semMapa}>
      <Text style={{ color: cores.textoSuave, textAlign: 'center' }}>
        O mapa ainda não está disponível nesta versão. Usa a tua localização para marcar o ponto de entrega.
      </Text>
      <Text style={{ color: cores.textoSuave }}>
        Ponto: {ponto.latitude.toFixed(5)}, {ponto.longitude.toFixed(5)}
      </Text>
    </View>
  );
}

const estilos = StyleSheet.create({
  caixa: { height: 260, borderRadius: raio, overflow: 'hidden' },
  semMapa: { borderRadius: raio, backgroundColor: cores.fundoSuave, padding: 16, gap: 6, alignItems: 'center' },
});
