// Ajudas de mapa (I10, I11). Sem API paga: a navegação abre a app do Google Maps no telemóvel.
import type { Ponto } from './tipos';

/** Link de navegação do Google Maps até ao ponto (abre a app se estiver instalada; senão o site) */
export function urlComoChegar(p: Ponto): string {
  return `https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}`;
}

/** Região do mapa que mostra todos os pontos, com margem; um só ponto fica centrado */
export function regiaoPara(pontos: Ponto[]) {
  const lats = pontos.map((p) => p.lat);
  const lngs = pontos.map((p) => p.lng);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLng = Math.min(...lngs);
  const maxLng = Math.max(...lngs);
  return {
    latitude: (minLat + maxLat) / 2,
    longitude: (minLng + maxLng) / 2,
    latitudeDelta: Math.max((maxLat - minLat) * 1.6, 0.01),
    longitudeDelta: Math.max((maxLng - minLng) * 1.6, 0.01),
  };
}

/** "há 20 s", "há 3 min" */
export function haQuantoTempo(iso: string, agora = Date.now()): string {
  const s = Math.max(0, Math.round((agora - new Date(iso).getTime()) / 1000));
  return s < 60 ? `há ${s} s` : `há ${Math.round(s / 60)} min`;
}
