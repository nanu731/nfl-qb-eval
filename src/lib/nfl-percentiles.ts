// One descriptive-rank implementation serves both static fallback and browser rendering.
import { sha, type Payload } from './nfl-comparison';
import type { AnnualPayload, DepthPayload } from './nfl-annual';

export const PERCENTILE_FORMULA_VERSION = 'OP-1.0';
export type PercentileMetric = 'sack_avoidance_pct' | 'short_cpoe_pp' | 'medium_cpoe_pp' | 'deep_cpoe_pp' | 'scramble_contribution';
export type PercentileCohort = 'annual-eligible-v1' | 'original-20-QB-v2';
export type PercentileReference = {
  metric: PercentileMetric; year: number; cohort: PercentileCohort;
  formulaVersion: string; direction: 'higher'; n: number; keyHash: string;
  peers: readonly { playerKey: string; value: number }[];
};
export type PercentileReferences = Map<string, PercentileReference>;
export type PercentileResult = {
  percentile: number | null; n: number; keyHash: string | null; year: number;
  cohort: PercentileCohort; formulaVersion: string; reason: string;
};
const finite = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);
const cohortFor = (metric: string): PercentileCohort => metric === 'scramble_contribution' ? 'original-20-QB-v2' : 'annual-eligible-v1';

/** Midpoint empirical standing, including the focal record among its finite peers. */
export function midpointPercentile(value: number | null, peers: readonly (number | null)[]): number | null {
  if (!finite(value)) return null;
  const values = peers.filter(finite);
  if (values.length < 2 || !values.some(peer => peer === value)) return null;
  let below = 0, tied = 0;
  for (const peer of values) {
    if (peer < value) below += 1;
    else if (peer === value) tied += 1;
  }
  return 100 * (below + 0.5 * tied) / values.length;
}

/** Display rounding never changes the full-precision radius or stretches endpoints. */
export function displayPercentile(percentile: number | null): string {
  return finite(percentile) ? String(Math.floor(percentile + 0.5)) : 'Unavailable';
}

/** Call only after all three immutable payloads pass their existing pair validators. */
export async function buildPercentileReferences(annual: AnnualPayload, depth: DepthPayload, legacy: Payload): Promise<PercentileReferences> {
  const groups = new Map<string, { metric: PercentileMetric; year: number; peers: { playerKey: string; value: number }[] }>();
  const add = (metric: PercentileMetric, year: number, playerKey: string, value: unknown) => {
    if (!finite(value)) return;
    const key = `${metric}:${year}`;
    if (!groups.has(key)) groups.set(key, { metric, year, peers: [] });
    groups.get(key)!.peers.push({ playerKey, value });
  };
  for (const row of annual.rows) add('sack_avoidance_pct', row.season, row.player_key, row.sack_avoidance_pct);
  for (const row of depth.rows) {
    if (row.bin === 'short' || row.bin === 'medium' || row.bin === 'deep') {
      add(`${row.bin}_cpoe_pp`, row.season, row.player_key, row.cpoe_pp);
    }
  }
  for (const row of legacy.rows) add('scramble_contribution', row.season, row.player_key, row.scramble_contribution);
  const references: PercentileReferences = new Map();
  // ASCII IDs and LF CSV make membership receipts identical in both runtimes.
  for (const [key, group] of [...groups.entries()].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)) {
    group.peers.sort((a, b) => a.playerKey < b.playerKey ? -1 : a.playerKey > b.playerKey ? 1 : 0);
    const csv = 'metric,player_key,season\n' + group.peers.map(peer => `${group.metric},${peer.playerKey},${group.year}\n`).join('');
    references.set(key, {
      ...group, n: group.peers.length, keyHash: await sha(new TextEncoder().encode(csv)),
      cohort: cohortFor(group.metric), formulaVersion: PERCENTILE_FORMULA_VERSION, direction: 'higher',
    });
  }
  return references;
}

export function percentileFor(references: ReadonlyMap<string, PercentileReference>, metric: string, year: number, id: string): PercentileResult {
  const reference = references.get(`${metric}:${year}`);
  const base = {
    n: reference?.n ?? 0, keyHash: reference?.keyHash ?? null, year,
    cohort: reference?.cohort ?? cohortFor(metric), formulaVersion: PERCENTILE_FORMULA_VERSION,
  };
  if (!reference) return { ...base, percentile: null, reason: 'No audited reference cohort for this metric and year.' };
  const peer = reference.peers.find(row => row.playerKey === id);
  if (!peer) return { ...base, percentile: null, reason: 'No finite audited outcome for this player and year.' };
  if (reference.n < 2) return { ...base, percentile: null, reason: 'Fewer than two finite reference peers.' };
  return { ...base, percentile: midpointPercentile(peer.value, reference.peers.map(row => row.value)), reason: 'available' };
}
