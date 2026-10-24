// Extrai um par (latitude, longitude) de texto colado do Google Maps: coordenadas soltas
// ("-8.944707, 13.376525") ou um endereço/URL que as contenha (?q=, /@lat,lng, !3dlat!4dlng).
// Devolve null quando não há um par válido. Links curtos (maps.app.goo.gl) não têm coordenadas
// no texto, por isso não dão aqui — é preciso colar os números.
const DEC = '(-?\\d{1,3}(?:\\.\\d+)?)';

const PADROES = [
  new RegExp(`[?&](?:q|query|ll|center|daddr|destination)=${DEC},${DEC}`, 'i'), // ?q=lat,lng
  new RegExp(`!3d${DEC}!4d${DEC}`),                                             // !3dlat!4dlng (ponto exacto)
  new RegExp(`@${DEC},${DEC}`),                                                 // /@lat,lng (centro do mapa)
  new RegExp(`${DEC}\\s*,\\s*${DEC}`),                                          // "lat, lng" colado
];

export function extrairCoordenadas(texto: string): [number, number] | null {
  const t = (texto ?? '').trim();
  if (!t) return null;
  for (const re of PADROES) {
    const m = t.match(re);
    if (m) {
      const lat = Number(m[1]);
      const lng = Number(m[2]);
      if (Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
        return [lat, lng];
      }
    }
  }
  return null;
}

// Procura uma morada na internet (OpenStreetMap/Nominatim) quando o geocoder do telemóvel não existe.
// Enviesado para Angola; uso leve (um balcão de cada vez), com User-Agent como a política pede.
export async function geocodarOnline(q: string): Promise<[number, number] | null> {
  const termo = (q ?? '').trim();
  if (!termo) return null;
  const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=ao&q=${encodeURIComponent(termo)}`;
  const r = await fetch(url, { headers: { 'User-Agent': 'MandaBue-Operador/1.0' } });
  if (!r.ok) return null;
  const dados = (await r.json()) as { lat?: string; lon?: string }[];
  const p = Array.isArray(dados) ? dados[0] : undefined;
  if (!p?.lat || !p?.lon) return null;
  const lat = Number(p.lat);
  const lng = Number(p.lon);
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? [lat, lng] : null;
}
