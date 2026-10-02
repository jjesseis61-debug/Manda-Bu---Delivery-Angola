// I11. O estafeta partilha a posição enquanto tem pedidos a caminho e o ecrã de entregas está aberto.
// O servidor diz quantos pedidos estão a caminho com este estafeta; com 0 (ou o interruptor
// desligado) a app pára de enviar. Só em primeiro plano: sem localização em segundo plano.
import * as Location from 'expo-location';
import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';

import { registarPosicaoEntrega } from './api';

const OPCOES: Location.LocationOptions = {
  accuracy: Location.Accuracy.High,
  timeInterval: 15_000, // no máximo de 15 em 15 segundos
  distanceInterval: 30, // ou a cada 30 metros
};

/** `tentar`: há pedidos a caminho na lista e o funcionário regista entregas. `versao` muda a cada recarga da lista. */
export function usePartilharLocalizacao(tentar: boolean, versao: number) {
  const [aCaminho, setACaminho] = useState(0);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!tentar) {
        setACaminho(0);
        return;
      }
      let activo = true;
      let vigia: Location.LocationSubscription | null = null;
      const enviar = async (p: Location.LocationObject) => {
        const n = await registarPosicaoEntrega(p.coords.latitude, p.coords.longitude, p.coords.accuracy ?? null);
        if (!activo) return n;
        setACaminho(n);
        if (n === 0) {
          vigia?.remove();
          vigia = null;
        }
        return n;
      };
      (async () => {
        try {
          const { status } = await Location.requestForegroundPermissionsAsync();
          if (status !== 'granted') {
            setErro('Sem autorização de localização: o cliente não vê onde está a entrega.');
            return;
          }
          setErro(null);
          const n = await enviar(await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High }));
          if (activo && n > 0) {
            vigia = await Location.watchPositionAsync(OPCOES, (p) => void enviar(p).catch(() => undefined));
            if (!activo) vigia.remove();
          }
        } catch {
          // Sem rede ou sem GPS: tenta outra vez na próxima recarga da lista
        }
      })();
      return () => {
        activo = false;
        vigia?.remove();
      };
    }, [tentar, versao]),
  );

  return { aCaminho, erro };
}
