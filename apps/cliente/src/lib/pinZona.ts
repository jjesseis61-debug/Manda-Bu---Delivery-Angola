import type { Zona } from './tipos';

/** A partir de quantos km entre o pino e o centro do bairro se pergunta «onde é a entrega?» */
export const LIMITE_PINO_ZONA_KM = 5;

/** Distância em km entre dois pontos (fórmula do círculo máximo) */
export function distanciaKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const r = (g: number) => (g * Math.PI) / 180;
  const x =
    Math.sin(r(b.lat - a.lat) / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(r(b.lng - a.lng) / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

/**
 * O pino está longe do bairro escolhido? Acontece a quem regista a morada noutro sítio (o mapa põe o pino
 * onde a pessoa está) e escolhe o bairro à mão. Devolve a distância e o bairro mais perto do pino
 * (para propor), ou null se está tudo certo ou se o bairro não tem centro conhecido.
 */
export function pinoLongeDaZona(
  pino: { lat: number; lng: number },
  zonaId: string,
  zonas: Pick<Zona, 'id' | 'nome' | 'centro_lat' | 'centro_lng'>[],
  limiteKm = LIMITE_PINO_ZONA_KM,
): { km: number; zona: string; maisPerto: { id: string; nome: string } | null } | null {
  const z = zonas.find((x) => x.id === zonaId);
  if (!z || z.centro_lat == null || z.centro_lng == null) return null;
  const km = distanciaKm(pino, { lat: z.centro_lat, lng: z.centro_lng });
  if (km < limiteKm) return null;
  const perto = zonas
    .filter((x) => x.centro_lat != null && x.centro_lng != null)
    .map((x) => ({ id: x.id, nome: x.nome, km: distanciaKm(pino, { lat: x.centro_lat as number, lng: x.centro_lng as number }) }))
    .sort((a, b) => a.km - b.km)[0];
  return { km, zona: z.nome, maisPerto: perto && perto.id !== z.id ? { id: perto.id, nome: perto.nome } : null };
}

/** O pino desta morada está longe do bairro dela? (então as distâncias a partir dela não são de confiança) */
export function moradaComPinoLonge(
  e: { pontos_entrega: { zona_id: string | null; lat?: number | null; lng?: number | null; zonas: { nome: string; centro_lat?: number | null; centro_lng?: number | null } | null } | null } | undefined,
  limiteKm = LIMITE_PINO_ZONA_KM,
): boolean {
  const p = e?.pontos_entrega;
  const z = p?.zonas;
  if (!p || p.lat == null || p.lng == null || !z || z.centro_lat == null || z.centro_lng == null) return false;
  return distanciaKm({ lat: Number(p.lat), lng: Number(p.lng) }, { lat: Number(z.centro_lat), lng: Number(z.centro_lng) }) >= limiteKm;
}

/** «fica ao lado» (menos de 100 m) ou «fica a 2,4 km» */
export function textoFicaA(km: number, distancia: (km: number) => string): string {
  return km < 0.1 ? 'fica ao lado' : `fica a ${distancia(km)}`;
}
