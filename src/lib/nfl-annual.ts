// The same immutable annual/depth contract runs at build time and in the browser.
import { sha, type Domain, type Row } from './nfl-comparison';

export const ANNUAL_URL = '/data/nfl-qb-annual-2006-2025-v1.json';
export const ANNUAL_MANIFEST_URL = '/data/nfl-qb-annual-2006-2025-v1.manifest.json';
export const DEPTH_URL = '/data/nfl-qb-depth-2006-2025-v1.json';
export const DEPTH_MANIFEST_URL = '/data/nfl-qb-depth-2006-2025-v1.manifest.json';
export const ANNUAL_SHA = '4a5afb5431eab1ba9119af49ae175fa5abd899d70e3f58ea9f5906e76122ba68';
export const ANNUAL_MANIFEST_SHA = 'e12f8c348585f80bc1cb258b0913b9222a2662b81365ab9072c218feb9d757f9';
export const DEPTH_SHA = '5aa2bc98de1c26f9056d5ccbab03327cc90bd4a0a37bd3ac568d0c9cb65285ae';
export const DEPTH_MANIFEST_SHA = 'f48d29dd22a0f27fe95c5f057d1e7becfde449ae20102d258f69855de2169e90';

export type AnnualRow = Row & {
  display_name: string; name_status: 'verified_source_display_name';
  eligible_throws: number; eligible_games: number; cpoe_pp: number; completion_pct: number;
  dropbacks: number; dropback_games: number; sacks: number; scramble_runs: number;
  sack_avoidance_pct: number; epa_per_dropback: number | null; epa_lower: number | null;
  epa_upper: number | null; epa_interval_status: string;
};
export type DepthBin = 'negative' | 'short' | 'medium' | 'deep';
export type DepthRow = Row & {
  display_name: string; name_status: 'verified_source_display_name'; bin: DepthBin;
  air_yards_lower: number; air_yards_upper: number; eligible_throws: number;
  eligible_games: number; bin_throws: number; positive_bin_games: number;
  cpoe_pp: number | null; lower: number | null; upper: number | null; interval_status: string;
};
export type SeasonCatalogEntry = {
  season: number; status: 'exported' | 'source_blocked'; reason: string | null; row_count: number;
};
type Versions = Record<string, { version: string; specification_sha256?: string; script_sha256?: string }>;
type Source = { season: number; sha256: string; url: string; [key: string]: unknown };
type Metadata = {
  schema_version: number; data_version: string; dataset_kind: string; generated_utc: string;
  seasons: number[]; season_catalog: SeasonCatalogEntry[]; eligibility: Record<string, string>;
  units: Record<string, string>; denominators: Record<string, string>; uncertainty: Record<string, string>;
  sources: { pbp: Source[]; schedule_reference: Record<string, unknown>[]; player_names: Record<string, string> };
  attribution: Record<string, string>; analysis_versions: Versions;
  aggregate_input_hashes: Record<string, string>; domains: Record<string, Domain>;
};
export type AnnualPayload = Metadata & { rows: AnnualRow[] };
export type DepthPayload = Metadata & {
  bins: { bin: DepthBin; air_yards_lower: number; air_yards_upper: number }[]; rows: DepthRow[];
};
type Manifest = Pick<Metadata, 'schema_version' | 'data_version' | 'dataset_kind' | 'generated_utc' |
  'seasons' | 'season_catalog' | 'units' | 'domains' | 'analysis_versions' | 'aggregate_input_hashes'> & {
  payload: { filename: string; sha256: string }; row_count: number; row_keys_sha256: string;
  source_hashes: { season: number; sha256: string }[]; export_script_sha256: string;
};

