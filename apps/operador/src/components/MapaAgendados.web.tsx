import { Text, View } from 'react-native';

import type { ParagemMapa } from '@/lib/agendados';
import { cores, raio } from '@/lib/tema';

/** Na web não há mapa nativo: lista as paragens por hora (a app do telemóvel mostra o mapa). */
export function MapaAgendados({ paragens }: { paragens: ParagemMapa[]; altura?: number }) {
  return (
    <View style={{ borderRadius: raio, backgroundColor: cores.fundoSuave, padding: 16, gap: 4 }}>
      {paragens.map((p) => (
        <Text key={p.id} style={{ color: p.alerta ? cores.erro : cores.textoSuave }}>
          {p.rotulo}
          {p.zona ? ` · ${p.zona}` : ''}
        </Text>
      ))}
    </View>
  );
}
