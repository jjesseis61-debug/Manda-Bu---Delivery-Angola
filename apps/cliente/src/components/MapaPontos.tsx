import { StyleSheet, Text, View } from 'react-native';
import MapView, { Marker } from 'react-native-maps';

import { regiaoPara } from '@/lib/mapa';
import { MAPA_NATIVO } from '@/lib/mapaNativo';
import { cores, raio } from '@/lib/tema';
import type { Ponto } from '@/lib/tipos';

export type Marcador = Ponto & { titulo: string; cor: string };

/** Mapa só de leitura com um ou mais marcadores (cozinha; estafeta e destino) */
export function MapaPontos({ marcadores, altura = 220 }: { marcadores: Marcador[]; altura?: number }) {
  // Sem mapa neste build (Android sem chave): os pontos em texto, como na web
  if (!MAPA_NATIVO)
    return (
      <View style={estilos.semMapa}>
        {marcadores.map((m) => (
          <Text key={m.titulo} style={{ color: cores.textoSuave }}>
            {m.titulo}: {m.lat.toFixed(5)}, {m.lng.toFixed(5)}
          </Text>
        ))}
      </View>
    );
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
  semMapa: { borderRadius: raio, backgroundColor: cores.fundoSuave, padding: 16, gap: 4 },
});
