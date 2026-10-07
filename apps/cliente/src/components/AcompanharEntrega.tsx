import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { Cartao, Paragrafo } from '@/components/ui';
import { posicaoEntrega } from '@/lib/api';
import { haQuantoTempo } from '@/lib/mapa';
import { cores } from '@/lib/tema';
import type { PosicaoEntrega } from '@/lib/tipos';

import { MapaPontos, type Marcador } from './MapaPontos';

const INTERVALO_MS = 10_000;

/** I11. Onde está o estafeta, actualizado a cada 10 s enquanto o ecrã está aberto e o pedido a caminho */
export function AcompanharEntrega({ pedidoId, aoTerminar }: { pedidoId: string; aoTerminar: () => void }) {
  const [posicao, setPosicao] = useState<PosicaoEntrega | null>(null);

  useFocusEffect(
    useCallback(() => {
      let activo = true;
      const ler = () =>
        posicaoEntrega(pedidoId)
          .then((p) => {
            if (!activo) return;
            setPosicao(p);
            // O pedido deixou de estar a caminho (entregue ou cancelado): o ecrã volta a ler o pedido
            if (!p.activo) aoTerminar();
          })
          .catch(() => undefined);
      void ler();
      const t = setInterval(ler, INTERVALO_MS);
      return () => {
        activo = false;
        clearInterval(t);
      };
    }, [pedidoId, aoTerminar]),
  );

  if (!posicao?.activo) return null;
  const marcadores: Marcador[] = [];
  if (posicao.estafeta) marcadores.push({ ...posicao.estafeta, titulo: 'Estafeta', cor: cores.marca });
  if (posicao.destino?.lat != null && posicao.destino?.lng != null) {
    marcadores.push({ lat: posicao.destino.lat, lng: posicao.destino.lng, titulo: 'Entrega', cor: '#1E88E5' });
  }

  return (
    <Cartao>
      {posicao.estafeta ? (
        <>
          <Text style={{ fontSize: 16, fontWeight: '700' }}>
            {posicao.minutos != null ? `Chega daqui a ~${posicao.minutos} min` : 'O estafeta está a caminho'}
          </Text>
          {marcadores.length > 0 && <MapaPontos marcadores={marcadores} />}
          <Paragrafo suave>
            {posicao.distancia_km != null ? `A ${String(posicao.distancia_km).replace('.', ',')} km · ` : ''}
            actualizado {haQuantoTempo(posicao.estafeta.actualizado_em)}. Tempo estimado pela distância.
          </Paragrafo>
        </>
      ) : (
        <Paragrafo suave>O estafeta está a caminho. A localização aparece aqui quando ele a partilhar.</Paragrafo>
      )}
    </Cartao>
  );
}
