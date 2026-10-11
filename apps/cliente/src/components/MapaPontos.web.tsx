import { Text, View } from 'react-native';

import { cores, raio } from '@/lib/tema';
import type { Ponto } from '@/lib/tipos';

export type Marcador = Ponto & { titulo: string; cor: string };

/** Na web não há mapa nativo: mostram-se os pontos em texto (a app do telemóvel mostra o mapa) */
export function MapaPontos({
  marcadores,
}: {
  marcadores: Marcador[];
  altura?: number;
  interactivo?: boolean;
  rota?: Ponto[];
}) {
  return (
    <View style={{ borderRadius: raio, backgroundColor: cores.fundoSuave, padding: 16, gap: 4 }}>
      {marcadores.map((m) => (
        <Text key={m.titulo} style={{ color: cores.textoSuave }}>
          {m.titulo}: {m.lat.toFixed(5)}, {m.lng.toFixed(5)}
        </Text>
      ))}
    </View>
  );
}
