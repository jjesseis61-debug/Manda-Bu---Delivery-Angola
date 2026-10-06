import { Camera, Map, Marker } from '@maplibre/maplibre-react-native';
import { StyleSheet, Text, View } from 'react-native';

import { estiloMapa } from '@/lib/mapaEstilo';
import { cores, raio } from '@/lib/tema';
import type { PosicaoEstafeta } from '@/lib/tipos';

/** Mapa (OpenStreetMap) com os estafetas de serviço, só leitura. Assume pelo menos um estafeta. */
export function MapaEstafetas({ estafetas, altura = 300 }: { estafetas: PosicaoEstafeta[]; altura?: number }) {
  const lats = estafetas.map((e) => e.lat);
  const lngs = estafetas.map((e) => e.lng);
  const oeste = Math.min(...lngs);
  const este = Math.max(...lngs);
  const sul = Math.min(...lats);
  const norte = Math.max(...lats);
  // Estafetas quase no mesmo sítio: centra, não faz zoom excessivo
  const juntos = estafetas.length === 1 || (este - oeste < 0.004 && norte - sul < 0.004);
  return (
    <View style={[estilos.caixa, { height: altura }]}>
      <Map
        style={StyleSheet.absoluteFill}
        mapStyle={estiloMapa}
        logo={false}
        compass={false}
        touchRotate={false}
        touchPitch={false}>
        {juntos ? (
          <Camera center={[(oeste + este) / 2, (sul + norte) / 2]} zoom={14} />
        ) : (
          <Camera bounds={[oeste, sul, este, norte]} padding={{ top: 48, right: 48, bottom: 48, left: 48 }} />
        )}
        {estafetas.map((e) => (
          <Marker key={e.funcionario_id} id={e.funcionario_id} lngLat={[e.lng, e.lat]}>
            <View style={estilos.marcador}>
              <Text style={estilos.nome} numberOfLines={1}>
                {e.nome}
              </Text>
              <View style={estilos.pin} />
            </View>
          </Marker>
        ))}
      </Map>
    </View>
  );
}

const estilos = StyleSheet.create({
  caixa: { borderRadius: raio, overflow: 'hidden' },
  marcador: { alignItems: 'center', maxWidth: 140 },
  nome: {
    backgroundColor: 'rgba(255,255,255,0.9)',
    color: cores.texto,
    fontSize: 11,
    fontWeight: '700',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 8,
    overflow: 'hidden',
    marginBottom: 2,
  },
  pin: { width: 16, height: 16, borderRadius: 8, backgroundColor: cores.marca, borderWidth: 2, borderColor: '#fff' },
});
