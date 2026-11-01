import { Text, View } from 'react-native';

import { cores, raio } from '@/lib/tema';

export type PontoEntrega = { id: string; lat: number; lng: number; titulo: string; aCaminho?: boolean };

/** Na web não há mapa nativo: lista os destinos e coordenadas (o telemóvel mostra o mapa). */
export function MapaEntregas({ pontos }: { pontos: PontoEntrega[]; altura?: number }) {
  return (
    <View style={{ borderRadius: raio, backgroundColor: cores.fundoSuave, padding: 16, gap: 4 }}>
      {pontos.map((p) => (
        <Text key={p.id} style={{ color: cores.textoSuave }}>
          {p.titulo}: {p.lat.toFixed(5)}, {p.lng.toFixed(5)}
        </Text>
      ))}
    </View>
  );
}
