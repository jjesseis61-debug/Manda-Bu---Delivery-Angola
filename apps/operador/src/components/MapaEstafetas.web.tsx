import { Text, View } from 'react-native';

import { cores, raio } from '@/lib/tema';
import type { PosicaoEstafeta } from '@/lib/tipos';

/** Na web não há mapa nativo: lista os estafetas e as coordenadas (a app do telemóvel mostra o mapa). */
export function MapaEstafetas({ estafetas }: { estafetas: PosicaoEstafeta[]; altura?: number }) {
  return (
    <View style={{ borderRadius: raio, backgroundColor: cores.fundoSuave, padding: 16, gap: 4 }}>
      {estafetas.map((e) => (
        <Text key={e.funcionario_id} style={{ color: cores.textoSuave }}>
          {e.nome}: {e.lat.toFixed(5)}, {e.lng.toFixed(5)} · {e.pedidos_a_levar} pedido(s)
        </Text>
      ))}
    </View>
  );
}