const GENERATED = '2026-10-20T02:22:52Z';
const SCRIPT_SHA = '1b3a4ee2dcb0a2b52ca36da47af6affba937f6f3ce496ccf57766622f6c8e826';
const YEARS = Array.from({ length: 20 }, (_, i) => 2006 + i).filter(y => y !== 2011);
const BINS = [
  { bin: 'negative', air_yards_lower: -15, air_yards_upper: 0 },
  { bin: 'short', air_yards_lower: 0, air_yards_upper: 10 },
  { bin: 'medium', air_yards_lower: 10, air_yards_upper: 20 },
  { bin: 'deep', air_yards_lower: 20, air_yards_upper: 70 },
] as const;
const ANNUAL_FIELDS = ['player_key','season','observed_name','display_name','name_status','eligible_throws','eligible_games','cpoe_pp','completion_pct','dropbacks','dropback_games','sacks','scramble_runs','sack_avoidance_pct','epa_per_dropback','epa_lower','epa_upper','epa_interval_status'];
const DEPTH_FIELDS = ['player_key','season','observed_name','display_name','name_status','bin','air_yards_lower','air_yards_upper','eligible_throws','eligible_games','bin_throws','positive_bin_games','cpoe_pp','lower','upper','interval_status'];
const TOP_FIELDS = ['schema_version','data_version','dataset_kind','generated_utc','seasons','season_catalog','eligibility','units','denominators','uncertainty','sources','attribution','analysis_versions','aggregate_input_hashes','rows','domains'];
const MANIFEST_FIELDS = ['schema_version','data_version','dataset_kind','generated_utc','payload','seasons','season_catalog','row_count','row_keys_sha256','units','domains','analysis_versions','aggregate_input_hashes','source_hashes','export_script_sha256'];
const ANNUAL_UNITS = { cpoe_pp:'percentage_points', completion_pct:'percent', eligible_throws:'throws', eligible_games:'actor_games', dropbacks:'dropbacks', dropback_games:'actor_games', sacks:'sacks', scramble_runs:'runs', sack_avoidance_pct:'percent', epa_per_dropback:'expected_points_per_dropback', epa_lower:'expected_points_per_dropback', epa_upper:'expected_points_per_dropback' };
const DEPTH_UNITS = { air_yards_lower:'yards', air_yards_upper:'yards', eligible_throws:'throws', eligible_games:'actor_games', bin_throws:'throws', positive_bin_games:'actor_games', cpoe_pp:'percentage_points', lower:'percentage_points', upper:'percentage_points' };
const AVAILABLE = ['approximate_conditional_game_sampling_sensitivity','collapsed_no_observed_deletion_variation'];
const UNAVAILABLE = ['no_opportunities','nonfinite_mean_or_deletion','fewer_than_two_games','nonpositive_deletion_denominator','nonfinite_or_invalid_variance','nonfinite_interval_endpoints','nonfinite_epa_on_frozen_D'];
const equal = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
function requireData(ok: unknown): asserts ok {
  if (!ok) throw new Error('The annual and depth data do not match the reviewed version.');
}
function keys(value: object, expected: readonly string[]) {
  requireData(value && typeof value === 'object' && equal(Object.keys(value).sort(), [...expected].sort()));
}
const finite = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n);
const count = (n: unknown): n is number => Number.isInteger(n) && Number(n) >= 0;
const sameNumber = (a: number, b: number) => Math.abs(a - b) < 1e-10;
const rowKey = (r: Row) => `${r.player_key}:${r.season}`;
function identity(r: AnnualRow | DepthRow) {
  requireData(/^00-\d{7}$/.test(r.player_key) && YEARS.includes(r.season));
  requireData(r.name_status === 'verified_source_display_name');
  for (const name of [r.display_name, r.observed_name]) requireData(typeof name === 'string' && name.trim() === name && name.length > 0 && !/[<>\u0000-\u001f]/.test(name));
  requireData(count(r.eligible_throws) && r.eligible_throws >= 200 && count(r.eligible_games) && r.eligible_games >= 10 && r.eligible_games <= 17);
  for (const v of Object.values(r)) if (typeof v === 'number') requireData(finite(v));
}
function interval(point: unknown, lower: unknown, upper: unknown, status: string) {
  requireData(AVAILABLE.includes(status) || UNAVAILABLE.includes(status));
  requireData(point === null || finite(point));
  if (AVAILABLE.includes(status)) {
    requireData(finite(point) && finite(lower) && finite(upper) && lower <= point && point <= upper);
    if (status === 'collapsed_no_observed_deletion_variation') requireData(lower === point && upper === point);
  } else {
    requireData(lower === null && upper === null);
    if (['no_opportunities','nonfinite_mean_or_deletion','nonfinite_epa_on_frozen_D'].includes(status)) requireData(point === null);
  }
}
function domain(d: Domain, numbers: number[], unit: string, limits: boolean, signed: boolean) {
  keys(d, ['min','max','unit','status','includes_marginal_limits','constant_observed']);
  requireData(d.unit === unit && d.status === 'available' && d.includes_marginal_limits === limits && d.constant_observed === false);
  requireData(finite(d.min) && finite(d.max) && d.min < d.max && numbers.every(finite));
  const all = signed ? [...numbers, 0] : numbers;
  requireData(d.min === Math.min(...all) && d.max === Math.max(...all));
  if (unit === 'percent') requireData(d.min >= 0 && d.max <= 100);
}
function metadata(p: AnnualPayload | DepthPayload, m: Manifest, isDepth: boolean) {
  keys(p, isDepth ? [...TOP_FIELDS, 'bins'] : TOP_FIELDS); keys(m, MANIFEST_FIELDS);
  requireData(p.schema_version === (isDepth ? 1 : 3) && p.data_version === (isDepth ? '2006-2025-depth-residual-v1' : '2006-2025-independent-annual-v1'));
  requireData(p.dataset_kind === (isDepth ? 'independent_annual_depth_display' : 'independent_annual_display') && p.generated_utc === GENERATED && equal(p.seasons, YEARS));
  keys(m.payload, ['filename','sha256']);
  requireData(m.payload.filename === (isDepth ? DEPTH_URL : ANNUAL_URL).split('/').pop() && m.payload.sha256 === (isDepth ? DEPTH_SHA : ANNUAL_SHA));
  for (const k of ['schema_version','data_version','dataset_kind','generated_utc','seasons','season_catalog','units','domains','analysis_versions','aggregate_input_hashes'] as const) requireData(equal(p[k], m[k]));
  requireData(equal(p.units, isDepth ? DEPTH_UNITS : ANNUAL_UNITS));
  requireData(Array.isArray(p.rows) && p.rows.length === (isDepth ? 2240 : 560) && m.row_count === p.rows.length);
  requireData(p.analysis_versions.annual.version === 'AD-1.0+AD-1.1' && p.analysis_versions.annual.specification_sha256 === '7d9c08e156c85fb7c69005b79c192c9b0e45d312ae3b8d5f94c4cdfcb8887ce1');
  requireData(p.analysis_versions.depth.version === 'DPX-1.0' && p.analysis_versions.depth.specification_sha256 === 'd097199d263267202330d3f17d4bb3b1b86aa5311c822f992326f6fb1d41206a');
  requireData(p.analysis_versions.export.version === 'annual-depth-1.0' && p.analysis_versions.export.script_sha256 === SCRIPT_SHA && m.export_script_sha256 === SCRIPT_SHA);
  requireData(p.season_catalog.length === 20);
  p.season_catalog.forEach((entry, i) => {
    keys(entry, ['season','status','reason','row_count']);
    requireData(entry.season === 2006 + i && entry.row_count === p.rows.filter(r => r.season === entry.season).length);
    requireData(entry.season === 2011 ? entry.status === 'source_blocked' && entry.reason === 'unresolved_duplicate_events_and_air_yards' && entry.row_count === 0 : entry.status === 'exported' && entry.reason === null && entry.row_count > 0);
  });
  const sources = p.sources.pbp.map(({ season, sha256 }) => ({ season, sha256 }));
  requireData(sources.length === 20 && equal(sources.map(s => s.season), Array.from({ length: 20 }, (_, i) => 2006 + i)) && equal(sources, m.source_hashes));
  for (const source of sources) requireData(/^[a-f0-9]{64}$/.test(source.sha256));
  requireData(p.sources.player_names.sha256 === p.aggregate_input_hashes.player_names);
}

