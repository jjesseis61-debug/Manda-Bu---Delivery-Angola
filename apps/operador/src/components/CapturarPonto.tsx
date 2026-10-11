import { Camera, Map, Marker, type PressEvent } from '@maplibre/maplibre-react-native';
import * as Location from 'expo-location';
import { useState } from 'react';
import { Linking, Platform, StyleSheet, View, type NativeSyntheticEvent } from 'react-native';

import { Aviso, Botao, Campo, Paragrafo } from '@/components/ui';
import { mensagemErro } from '@/lib/formatar';
import { estiloMapa } from '@/lib/mapaEstilo';
import { cores, espaco, raio } from '@/lib/tema';

// O mapa só corre no telemóvel; na web fica só a captura/escrita das coordenadas.
const HA_MAPA = Platform.OS !== 'web';
// Centro de Luanda, só para abrir o mapa antes de haver ponto marcado
const LUANDA = { lat: -8.8383, lng: 13.2344 };

const numero = (t: string, limite: number): number | null => {
  const n = Number(t.replace(',', '.'));
  return t.trim() !== '' && Number.isFinite(n) && Math.abs(n) <= limite ? n : null;
};

/**
 * Captura de um ponto no mapa: botão "usar a localização actual", mapa tocável (OpenStreetMap)
 * e campos manuais. Partilhado pela cozinha (I10) e pelas zonas de entrega.
 * Opera sobre texto (lat/lng como strings) para encaixar nos formulários que já existem.
 */
export function CapturarPonto({
  lat,
  lng,
  aoMudar,
  altura = 220,
}: {
  lat: string;
  lng: string;
  aoMudar: (lat: string, lng: string) => void;
  altura?: number;
}) {
  const [erro, setErro] = useState<string | null>(null);
  const [aLocalizar, setALocalizar] = useState(false);

  const vLat = numero(lat, 90);
  const vLng = numero(lng, 180);
  const temPonto = vLat !== null && vLng !== null;
  const centro: [number, number] = temPonto ? [vLng, vLat] : [LUANDA.lng, LUANDA.lat];

  const definir = (la: number, lo: number) => aoMudar(la.toFixed(6), lo.toFixed(6));

  async function usarActual() {
    if (aLocalizar) return;
    setErro(null);
    setALocalizar(true);
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        setErro('Sem autorização para usar a localização. Escreve as coordenadas ou toca no mapa.');
        return;
      }
      const servicos = await Location.hasServicesEnabledAsync();
      if (!servicos) {
        setErro('A localização do telemóvel está desligada. Liga-a nas definições e tenta de novo.');
        return;
      }
      const conhecida = await Location.getLastKnownPositionAsync();
      if (conhecida) definir(conhecida.coords.latitude, conhecida.coords.longitude);
      const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      definir(pos.coords.latitude, pos.coords.longitude);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setALocalizar(false);
    }
  }

  return (
    <View>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {HA_MAPA && (
        <View style={[estilos.caixa, { height: altura }]}>
          <Map
            style={StyleSheet.absoluteFill}
            mapStyle={estiloMapa}
            logo={false}
            compass={false}
            touchRotate={false}
            touchPitch={false}
            onPress={(e: NativeSyntheticEvent<PressEvent>) => {
              const [lo, la] = e.nativeEvent.lngLat;
              definir(la, lo);
            }}>
            <Camera center={centro} zoom={temPonto ? 15 : 12} />
            {temPonto && (
              <Marker id="ponto" lngLat={[vLng, vLat]}>
                <View style={estilos.pin} />
              </Marker>
            )}
          </Map>
        </View>
      )}
      {HA_MAPA && <Paragrafo suave>Toca no mapa para marcar o ponto, ou usa a localização actual.</Paragrafo>}
      <Botao
        titulo={aLocalizar ? 'A localizar…' : 'Usar a localização actual'}
        variante="secundario"
        aoCarregar={usarActual}
        aCarregar={aLocalizar}
      />
      <View style={{ flexDirection: 'row', gap: espaco.s }}>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Latitude" value={lat} keyboardType="numbers-and-punctuation" onChangeText={(t) => aoMudar(t, lng)} />
        </View>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Longitude" value={lng} keyboardType="numbers-and-punctuation" onChangeText={(t) => aoMudar(lat, t)} />
        </View>
      </View>
      {temPonto && (
        <Botao
          titulo="Ver no Google Maps"
          variante="texto"
          aoCarregar={() => Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${vLat},${vLng}`)}
        />
      )}
    </View>
  );
}

const estilos = StyleSheet.create({
  caixa: { borderRadius: raio, overflow: 'hidden', marginBottom: espaco.s },
  pin: { width: 20, height: 20, borderRadius: 10, backgroundColor: cores.marca, borderWidth: 3, borderColor: '#fff' },
});
