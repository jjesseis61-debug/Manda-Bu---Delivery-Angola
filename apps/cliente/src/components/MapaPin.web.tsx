// Versão web (PWA) do pino no mapa: o mesmo mapa OpenStreetMap da app (MapLibre GL, versão
// para o navegador). Toca no mapa ou arrasta o pino para marcar a porta de casa.
import 'maplibre-gl/dist/maplibre-gl.css';

import type { Map as MapaGl, Marker as MarcadorGl } from 'maplibre-gl';
import { useEffect, useRef } from 'react';
import { View } from 'react-native';

import { estiloMapa } from '@/lib/mapaEstilo';
import { cores, raio } from '@/lib/tema';

export type Coordenadas = { latitude: number; longitude: number };

/** Bolinha da marca, igual à da app */
export function elementoPino(cor: string = cores.marca): HTMLDivElement {
  const el = document.createElement('div');
  el.style.cssText = `width:20px;height:20px;border-radius:10px;background:${cor};border:3px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4);cursor:grab`;
  return el;
}

export function MapaPin({ ponto, aoMudar, centrarEm }: { ponto: Coordenadas; aoMudar: (p: Coordenadas) => void; centrarEm?: Coordenadas }) {
  const caixa = useRef<HTMLDivElement | null>(null);
  const mapa = useRef<MapaGl | null>(null);
  const pino = useRef<MarcadorGl | null>(null);
  const aoMudarRef = useRef(aoMudar);
  aoMudarRef.current = aoMudar;

  // Cria o mapa uma vez (a biblioteca só se carrega quando o ecrã do mapa abre)
  useEffect(() => {
    let vivo = true;
    (async () => {
      const gl = await import('maplibre-gl');
      if (!vivo || !caixa.current) return;
      const m = new gl.Map({
        container: caixa.current,
        style: estiloMapa as never,
        center: [ponto.longitude, ponto.latitude],
        zoom: 15,
        attributionControl: { compact: true },
        dragRotate: false,
        pitchWithRotate: false,
      });
      m.touchZoomRotate.disableRotation();
      m.addControl(new gl.NavigationControl({ showCompass: false }), 'top-right');
      const p = new gl.Marker({ element: elementoPino(), draggable: true })
        .setLngLat([ponto.longitude, ponto.latitude])
        .addTo(m);
      p.on('dragend', () => {
        const { lng, lat } = p.getLngLat();
        aoMudarRef.current({ latitude: lat, longitude: lng });
      });
      m.on('click', (e) => aoMudarRef.current({ latitude: e.lngLat.lat, longitude: e.lngLat.lng }));
      mapa.current = m;
      pino.current = p;
    })();
    return () => {
      vivo = false;
      mapa.current?.remove();
      mapa.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // O ponto mudou (toque, GPS "A minha localização"): move o pino
  useEffect(() => {
    pino.current?.setLngLat([ponto.longitude, ponto.latitude]);
  }, [ponto.latitude, ponto.longitude]);

  useEffect(() => {
    if (centrarEm) mapa.current?.flyTo({ center: [centrarEm.longitude, centrarEm.latitude], zoom: 15, duration: 500 });
  }, [centrarEm]);

  return (
    <View style={{ height: 260, borderRadius: raio, overflow: 'hidden', backgroundColor: cores.fundoSuave }}>
      <div ref={caixa} style={{ width: '100%', height: '100%' }} />
    </View>
  );
}
