import { useEffect, useState } from 'react';

import { posicaoPedido } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import type { PosicaoPedido } from '@/lib/tipos';

import { Aviso, Paragrafo } from './ui';

const INTERVALO_MS = 10_000;

/** Na web não há mapa nativo: mostra as coordenadas (a app do telemóvel mostra o mapa vivo). */
export function AcompanharPedido({ pedidoId }: { pedidoId: string; altura?: number }) {
  const [pos, setPos] = useState<PosicaoPedido | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let activo = true;
    const ler = () =>
      posicaoPedido(pedidoId)
        .then((p) => activo && (setPos(p), setErro(null)))
        .catch((e) => activo && setErro(mensagemErro(e)));
    void ler();
    const t = setInterval(ler, INTERVALO_MS);
    return () => {
      activo = false;
      clearInterval(t);
    };
  }, [pedidoId]);

  if (erro) return <Aviso tipo="erro">{erro}</Aviso>;
  if (!pos) return <Paragrafo suave>A carregar…</Paragrafo>;
  if (!pos.activo) return <Paragrafo suave>Este pedido já não está a caminho.</Paragrafo>;
  if (!pos.estafeta) return <Paragrafo suave>{(pos.estafeta_nome ?? 'O estafeta')} vai a caminho. À espera da localização.</Paragrafo>;

  return (
    <Paragrafo suave>
      {pos.estafeta_nome ?? 'Estafeta'}: {pos.estafeta.lat.toFixed(5)}, {pos.estafeta.lng.toFixed(5)}
      {pos.distancia_km != null ? ` · a ${String(pos.distancia_km).replace('.', ',')} km` : ''}
      {pos.minutos != null ? ` · ~${pos.minutos} min` : ''}
    </Paragrafo>
  );
}
