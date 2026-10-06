// Mapa gratuito OpenStreetMap (sem chave, sem faturação): usado para acompanhar os estafetas.
// Se um dia o volume crescer, define EXPO_PUBLIC_MAPA_TILES_URL (no build) com um fornecedor próprio
// no formato https://.../{z}/{x}/{y}.png e a app passa a usá-lo sem mudar código.
import type { StyleSpecification } from '@maplibre/maplibre-react-native';

const TILES = process.env.EXPO_PUBLIC_MAPA_TILES_URL ?? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

export const estiloOsm: StyleSpecification = {
  version: 8,
  sources: {
    osm: { type: 'raster', tiles: [TILES], tileSize: 256, maxzoom: 19, attribution: '© OpenStreetMap' },
  },
  layers: [{ id: 'osm', type: 'raster', source: 'osm' }],
};
