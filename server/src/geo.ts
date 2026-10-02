export interface MapPlace { name: string; lat: number; lng: number; phone: string | null; address: string | null }
export type FetchPlaces = (lat: number, lng: number, radiusM: number) => Promise<MapPlace[]>;

export const distanceKm = (aLat: number, aLng: number, bLat: number, bLng: number) => {
  const r = Math.PI / 180, dLat = (bLat - aLat) * r, dLng = (bLng - aLng) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * r) * Math.cos(bLat * r) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(h));
};

/** Pharmacies from OpenStreetMap (open data, ODbL), looked up server-side so phones never talk to Overpass and
 *  we can cache. Failure is not fatal: the caller just gets no map results. */
export function overpassPlaces(endpoint = process.env.OVERPASS_URL || 'https://overpass-api.de/api/interpreter'): FetchPlaces {
  return async (lat, lng, radiusM) => {
    const q = `[out:json][timeout:20];(node["amenity"="pharmacy"](around:${radiusM},${lat},${lng});way["amenity"="pharmacy"](around:${radiusM},${lat},${lng}););out center tags 80;`;
    const res = await fetch(endpoint, {
      method: 'POST', body: new URLSearchParams({ data: q }),
      headers: { 'user-agent': 'HealthDiary/1.0 (health-api.jagotech.com.bd)' }, signal: AbortSignal.timeout(25_000),
    });
    if (!res.ok) throw new Error(`overpass ${res.status}`);
    const j = (await res.json()) as { elements?: any[] };
    return (j.elements ?? []).flatMap((e) => {
      const pLat = e.lat ?? e.center?.lat, pLng = e.lon ?? e.center?.lon, t = e.tags ?? {};
      if (typeof pLat !== 'number' || typeof pLng !== 'number') return [];
      const addr = [t['addr:housenumber'], t['addr:street'], t['addr:suburb'] ?? t['addr:city']].filter(Boolean).join(', ');
      return [{ name: String(t['name:bn'] ?? t.name ?? 'ফার্মেসি').slice(0, 120), lat: pLat, lng: pLng,
        phone: (t.phone ?? t['contact:phone'] ?? null) && String(t.phone ?? t['contact:phone']).slice(0, 40), address: addr || null }];
    });
  };
}

/** 12-hour cache keyed by a ~2 km grid cell, so many users in one area cost one lookup. */
export function cached(fetchPlaces: FetchPlaces, ttlMs = 12 * 3600_000): FetchPlaces {
  const mem = new Map<string, { at: number; v: MapPlace[] }>();
  return async (lat, lng, radiusM) => {
    const cLat = Math.round(lat / 0.02) * 0.02, cLng = Math.round(lng / 0.02) * 0.02;
    const key = `${cLat.toFixed(2)}|${cLng.toFixed(2)}|${radiusM}`;
    const hit = mem.get(key);
    if (hit && Date.now() - hit.at < ttlMs) return hit.v;
    const v = await fetchPlaces(cLat, cLng, radiusM + 2500); // cover the whole cell, caller filters by true distance
    if (mem.size > 300) mem.delete(mem.keys().next().value!);
    mem.set(key, { at: Date.now(), v });
    return v;
  };
}
