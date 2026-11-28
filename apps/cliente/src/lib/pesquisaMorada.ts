// Pesquisa de morada por texto (rua, bairro, sítio conhecido) para o "Novo endereço".
// 1) Bairros onde entregamos (zonas), sem rede e instantâneo.
// 2) Ruas e sítios do OpenStreetMap pelo Photon (gratuito, sem chave), limitado a Angola e
//    com preferência pelos resultados perto de Luanda. Só se envia o texto escrito.
import type { Zona } from './tipos';

export type ResultadoMorada = { id: string; nome: string; detalhe: string; lat: number; lng: number; zonaId?: string };

const PHOTON = 'https://photon.komoot.io/api/';
// Caixa de Angola (oeste, sul, este, norte)
const ANGOLA = '11.6,-18.1,24.1,-4.3';
const LUANDA = { lat: -8.8383, lng: 13.2344 };

/** Sem acentos e em minúsculas, para comparar "Maianga" com "maianga" ou "Viana" com "viána" */
export function normalizar(t: string): string {
  return t
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim();
}

/** Bairros (zonas com centro no mapa) cujo nome contém o texto */
export function procurarBairros(texto: string, zonas: Zona[]): ResultadoMorada[] {
  const q = normalizar(texto);
  if (q.length < 2) return [];
  return zonas
    .filter((z) => z.centro_lat != null && z.centro_lng != null && normalizar(z.nome).includes(q))
    .slice(0, 3)
    .map((z) => ({
      id: `zona-${z.id}`,
      nome: z.nome,
      detalhe: 'Bairro onde entregamos',
      lat: z.centro_lat as number,
      lng: z.centro_lng as number,
      zonaId: z.id,
    }));
}

type Propriedades = {
  osm_id?: number;
  name?: string;
  street?: string;
  housenumber?: string;
  district?: string;
  locality?: string;
  city?: string;
  county?: string;
  state?: string;
  country?: string;
  countrycode?: string;
};
type Feature = { geometry?: { coordinates?: [number, number] }; properties?: Propriedades };

/** Converte a resposta do Photon (GeoJSON) em resultados legíveis, só os de Angola, sem repetidos */
export function lerResposta(json: { features?: Feature[] }): ResultadoMorada[] {
  const vistos = new Set<string>();
  const out: ResultadoMorada[] = [];
  for (const f of json.features ?? []) {
    const p = f.properties ?? {};
    const c = f.geometry?.coordinates;
    if (!c || (p.countrycode && p.countrycode.toUpperCase() !== 'AO')) continue;
    const rua = [p.street, p.housenumber].filter(Boolean).join(' ');
    const nome = p.name || rua;
    if (!nome) continue;
    const detalhe = [p.name && rua && rua !== p.name ? rua : null, p.district ?? p.locality, p.city ?? p.county, p.state]
      .filter((x, i, a): x is string => !!x && a.indexOf(x) === i)
      .join(', ');
    const chave = `${nome}|${detalhe}`;
    if (vistos.has(chave)) continue;
    vistos.add(chave);
    out.push({ id: `osm-${p.osm_id ?? out.length}-${c[0]}`, nome, detalhe, lat: c[1], lng: c[0] });
  }
  return out;
}

/** Ruas e sítios pelo texto. Lança se a rede falhar (o ecrã mostra só os bairros). */
export async function procurarNoMapa(texto: string, perto?: { lat: number; lng: number }, sinal?: AbortSignal) {
  const q = texto.trim();
  if (q.length < 3) return [];
  const centro = perto ?? LUANDA;
  const url =
    `${PHOTON}?q=${encodeURIComponent(q)}&limit=6&bbox=${ANGOLA}` +
    `&lat=${centro.lat.toFixed(4)}&lon=${centro.lng.toFixed(4)}`;
  const r = await fetch(url, { signal: sinal });
  if (!r.ok) throw new Error(`pesquisa_${r.status}`);
  return lerResposta(await r.json());
}
