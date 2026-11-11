// Versão web (PWA) do mapa só de leitura (cozinha; estafeta e destino; rota), com o mesmo
// mapa OpenStreetMap da app (MapLibre GL para o navegador).
import 'maplibre-gl/dist/maplibre-gl.css';

import type { GeoJSONSource, Map as MapaGl, Marker as MarcadorGl } from 'maplibre-gl';
import { useEffect, useRef } from 'react';
import { View } from 'react-native';

import { elementoPino } from '@/components/MapaPin.web';
import { limitesPara } from '@/lib/mapa';
import { estiloMapa } from '@/lib/mapaEstilo';
import { cores, raio } from '@/lib/tema';
import type { Ponto } from '@/lib/tipos';

export type Marcador = Ponto & { titulo: string; cor: string };

type Props = { marcadores: Marcador[]; altura?: number; interactivo?: boolean; rota?: Ponto[] };

function enquadrar(m: MapaGl, marcadores: Marcador[], animar: boolean) {
  const [oeste, sul, este, norte] = limitesPara(marcadores);
  const juntos = marcadores.length === 1 || (este - oeste < 0.004 && norte - sul < 0.004);
  if (juntos) m.jumpTo({ center: [(oeste + este) / 2, (sul + norte) / 2], zoom: 15 });
  else m.fitBounds([[oeste, sul], [este, norte]], { padding: 40, maxZoom: 16, animate: animar });
}

export function MapaPontos({ marcadores, altura = 220, interactivo = false, rota }: Props) {
  const caixa = useRef<HTMLDivElement | null>(null);
  const mapa = useRef<MapaGl | null>(null);
  const pinos = useRef<MarcadorGl[]>([]);
  const glRef = useRef<typeof import('maplibre-gl') | null>(null);
  const primeira = useRef(true);

  useEffect(() => {
    let vivo = true;
    (async () => {
      const gl = await import('maplibre-gl');
      if (!vivo || !caixa.current) return;
      glRef.current = gl;
      const m = new gl.Map({
        container: caixa.current,
        style: estiloMapa as never,
        center: [13.234, -8.839],
        zoom: 12,
        interactive: interactivo,
        attributionControl: { compact: true },
      });
      mapa.current = m;
      m.on('load', () => desenhar());
    })();
    return () => {
      vivo = false;
      mapa.current?.remove();
      mapa.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [interactivo]);

  function desenhar() {
    const m = mapa.current;
    const gl = glRef.current;
    if (!m || !gl || marcadores.length === 0) return;
    pinos.current.forEach((p) => p.remove());
    pinos.current = marcadores.map((mk) => {
      const el = elementoPino(mk.cor);
      el.style.cursor = 'default';
      el.title = mk.titulo;
      return new gl.Marker({ element: el }).setLngLat([mk.lng, mk.lat]).addTo(m);
    });
    const linha = rota && rota.length > 1 ? rota : null;
    const dados = {
      type: 'Feature' as const,
      properties: {},
      geometry: { type: 'LineString' as const, coordinates: (linha ?? []).map((p) => [p.lng, p.lat]) },
    };
    const fonte = m.getSource('rota') as GeoJSONSource | undefined;
    if (fonte) fonte.setData(dados);
    else if (m.isStyleLoaded()) {
      m.addSource('rota', { type: 'geojson', data: dados });
      m.addLayer({ id: 'rota', type: 'line', source: 'rota', paint: { 'line-color': cores.marca, 'line-width': 4 } });
    }
    enquadrar(m, marcadores, !primeira.current);
    primeira.current = false;
  }

  // Marcadores ou rota mudaram (ex.: estafeta a andar): redesenha
  useEffect(() => {
    if (mapa.current?.loaded()) desenhar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [JSON.stringify(marcadores), JSON.stringify(rota ?? null)]);

  if (marcadores.length === 0) return null;
  return (
    <View style={{ height: altura, borderRadius: raio, overflow: 'hidden', backgroundColor: cores.fundoSuave }}>
      <div ref={caixa} style={{ width: '100%', height: '100%' }} />
    </View>
  );
}
