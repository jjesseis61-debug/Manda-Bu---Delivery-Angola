// Mapa gratuito e sem chave. Por defeito usa o OpenFreeMap (tiles vetoriais do OpenStreetMap, sem
// API key, sem limites e com uso comercial permitido; feito para apps, ao contrário do servidor
// público de tiles do OSM, que bloqueia apps). Se definires EXPO_PUBLIC_MAPA_TILES_URL (um molde
// raster no formato https://.../{z}/{x}/{y}.png, ex.: MapTiler/Stadia), usa esse fornecedor.
import type { StyleSpecification } from '@maplibre/maplibre-react-native';

const TILES = process.env.EXPO_PUBLIC_MAPA_TILES_URL;

export const estiloMapa: string | StyleSpecification = TILES
  ? {
      version: 8,
      sources: { osm: { type: 'raster', tiles: [TILES], tileSize: 256, maxzoom: 19, attribution: '© OpenStreetMap' } },
      layers: [{ id: 'osm', type: 'raster', source: 'osm' }],
    }
  : 'https://tiles.openfreemap.org/styles/bright';
