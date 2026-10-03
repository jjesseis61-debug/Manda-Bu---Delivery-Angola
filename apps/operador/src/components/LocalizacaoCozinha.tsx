import * as Location from 'expo-location';
import { useEffect, useState } from 'react';
import { Linking, Switch, Text, View } from 'react-native';

import { Aviso, Botao, Campo, Cartao, Paragrafo, Subtitulo } from '@/components/ui';
import { guardarLocalizacao, lerLocalizacao } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';

type Edicao = { id?: string; morada: string; horario: string; lat: string; lng: string; publica: boolean };

const coordenada = (t: string, limite: number) => {
  const n = Number(t.replace(',', '.'));
  return t.trim() !== '' && Number.isFinite(n) && Math.abs(n) <= limite ? n : null;
};

/** I10. Morada e ponto da cozinha para o "Como chegar" dos clientes (só aparece com a autorização da responsável) */
export function LocalizacaoCozinha({ cozinhaId }: { cozinhaId: string }) {
  const [l, setL] = useState<Edicao | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    lerLocalizacao(cozinhaId)
      .then((x) =>
        setL(
          x
            ? { id: x.id, morada: x.morada ?? '', horario: x.horario ?? '', lat: String(x.lat), lng: String(x.lng), publica: x.publica }
            : { morada: '', horario: '', lat: '', lng: '', publica: false },
        ),
      )
      .catch((e) => setErro(mensagemErro(e)));
  }, [cozinhaId]);

  if (!l) return erro ? <Aviso tipo="erro">{erro}</Aviso> : null;

  const lat = coordenada(l.lat, 90);
  const lng = coordenada(l.lng, 180);

  async function aquiMesmo() {
    setErro(null);
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') {
      setErro('Sem autorização para usar a localização. Escreve as coordenadas.');
      return;
    }
    const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
    setL((x) => x && { ...x, lat: pos.coords.latitude.toFixed(6), lng: pos.coords.longitude.toFixed(6) });
  }

  async function guardar() {
    if (!l || lat === null || lng === null) return;
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await guardarLocalizacao({
        id: l.id,
        cozinha_id: cozinhaId,
        morada: l.morada.trim() || null,
        horario: l.horario.trim() || null,
        lat,
        lng,
        publica: l.publica,
      });
      const x = await lerLocalizacao(cozinhaId);
      if (x) setL({ ...l, id: x.id });
      setSucesso('Localização guardada.');
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <Cartao>
      <Subtitulo>Localização (&quot;Como chegar&quot;)</Subtitulo>
      <Paragrafo suave>Os clientes vêem a morada e um botão que abre o Google Maps até aqui.</Paragrafo>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
      <Campo rotulo="Morada" value={l.morada} onChangeText={(t) => setL({ ...l, morada: t })} />
      <Campo rotulo="Horário (ex.: Seg–Sex 10h–15h)" value={l.horario} onChangeText={(t) => setL({ ...l, horario: t })} />
      <View style={{ flexDirection: 'row', gap: espaco.s }}>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Latitude" value={l.lat} keyboardType="numbers-and-punctuation" onChangeText={(t) => setL({ ...l, lat: t })} />
        </View>
        <View style={{ flex: 1 }}>
          <Campo rotulo="Longitude" value={l.lng} keyboardType="numbers-and-punctuation" onChangeText={(t) => setL({ ...l, lng: t })} />
        </View>
      </View>
      <Botao titulo="Usar a localização deste telemóvel (estou na cozinha)" variante="secundario" aoCarregar={aquiMesmo} />
      {lat !== null && lng !== null && (
        <Botao
          titulo="Ver no Google Maps"
          variante="texto"
          aoCarregar={() => Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${lat},${lng}`)}
        />
      )}
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
        <Text style={{ flex: 1 }}>A responsável autorizou mostrar a localização aos clientes</Text>
        <Switch thumbColor="#FFFFFF" value={l.publica} onValueChange={(v) => setL({ ...l, publica: v })} trackColor={{ true: cores.marca, false: cores.contorno }} />
      </View>
      <Botao titulo="Guardar localização" aCarregar={ocupado} desactivado={lat === null || lng === null} aoCarregar={guardar} />
    </Cartao>
  );
}
