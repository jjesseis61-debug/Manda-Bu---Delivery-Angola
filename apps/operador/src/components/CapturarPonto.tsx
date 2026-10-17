import { Camera, Map, Marker, type PressEvent } from '@maplibre/maplibre-react-native';
import * as Location from 'expo-location';
import { useState } from 'react';
import { Linking, Platform, Pressable, StyleSheet, Text, View, type NativeSyntheticEvent } from 'react-native';

import { Aviso, Botao, Campo, Paragrafo } from '@/components/ui';
import { extrairCoordenadas } from '@/lib/coordenadas';
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
  aoSugerirMorada,
  altura = 280,
}: {
  lat: string;
  lng: string;
  aoMudar: (lat: string, lng: string) => void;
  /** Quando dado, mostra um botão para preencher a morada a partir do ponto (reverse geocode) */
  aoSugerirMorada?: (morada: string) => void;
  altura?: number;
}) {
  const [erro, setErro] = useState<string | null>(null);
  const [aLocalizar, setALocalizar] = useState(false);
  const [procura, setProcura] = useState('');
  const [aProcurar, setAProcurar] = useState(false);
  const [colado, setColado] = useState('');
  const [aMorada, setAMorada] = useState(false);

  const vLat = numero(lat, 90);
  const vLng = numero(lng, 180);
  const temPonto = vLat !== null && vLng !== null;
  const centro: [number, number] = temPonto ? [vLng, vLat] : [LUANDA.lng, LUANDA.lat];
  const [zoom, setZoom] = useState(temPonto ? 16 : 12);
  const ajustarZoom = (d: number) => setZoom((z) => Math.min(20, Math.max(3, z + d)));

  // Ao escolher um ponto (toque, GPS, procura, colar) aproxima para ser fácil afinar
  const definir = (la: number, lo: number) => {
    aoMudar(la.toFixed(6), lo.toFixed(6));
    setZoom((z) => Math.max(z, 16));
  };

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

  // Procurar por morada/nome (geocoder do próprio telemóvel — sem chave Google)
  async function procurarMorada() {
    const q = procura.trim();
    if (!q || aProcurar) return;
    setErro(null);
    setAProcurar(true);
    try {
      const r = await Location.geocodeAsync(q);
      if (r[0]) definir(r[0].latitude, r[0].longitude);
      else setErro('Não encontrei essa morada. Tenta algo mais específico, ou cola as coordenadas do Google Maps.');
    } catch {
      setErro('Este telemóvel não conseguiu procurar a morada. Cola as coordenadas do Google Maps.');
    } finally {
      setAProcurar(false);
    }
  }

  // Preencher a morada a partir do ponto marcado (reverse geocode do sistema)
  async function preencherMorada() {
    if (!aoSugerirMorada || vLat === null || vLng === null || aMorada) return;
    setErro(null);
    setAMorada(true);
    try {
      const r = await Location.reverseGeocodeAsync({ latitude: vLat, longitude: vLng });
      const a = r[0];
      const partes = a ? [a.street || a.name, a.district || a.subregion, a.city || a.region].filter((p): p is string => !!p) : [];
      if (partes.length) aoSugerirMorada([...new Set(partes)].join(', '));
      else setErro('Não consegui obter a morada deste ponto. Escreve-a à mão.');
    } catch {
      setErro('Este telemóvel não conseguiu obter a morada do ponto. Escreve-a à mão.');
    } finally {
      setAMorada(false);
    }
  }

  // Trazer um ponto do Google Maps: coordenadas coladas ("-8.94, 13.37") ou um link que as contenha
  function aplicarColado() {
    const c = extrairCoordenadas(colado);
    if (c) {
      definir(c[0], c[1]);
      setColado('');
      setErro(null);
    } else {
      setErro('Não encontrei coordenadas. Cola "-8.944707, 13.376525" ou um link do Google Maps com os números.');
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
            <Camera center={centro} zoom={zoom} duration={300} />
            {temPonto && (
              <Marker id="ponto" lngLat={[vLng, vLat]}>
                <View style={estilos.pin} />
              </Marker>
            )}
          </Map>
          {/* Botões de zoom (o mapa pequeno é difícil de aproximar só com os dedos) */}
          <View style={estilos.zoomBotoes}>
            <Pressable onPress={() => ajustarZoom(1)} accessibilityLabel="Aproximar" style={estilos.zoomBotao}>
              <Text style={estilos.zoomTexto}>＋</Text>
            </Pressable>
            <Pressable onPress={() => ajustarZoom(-1)} accessibilityLabel="Afastar" style={estilos.zoomBotao}>
              <Text style={estilos.zoomTexto}>－</Text>
            </Pressable>
          </View>
        </View>
      )}
      {HA_MAPA && <Paragrafo suave>Toca no mapa para marcar o ponto (usa ＋ / － para aproximar), ou usa a localização actual.</Paragrafo>}
      <Botao
        titulo={aLocalizar ? 'A localizar…' : 'Usar a localização actual'}
        variante="secundario"
        aoCarregar={usarActual}
        aCarregar={aLocalizar}
      />

      {/* Procurar por morada/nome: o telemóvel encontra o ponto (sem Google Maps) */}
      <Campo
        rotulo="Procurar morada"
        placeholder="Ex.: Vila Chinesa, Viana"
        value={procura}
        onChangeText={setProcura}
        onSubmitEditing={procurarMorada}
      />
      <Botao titulo={aProcurar ? 'A procurar…' : 'Procurar'} variante="secundario" aoCarregar={procurarMorada} aCarregar={aProcurar} />

      {/* Trazer um ponto do Google Maps para aqui */}
      <Campo
        rotulo="Colar do Google Maps"
        placeholder="-8.944707, 13.376525 ou um link"
        value={colado}
        onChangeText={setColado}
        onSubmitEditing={aplicarColado}
      />
      <Paragrafo suave>No Google Maps, carrega longo no sítio e copia os números que aparecem; cola-os aqui e toca em Aplicar.</Paragrafo>
      <Botao titulo="Aplicar" variante="secundario" desactivado={colado.trim() === ''} aoCarregar={aplicarColado} />

      <View style={{ flexDirection: 'row', gap: espaco.s }}>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Latitude" value={lat} keyboardType="numbers-and-punctuation" onChangeText={(t) => aoMudar(t, lng)} />
        </View>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Longitude" value={lng} keyboardType="numbers-and-punctuation" onChangeText={(t) => aoMudar(lat, t)} />
        </View>
      </View>
      {temPonto && aoSugerirMorada && (
        <Botao titulo={aMorada ? 'A obter morada…' : 'Preencher a morada deste ponto'} variante="texto" aoCarregar={preencherMorada} aCarregar={aMorada} />
      )}
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
  zoomBotoes: { position: 'absolute', top: espaco.s, right: espaco.s, gap: espaco.xs },
  zoomBotao: {
    width: 40,
    height: 40,
    borderRadius: 8,
    backgroundColor: '#FFFFFF',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: cores.contorno,
    elevation: 2,
  },
  zoomTexto: { fontSize: 22, fontWeight: '700', color: cores.texto, lineHeight: 26 },
});