/** All four reviewed byte sequences are required; a partial or stale pair rejects together. */
export async function validateAnnualDepth(annualBytes: Uint8Array, annualManifestBytes: Uint8Array, depthBytes: Uint8Array, depthManifestBytes: Uint8Array): Promise<{ annual: AnnualPayload; depth: DepthPayload }> {
  const hashes = await Promise.all([annualBytes, annualManifestBytes, depthBytes, depthManifestBytes].map(sha));
  requireData(equal(hashes, [ANNUAL_SHA, ANNUAL_MANIFEST_SHA, DEPTH_SHA, DEPTH_MANIFEST_SHA]));
  const decode = (bytes: Uint8Array) => JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  const annual = decode(annualBytes) as AnnualPayload, depth = decode(depthBytes) as DepthPayload;
  const am = decode(annualManifestBytes) as Manifest, dm = decode(depthManifestBytes) as Manifest;
  metadata(annual, am, false); metadata(depth, dm, true);
  for (const k of ['generated_utc','seasons','eligibility','sources','attribution','analysis_versions','aggregate_input_hashes'] as const) requireData(equal(annual[k], depth[k]));
  requireData(equal(depth.bins, BINS));
  const byKey = new Map<string, AnnualRow>(), names = new Map<string, string>();
  for (const r of annual.rows) {
    keys(r, ANNUAL_FIELDS); identity(r);
    const key = rowKey(r); requireData(!byKey.has(key)); byKey.set(key, r);
    const name = `${r.display_name}\n${r.observed_name}`;
    requireData(!names.has(r.player_key) || names.get(r.player_key) === name); names.set(r.player_key, name);
    for (const f of ['dropbacks','dropback_games','sacks','scramble_runs'] as const) requireData(count(r[f]));
    requireData(r.dropbacks >= r.eligible_throws && r.dropbacks >= r.sacks + r.scramble_runs && r.dropback_games >= r.eligible_games && r.dropback_games <= 17);
    requireData(finite(r.cpoe_pp) && r.cpoe_pp >= -100 && r.cpoe_pp <= 100 && finite(r.completion_pct) && r.completion_pct >= 0 && r.completion_pct <= 100);
    requireData(finite(r.sack_avoidance_pct) && sameNumber(r.sack_avoidance_pct, 100 * (r.dropbacks - r.sacks) / r.dropbacks));
    interval(r.epa_per_dropback, r.epa_lower, r.epa_upper, r.epa_interval_status);
  }
  requireData(names.size === 140 && new Set(annual.rows.map(r => r.season)).size === 19);
  const depthKeys = new Set<string>(), counts = new Map<string, number>();
  for (const r of depth.rows) {
    keys(r, DEPTH_FIELDS); identity(r);
    const key = rowKey(r), a = byKey.get(key), bin = BINS.find(b => b.bin === r.bin);
    requireData(a && bin && !depthKeys.has(`${key}:${r.bin}`)); depthKeys.add(`${key}:${r.bin}`);
    requireData(r.display_name === a.display_name && r.observed_name === a.observed_name && r.name_status === a.name_status && r.eligible_throws === a.eligible_throws && r.eligible_games === a.eligible_games);
    requireData(r.air_yards_lower === bin.air_yards_lower && r.air_yards_upper === bin.air_yards_upper);
    requireData(count(r.bin_throws) && r.bin_throws <= r.eligible_throws && count(r.positive_bin_games) && r.positive_bin_games <= Math.min(r.bin_throws, r.eligible_games));
    requireData(r.bin_throws === 0 ? r.positive_bin_games === 0 && r.cpoe_pp === null && r.interval_status === 'no_opportunities' : r.positive_bin_games > 0 && finite(r.cpoe_pp) && r.cpoe_pp >= -100 && r.cpoe_pp <= 100 && r.interval_status !== 'no_opportunities');
    interval(r.cpoe_pp, r.lower, r.upper, r.interval_status);
    counts.set(key, (counts.get(key) ?? 0) + r.bin_throws);
  }
  for (const [key, r] of byKey) requireData(BINS.every(b => depthKeys.has(`${key}:${b.bin}`)) && counts.get(key) === r.eligible_throws);
  // CSV keys bind order and identity to the export manifests as well as the byte pins.
  for (const [p, m, fields] of [[annual, am, ['player_key','season']], [depth, dm, ['player_key','season','bin']]] as const) {
    const csv = `${fields.join(',')}\n${p.rows.map(r => fields.map(f => r[f]).join(',')).join('\n')}\n`;
    requireData(await sha(new TextEncoder().encode(csv)) === m.row_keys_sha256);
  }
  keys(annual.domains, ['cpoe_pp','completion_pct','sack_avoidance_pct','epa_per_dropback']);
  for (const field of ['cpoe_pp','completion_pct','sack_avoidance_pct','epa_per_dropback'] as const) {
    const hasLimits = field === 'epa_per_dropback';
    const values = annual.rows.flatMap(r => hasLimits ? [r[field], r.epa_lower, r.epa_upper] : [r[field]]).filter(finite);
    domain(annual.domains[field], values, ANNUAL_UNITS[field], hasLimits, !['completion_pct','sack_avoidance_pct'].includes(field));
  }
  keys(depth.domains, ['depth_cpoe_pp']);
  domain(depth.domains.depth_cpoe_pp, depth.rows.filter(r => r.bin !== 'negative').flatMap(r => [r.cpoe_pp,r.lower,r.upper]).filter(finite), 'percentage_points', true, true);
  return { annual, depth };
}
