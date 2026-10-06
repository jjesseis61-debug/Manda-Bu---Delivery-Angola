import { Camera, Map, Marker as MarcadorOsm } from '@maplibre/maplibre-react-native';
import { StyleSheet, View } from 'react-native';
import MapView, { Marker } from 'react-native-maps';

import { limitesPara, regiaoPara } from '@/lib/mapa';
import { estiloOsm } from '@/lib/mapaEstilo';
import { GOOGLE_DISPONIVEL } from '@/lib/mapaNativo';
import { useSessao } from '@/lib/sessao';
import { raio } from '@/lib/tema';
import type { Ponto } from '@/lib/tipos';

export type Marcador = Ponto & { titulo: string; cor: string };

/**
 * Mapa só de leitura com um ou mais marcadores (cozinha; estafeta e destino).
 * Por defeito usa o OpenStreetMap (grátis). Com o interruptor `mapa_google` e a chave no build,
 * usa o Google/Apple Maps.
 */
export function MapaPontos({ marcadores, altura = 220 }: { marcadores: Marcador[]; altura?: number }) {
  const { ligada } = useSessao();
  if (marcadores.length === 0) return null;
  const usarGoogle = GOOGLE_DISPONIVEL && ligada('mapa_google');
  return (
    <View style={[estilos.caixa, { height: altura }]}>
      {usarGoogle ? <Google marcadores={marcadores} /> : <Osm marcadores={marcadores} />}
    </View>
  );
}

function Google({ marcadores }: { marcadores: Marcador[] }) {
  return (
    <MapView style={StyleSheet.absoluteFill} region={regiaoPara(marcadores)} scrollEnabled={false} zoomEnabled={false}>
      {marcadores.map((m) => (
        <Marker key={m.titulo} coordinate={{ latitude: m.lat, longitude: m.lng }} title={m.titulo} pinColor={m.cor} />
      ))}
    </MapView>
  );
}

function Osm({ marcadores }: { marcadores: Marcador[] }) {
  const [oeste, sul, este, norte] = limitesPara(marcadores);
  return (
    <Map
      style={StyleSheet.absoluteFill}
      mapStyle={estiloOsm}
      logo={false}
      compass={false}
      dragPan={false}
      touchZoom={false}
      doubleTapZoom={false}
      touchRotate={false}
      touchPitch={false}>
      {marcadores.length === 1 ? (
        <Camera center={[marcadores[0].lng, marcadores[0].lat]} zoom={14} />
      ) : (
        <Camera bounds={[oeste, sul, este, norte]} padding={{ top: 40, right: 40, bottom: 40, left: 40 }} />
      )}
      {marcadores.map((m) => (
        <MarcadorOsm key={m.titulo} id={m.titulo} lngLat={[m.lng, m.lat]}>
          <View style={[estilos.pin, { backgroundColor: m.cor }]} />
        </MarcadorOsm>
      ))}
    </Map>
  );
}

const estilos = StyleSheet.create({
  caixa: { borderRadius: raio, overflow: 'hidden' },
  pin: { width: 18, height: 18, borderRadius: 9, borderWidth: 2, borderColor: '#fff' },
});
