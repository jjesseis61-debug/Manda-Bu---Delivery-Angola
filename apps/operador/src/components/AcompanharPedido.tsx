import { Camera, Map, Marker } from '@maplibre/maplibre-react-native';
import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { posicaoPedido } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { estiloMapa } from '@/lib/mapaEstilo';
import { cores, raio } from '@/lib/tema';
import type { PosicaoPedido } from '@/lib/tipos';

import { Aviso, Paragrafo } from './ui';

const INTERVALO_MS = 10_000;

type Pino = { lat: number; lng: number; nome: string; cor: string };

/** Mapa vivo com o estafeta de um pedido (🔴) e o destino (🔵), para a cozinha acompanhar. */
export function AcompanharPedido({ pedidoId, altura = 320 }: { pedidoId: string; altura?: number }) {
  const [pos, setPos] = useState<PosicaoPedido | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let activo = true;
    const ler = () =>
      posicaoPedido(pedidoId)
        .then((p) => {
          if (activo) {
            setPos(p);
            setErro(null);
          }
        })
        .catch((e) => {
          if (activo) setErro(mensagemErro(e));
        });
    void ler();
    const t = setInterval(ler, INTERVALO_MS);
    return () => {
      activo = false;
      clearInterval(t);
    };
  }, [pedidoId]);

  if (erro) return <Aviso tipo="erro">{erro}</Aviso>;
  if (!pos) return <Paragrafo suave>A carregar o mapa…</Paragrafo>;
  if (!pos.activo) return <Paragrafo suave>Este pedido já não está a caminho.</Paragrafo>;

  const pinos: Pino[] = [];
  if (pos.estafeta) pinos.push({ ...pos.estafeta, nome: pos.estafeta_nome ?? 'Estafeta', cor: cores.marca });
  if (pos.destino?.lat != null && pos.destino?.lng != null) {
    pinos.push({ lat: pos.destino.lat, lng: pos.destino.lng, nome: 'Entrega', cor: '#1E88E5' });
  }

  if (pinos.length === 0) {
    return <Paragrafo suave>{(pos.estafeta_nome ?? 'O estafeta')} vai a caminho. A localização aparece quando ele a partilhar.</Paragrafo>;
  }

  const lats = pinos.map((p) => p.lat);
  const lngs = pinos.map((p) => p.lng);
  const oeste = Math.min(...lngs);
  const este = Math.max(...lngs);
  const sul = Math.min(...lats);
  const norte = Math.max(...lats);
  const juntos = pinos.length === 1 || (este - oeste < 0.004 && norte - sul < 0.004);

  return (
    <View style={{ gap: 8 }}>
      <View style={[estilos.caixa, { height: altura }]}>
        <Map style={StyleSheet.absoluteFill} mapStyle={estiloMapa} logo={false} compass={false} touchRotate={false} touchPitch={false}>
          {juntos ? (
            <Camera center={[(oeste + este) / 2, (sul + norte) / 2]} zoom={14} />
          ) : (
            <Camera bounds={[oeste, sul, este, norte]} padding={{ top: 48, right: 48, bottom: 48, left: 48 }} />
          )}
          {pinos.map((p) => (
            <Marker key={p.nome} id={p.nome} lngLat={[p.lng, p.lat]}>
              <View style={estilos.marcador}>
                <Text style={estilos.nome} numberOfLines={1}>
                  {p.nome}
                </Text>
                <View style={[estilos.pin, { backgroundColor: p.cor }]} />
              </View>
            </Marker>
          ))}
        </Map>
      </View>
      <Paragrafo suave>
        🔴 {pos.estafeta_nome ?? 'Estafeta'} · 🔵 Entrega.
        {pos.distancia_km != null ? ` A ${String(pos.distancia_km).replace('.', ',')} km` : ''}
        {pos.minutos != null ? ` · chega a ~${pos.minutos} min` : ''}
        {pos.estafeta ? '' : ' — à espera da localização do estafeta.'}
      </Paragrafo>
    </View>
  );
}

const estilos = StyleSheet.create({
  caixa: { borderRadius: raio, overflow: 'hidden' },
  marcador: { alignItems: 'center', maxWidth: 140 },
  nome: {
    backgroundColor: 'rgba(255,255,255,0.92)',
    color: cores.texto,
    fontSize: 11,
    fontWeight: '700',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 8,
    overflow: 'hidden',
    marginBottom: 2,
  },
  pin: { width: 16, height: 16, borderRadius: 8, borderWidth: 2, borderColor: '#fff' },
});
