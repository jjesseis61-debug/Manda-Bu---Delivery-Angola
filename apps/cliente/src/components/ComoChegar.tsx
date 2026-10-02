import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Text } from 'react-native';

import { Botao, Cartao } from '@/components/ui';
import { localizacaoCozinha } from '@/lib/api';
import { urlComoChegar } from '@/lib/mapa';
import { cores } from '@/lib/tema';
import type { LocalizacaoCozinha } from '@/lib/tipos';

import { MapaPontos } from './MapaPontos';

/** I10. Morada da cozinha e botão que abre a navegação do Google Maps. Sem localização pública não mostra nada. */
export function ComoChegar({ cozinhaId, comMapa = false }: { cozinhaId: string; comMapa?: boolean }) {
  const [local, setLocal] = useState<LocalizacaoCozinha | null>(null);

  useFocusEffect(
    useCallback(() => {
      localizacaoCozinha(cozinhaId)
        .then(setLocal)
        .catch(() => setLocal(null));
    }, [cozinhaId]),
  );

  if (!local) return null;
  return (
    <Cartao>
      <Text style={{ fontSize: 15, fontWeight: '600' }}>📍 {local.nome}</Text>
      {local.morada && <Text>{local.morada}</Text>}
      {local.horario && <Text style={{ color: cores.textoSuave }}>{local.horario}</Text>}
      {comMapa && <MapaPontos marcadores={[{ lat: local.lat, lng: local.lng, titulo: local.nome, cor: cores.marca }]} altura={180} />}
      <Botao titulo="Como chegar" variante="secundario" aoCarregar={() => Linking.openURL(urlComoChegar(local))} />
    </Cartao>
  );
}
