import { Camera, Map, Marker as MarcadorOsm, type CameraRef, type PressEvent } from '@maplibre/maplibre-react-native';
import { useEffect, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import type { NativeSyntheticEvent } from 'react-native';
import MapView, { Marker, type MapPressEvent } from 'react-native-maps';

import { estiloMapa } from '@/lib/mapaEstilo';
import { GOOGLE_DISPONIVEL } from '@/lib/mapaNativo';
import { useSessao } from '@/lib/sessao';
import { cores, raio } from '@/lib/tema';

export type Coordenadas = { latitude: number; longitude: number };

type MapaProps = {
  ponto: Coordenadas;
  aoMudar: (p: Coordenadas) => void;
  /** Quando muda, o mapa desliza para aqui (ex.: centro do bairro escolhido). Não mexe no pino. */
  centrarEm?: Coordenadas;
};

/**
 * Pin no mapa: toca no mapa para marcar o ponto de entrega.
 * Por defeito usa o OpenStreetMap (grátis). Com o interruptor `mapa_google` e a chave no build,
 * usa o Google/Apple Maps (onde o pin também se pode arrastar).
 */
export function MapaPin({ ponto, aoMudar, centrarEm }: MapaProps) {
  const { ligada } = useSessao();
  const usarGoogle = GOOGLE_DISPONIVEL && ligada('mapa_google');
  return (
    <View style={estilos.caixa}>
      {usarGoogle ? <Google ponto={ponto} aoMudar={aoMudar} centrarEm={centrarEm} /> : <Osm ponto={ponto} aoMudar={aoMudar} centrarEm={centrarEm} />}
    </View>
  );
}

function Google({ ponto, aoMudar, centrarEm }: MapaProps) {
  const mapa = useRef<MapView>(null);
  useEffect(() => {
    if (centrarEm) mapa.current?.animateToRegion({ ...centrarEm, latitudeDelta: 0.01, longitudeDelta: 0.01 }, 500);
  }, [centrarEm]);
  return (
    <MapView
      ref={mapa}
      style={StyleSheet.absoluteFill}
      initialRegion={{ ...ponto, latitudeDelta: 0.01, longitudeDelta: 0.01 }}
      onPress={(e: MapPressEvent) => aoMudar(e.nativeEvent.coordinate)}>
      <Marker coordinate={ponto} draggable onDragEnd={(e) => aoMudar(e.nativeEvent.coordinate)} />
    </MapView>
  );
}

function Osm({ ponto, aoMudar, centrarEm }: MapaProps) {
  const camara = useRef<CameraRef>(null);
  useEffect(() => {
    if (centrarEm) camara.current?.flyTo({ center: [centrarEm.longitude, centrarEm.latitude], duration: 500 });
  }, [centrarEm]);
  return (
    <Map
      style={StyleSheet.absoluteFill}
      mapStyle={estiloMapa}
      logo={false}
      compass={false}
      touchRotate={false}
      touchPitch={false}
      onPress={(e: NativeSyntheticEvent<PressEvent>) => {
        const [lng, lat] = e.nativeEvent.lngLat;
        aoMudar({ latitude: lat, longitude: lng });
      }}>
      <Camera ref={camara} initialViewState={{ center: [ponto.longitude, ponto.latitude], zoom: 15 }} />
      <MarcadorOsm id="pin" lngLat={[ponto.longitude, ponto.latitude]}>
        <View style={estilos.pin} />
      </MarcadorOsm>
    </Map>
  );
}

const estilos = StyleSheet.create({
  caixa: { height: 260, borderRadius: raio, overflow: 'hidden' },
  pin: { width: 20, height: 20, borderRadius: 10, backgroundColor: cores.marca, borderWidth: 3, borderColor: '#fff' },
});
