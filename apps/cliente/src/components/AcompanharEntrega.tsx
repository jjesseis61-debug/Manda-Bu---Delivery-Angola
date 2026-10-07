import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Dimensions, Modal, Text, View } from 'react-native';

import { Cartao, Paragrafo } from '@/components/ui';
import { posicaoEntrega } from '@/lib/api';
import { haQuantoTempo } from '@/lib/mapa';
import { cores, espaco } from '@/lib/tema';
import type { PosicaoEntrega } from '@/lib/tipos';

import { MapaPontos, type Marcador } from './MapaPontos';

const INTERVALO_MS = 10_000;

/** I11. Onde está o estafeta, actualizado a cada 10 s enquanto o ecrã está aberto e o pedido a caminho */
export function AcompanharEntrega({ pedidoId, aoTerminar }: { pedidoId: string; aoTerminar: () => void }) {
  const [posicao, setPosicao] = useState<PosicaoEntrega | null>(null);
  // Mapa de rota em ecrã inteiro (abre ao tocar no mapa pequeno)
  const [emEcraInteiro, setEmEcraInteiro] = useState(false);

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
  const tempo = posicao.minutos != null ? `Chega daqui a ~${posicao.minutos} min` : 'O estafeta está a caminho';

  return (
    <Cartao>
      {posicao.estafeta ? (
        <>
          <Text style={{ fontSize: 16, fontWeight: '700' }}>{tempo}</Text>
          {marcadores.length > 0 && (
            <>
              <MapaPontos marcadores={marcadores} interactivo />
              <Text
                accessibilityRole="button"
                accessibilityLabel="Abrir o mapa de rota em ecrã inteiro"
                style={{ color: cores.marca, fontWeight: '600' }}
                onPress={() => setEmEcraInteiro(true)}>
                Arrasta o mapa para explorar · toca aqui para o ver em ecrã inteiro.
              </Text>
            </>
          )}
          <Paragrafo suave>
            {posicao.distancia_km != null ? `A ${String(posicao.distancia_km).replace('.', ',')} km · ` : ''}
            actualizado {haQuantoTempo(posicao.estafeta.actualizado_em)}. Tempo estimado pela distância.
          </Paragrafo>

          <Modal visible={emEcraInteiro} animationType="slide" onRequestClose={() => setEmEcraInteiro(false)}>
            <View style={{ flex: 1, backgroundColor: cores.fundo, padding: espaco.m, gap: espaco.s }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 18, fontWeight: '700', flex: 1 }}>{tempo}</Text>
                <Text
                  accessibilityRole="button"
                  style={{ color: cores.marca, fontWeight: '700', fontSize: 16, paddingHorizontal: espaco.s }}
                  onPress={() => setEmEcraInteiro(false)}>
                  Fechar
                </Text>
              </View>
              <MapaPontos marcadores={marcadores} interactivo altura={Dimensions.get('window').height - 160} />
              <Paragrafo suave>
                🔴 Estafeta · 🔵 Entrega. {posicao.distancia_km != null ? `A ${String(posicao.distancia_km).replace('.', ',')} km · ` : ''}
                actualizado {haQuantoTempo(posicao.estafeta.actualizado_em)}.
              </Paragrafo>
            </View>
          </Modal>
        </>
      ) : (
        <Paragrafo suave>O estafeta está a caminho. A localização aparece aqui quando ele a partilhar.</Paragrafo>
      )}
    </Cartao>
  );
}
