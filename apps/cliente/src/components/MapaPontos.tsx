import { Camera, GeoJSONSource, Layer, Map, Marker as MarcadorOsm } from '@maplibre/maplibre-react-native';
import type { Feature, LineString } from 'geojson';
import { StyleSheet, View } from 'react-native';
import MapView, { Marker, Polyline } from 'react-native-maps';

import { limitesPara, regiaoPara } from '@/lib/mapa';
import { estiloMapa } from '@/lib/mapaEstilo';
import { GOOGLE_DISPONIVEL } from '@/lib/mapaNativo';
import { useSessao } from '@/lib/sessao';
import { cores, raio } from '@/lib/tema';
import type { Ponto } from '@/lib/tipos';

export type Marcador = Ponto & { titulo: string; cor: string };

/**
 * Mapa só de leitura com um ou mais marcadores (cozinha; estafeta e destino).
 * Por defeito usa o OpenStreetMap (grátis). Com o interruptor `mapa_google` e a chave no build,
 * usa o Google/Apple Maps.
 */
export function MapaPontos({
  marcadores,
  altura = 220,
  interactivo = false,
  rota,
}: {
  marcadores: Marcador[];
  altura?: number;
  /** Ecrã inteiro: permite arrastar e aproximar o mapa (o preview é estático) */
  interactivo?: boolean;
  /** Linha da rota por estrada (Gate B); quando ausente, mostram-se só os marcadores */
  rota?: Ponto[];
}) {
  const { ligada } = useSessao();
  if (marcadores.length === 0) return null;
  const usarGoogle = GOOGLE_DISPONIVEL && ligada('mapa_google');
  const linha = rota && rota.length > 1 ? rota : undefined;
  return (
    <View style={[estilos.caixa, { height: altura }]}>
      {usarGoogle ? (
        <Google marcadores={marcadores} interactivo={interactivo} rota={linha} />
      ) : (
        <Osm marcadores={marcadores} interactivo={interactivo} rota={linha} />
      )}
    </View>
  );
}

function Google({ marcadores, interactivo, rota }: { marcadores: Marcador[]; interactivo: boolean; rota?: Ponto[] }) {
  return (
    <MapView style={StyleSheet.absoluteFill} region={regiaoPara(marcadores)} scrollEnabled={interactivo} zoomEnabled={interactivo}>
      {rota && (
        <Polyline coordinates={rota.map((p) => ({ latitude: p.lat, longitude: p.lng }))} strokeColor={cores.marca} strokeWidth={4} />
      )}
      {marcadores.map((m) => (
        <Marker key={m.titulo} coordinate={{ latitude: m.lat, longitude: m.lng }} title={m.titulo} pinColor={m.cor} />
      ))}
    </MapView>
  );
}

function Osm({ marcadores, interactivo, rota }: { marcadores: Marcador[]; interactivo: boolean; rota?: Ponto[] }) {
  const [oeste, sul, este, norte] = limitesPara(marcadores);
  // Pontos quase no mesmo sítio (ex.: estafeta junto ao destino): centra, não faz zoom excessivo
  const juntos = marcadores.length === 1 || (este - oeste < 0.004 && norte - sul < 0.004);
  const linhaGeo: Feature<LineString> | undefined = rota
    ? { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: rota.map((p) => [p.lng, p.lat]) } }
    : undefined;
  return (
    <Map
      style={StyleSheet.absoluteFill}
      mapStyle={estiloMapa}
      logo={false}
      compass={false}
      dragPan={interactivo}
      touchZoom={interactivo}
      doubleTapZoom={interactivo}
      touchRotate={false}
      touchPitch={false}>
      {juntos ? (
        <Camera center={[(oeste + este) / 2, (sul + norte) / 2]} zoom={15} />
      ) : (
        <Camera bounds={[oeste, sul, este, norte]} padding={{ top: 40, right: 40, bottom: 40, left: 40 }} />
      )}
      {linhaGeo && (
        <GeoJSONSource id="rota" data={linhaGeo}>
          <Layer id="rota-linha" type="line" source="rota" paint={{ 'line-color': cores.marca, 'line-width': 4 }} />
        </GeoJSONSource>
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
