// Run with Node 24. Optional first argument: a previously frozen reference receipt.
// Native DOM/visual checks belong to the separate browser verification.
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { stripTypeScriptTypes } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const moduleCache = new Map();
async function loadTypeScript(relative) {
  if (moduleCache.has(relative)) return moduleCache.get(relative);
  let source = stripTypeScriptTypes(readFileSync(new URL(relative, root), 'utf8'));
  for (const match of [...source.matchAll(/from\s+['"](.\/.+?)['"]/g)]) {
    const url = new URL(match[1] + '.ts', new URL(relative, root));
    const target = fileURLToPath(url).slice(fileURLToPath(root).length);
    source = source.replace(match[0], `from '${await loadTypeScript(target)}'`);
  }
  const data = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
  moduleCache.set(relative, data);
  return data;
}
const core = await import(await loadTypeScript('src/lib/nfl-percentiles.ts'));
const annualContract = await import(await loadTypeScript('src/lib/nfl-annual.ts'));
const legacyContract = await import(await loadTypeScript('src/lib/nfl-comparison.ts'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const pins = {
  [annualContract.ANNUAL_URL.split('/').pop()]: annualContract.ANNUAL_SHA,
  [annualContract.ANNUAL_MANIFEST_URL.split('/').pop()]: annualContract.ANNUAL_MANIFEST_SHA,
  [annualContract.DEPTH_URL.split('/').pop()]: annualContract.DEPTH_SHA,
  [annualContract.DEPTH_MANIFEST_URL.split('/').pop()]: annualContract.DEPTH_MANIFEST_SHA,
  [legacyContract.DATA_URL.split('/').pop()]: legacyContract.PAYLOAD_SHA,
  [legacyContract.MANIFEST_URL.split('/').pop()]: legacyContract.MANIFEST_SHA,
};
const assets = Object.fromEntries(Object.keys(pins).map(name => [name, readFileSync(new URL(`public/data/${name}`, root))]));
for (const [name, expected] of Object.entries(pins)) assert.equal(digest(assets[name]), expected, name);
const { annual, depth } = await annualContract.validateAnnualDepth(...Object.keys(pins).slice(0, 4).map(name => assets[name]));
const legacy = await legacyContract.validatePair(...Object.keys(pins).slice(4).map(name => assets[name]));
const { midpointPercentile: midpoint, displayPercentile: display, percentileFor: lookup } = core;
const unitCases = [
  [0, [0, 0, 2, 3], 25], [2, [0, 0, 2, 3], 62.5],
  [9, [9, 9, 9], 50], [9, [9], null], [null, [1, 2], null],
  [NaN, [1, 2], null], [Infinity, [1, 2], null], [1, [1, null, NaN, Infinity, 2], 25],
  [1, [1, null], null], [3, [1, 2], null], [0, [-0, 0], 50],
  [1, [1, 1 + Number.EPSILON], 25], [1 + Number.EPSILON, [1, 1 + Number.EPSILON], 75],
];
for (const [value, peers, expected] of unitCases) assert.equal(midpoint(value, peers), expected);
assert.equal(display(null), 'Unavailable'); assert.equal(display(NaN), 'Unavailable');
assert.equal(display(2.5), '3'); assert.equal(display(97.5), '98'); assert.equal(display(0.4), '0');
const refs = await core.buildPercentileReferences(annual, depth, legacy);
assert.equal(refs.size, 78);
let frozenReferencesChecked = 0;
if (process.argv[2]) {
  const frozen = JSON.parse(readFileSync(process.argv[2], 'utf8'));
  assert.deepEqual(pins, frozen.source_pins);
  assert.equal(frozen.references.length, refs.size);
  for (const row of frozen.references) {
    const ref = refs.get(`${row.metric}:${row.year}`);
    assert.ok(ref); assert.equal(ref.n, row.N); assert.equal(ref.keyHash, row.key_sha256);
    assert.equal(ref.cohort, row.cohort); frozenReferencesChecked++;
  }
}
// Independent oracle: average positions in a sorted population, rather than B/T counts.
const expectedRank = (value, peers) => {
  if (!Number.isFinite(value)) return null;
  const sorted = peers.filter(Number.isFinite).sort((a, b) => a - b);
  const first = sorted.indexOf(value), last = sorted.lastIndexOf(value);
  if (sorted.length < 2 || first < 0) return null;
  return ((first + last + 1) / 2) / sorted.length * 100;
};
const rawGroups = new Map();
const addRaw = (metric, row, value) => {
  const key = `${metric}:${row.season}`;
  if (!rawGroups.has(key)) rawGroups.set(key, []);
  rawGroups.get(key).push({ id: row.player_key, year: row.season, value });
};
for (const row of annual.rows) addRaw('sack_avoidance_pct', row, row.sack_avoidance_pct);
for (const row of depth.rows) if (['short', 'medium', 'deep'].includes(row.bin)) addRaw(`${row.bin}_cpoe_pp`, row, row.cpoe_pp);
for (const row of legacy.rows) addRaw('scramble_contribution', row, row.scramble_contribution);
const before = JSON.stringify([...refs]);
let checkedValues = 0, rawNullGaps = 0, maxDelta = 0;
for (const [key, rows] of rawGroups) {
  const metric = key.split(':')[0], year = rows[0].year;
  const finite = rows.filter(row => Number.isFinite(row.value));
  const ref = refs.get(key);
  assert.equal(ref.year, year); assert.equal(ref.metric, metric); assert.equal(ref.n, finite.length);
  assert.equal(ref.formulaVersion, 'OP-1.0'); assert.equal(ref.direction, 'higher');
  const serialized = 'metric,player_key,season\n' + finite.map(row => row.id).sort().map(id => `${metric},${id},${year}\n`).join('');
  assert.equal(ref.keyHash, digest(serialized));
  assert.deepEqual(ref.peers, [...finite].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0).map(row => ({ playerKey: row.id, value: row.value })));
  for (const row of rows) {
    const actual = lookup(refs, metric, year, row.id);
    const expected = expectedRank(row.value, rows.map(peer => peer.value));
    assert.equal(actual.n, finite.length); assert.equal(actual.keyHash, ref.keyHash);
    if (expected === null) { assert.equal(actual.percentile, null); rawNullGaps++; }
    else {
      const delta = Math.abs(actual.percentile - expected); maxDelta = Math.max(maxDelta, delta);
      assert.ok(delta < 1e-12, `${key}:${row.id}`);
      assert.ok(Number(display(actual.percentile)) >= 1 && Number(display(actual.percentile)) <= 100);
    }
    checkedValues++;
  }
  const ordered = [...finite].sort((a, b) => a.value - b.value).map(row => lookup(refs, metric, year, row.id).percentile);
  assert.ok(ordered.every((value, i) => i === 0 || value >= ordered[i - 1]));
}
assert.equal(checkedValues, 2280);
// Fixed populations cannot depend on the order or identity of requested comparisons/searches.
for (const [key, rows] of [...rawGroups].reverse()) {
  const metric = key.split(':')[0];
  for (const row of [...rows].reverse()) lookup(refs, metric, row.year, row.id);
}
assert.equal(JSON.stringify([...refs]), before);
assert.equal(lookup(refs, 'sack_avoidance_pct', 2011, annual.rows[0].player_key).percentile, null);
assert.equal(lookup(refs, 'short_cpoe_pp', 2024, 'not-a-player').percentile, null);
assert.equal(lookup(refs, 'scramble_contribution', 2022, legacy.rows[0].player_key).percentile, null);
for (const year of [2023, 2024]) {
  const ref = refs.get(`scramble_contribution:${year}`);
  assert.equal(ref.n, 20); assert.equal(ref.cohort, 'original-20-QB-v2');
  assert.notEqual(ref.keyHash, refs.get(`sack_avoidance_pct:${year}`).keyHash);
  const outsider = annual.rows.find(row => row.season === year && !ref.peers.some(peer => peer.playerKey === row.player_key));
  assert.ok(outsider); assert.equal(lookup(refs, 'scramble_contribution', year, outsider.player_key).percentile, null);
}
// Synthetic absence verifies null and one-peer handling even if accepted points are all finite.
const synthetic = structuredClone(depth); synthetic.rows[0].cpoe_pp = null;
const nullRow = synthetic.rows.find(row => row.bin === 'short'); nullRow.cpoe_pp = null;
const nullRefs = await core.buildPercentileReferences(annual, synthetic, legacy);
assert.equal(lookup(nullRefs, 'short_cpoe_pp', nullRow.season, nullRow.player_key).percentile, null);
const one = { ...annual, rows: [annual.rows[0]] };
assert.equal(lookup(await core.buildPercentileReferences(one, { ...depth, rows: [] }, { ...legacy, rows: [] }), 'sack_avoidance_pct', one.rows[0].season, one.rows[0].player_key).percentile, null);
// Twenty untied observations have five-point spacing, without endpoint stretching.
const twenty = Array.from({ length: 20 }, (_, i) => i);
assert.deepEqual(twenty.map(value => midpoint(value, twenty)), twenty.map(i => 2.5 + 5 * i));
let staticDefaultCellsChecked = 0;
const builtPage = new URL('dist/projects/nfl-qbs-re-evaluated/index.html', root);
if (existsSync(builtPage)) {
  const html = readFileSync(builtPage, 'utf8');
  const table = html.match(/<table data-static-default[\s\S]*?<\/table>/)?.[0];
  assert.ok(table, 'build includes a no-JavaScript default comparison');
  const allRows = [...table.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/g)].slice(1);
  assert.equal(allRows.length, 7);
  const rows = allRows.slice(2);
  const metrics = ['sack_avoidance_pct', 'scramble_contribution', 'short_cpoe_pp', 'medium_cpoe_pp', 'deep_cpoe_pp'];
  assert.equal(rows.length, metrics.length);
  rows.forEach(([row], i) => {
    if (i === 1) return; // Active annual Mobility has its own verifier; preserve legacy20 references above.
    const cells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)];
    assert.equal(cells.length, 2);
    cells.forEach(([, text], j) => {
      const raw = rawGroups.get(`${metrics[i]}:2023`), id = ['00-0033873', '00-0034857'][j];
      const value = raw.find(r => r.id === id).value;
      const expected = Math.floor(expectedRank(value, raw.map(r => r.value)) + 0.5);
      assert.ok(text.startsWith(`${expected} percentile`));
      assert.ok(text.includes(`N=${raw.length}`));
      assert.ok(text.includes('annual finite eligible peers'));
      assert.ok(text.includes('Recorded value:'));
      assert.ok(text.includes('raw range'));
      assert.ok(text.includes('not percentile intervals'));
      staticDefaultCellsChecked++;
    });
  });
}
console.log(JSON.stringify({ status: 'passed', formulaVersion: core.PERCENTILE_FORMULA_VERSION, sourcePins: pins, references: refs.size, frozenReferencesChecked, independentNativeRanksChecked: checkedValues, rawNullGaps, syntheticNullAndSingleton: 'passed', unitCases: unitCases.length, monotonicity: 'all metric-years passed', referenceLookupInvariance: 'passed', legacyCohortAndBlockedYear: 'passed', maxIndependentRankDelta: maxDelta, staticDefaultCellsChecked, browserChecks: 'separate' }, null, 2));
