// Execute the real pinned annual Mobility consumer; native browser checks are separate.
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {fileURLToPath} from 'node:url';
const root=new URL('../',import.meta.url),cache=new Map();
async function load(relative){
 if(cache.has(relative))return cache.get(relative);
 let source=stripTypeScriptTypes(readFileSync(new URL(relative,root),'utf8'));
 for(const match of [...source.matchAll(/from\s+['"](.\/.+?)['"]/g)]){
  const target=fileURLToPath(new URL(match[1]+'.ts',new URL(relative,root))).slice(fileURLToPath(root).length);source=source.replace(match[0],`from '${await load(target)}'`);
 }
 const url=`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;cache.set(relative,url);return url;
}
const core=await import(await load('src/lib/nfl-mobility.ts'));
const bytes=new Uint8Array(readFileSync(new URL('public'+core.MOBILITY_URL,root))),manifest=new Uint8Array(readFileSync(new URL('public'+core.MOBILITY_MANIFEST_URL,root)));
const annual=JSON.parse(readFileSync(new URL('public/data/nfl-qb-annual-2006-2025-v1.json',root))),legacy=JSON.parse(readFileSync(new URL('public/data/nfl-qb-2023-2024-v2.json',root)));
const data=await core.validateAnnualMobility(bytes,manifest,annual,legacy),references=await core.buildMobilityReferences(data);
assert.equal(data.rows.length,560);assert.equal(references.size,19);let checked=0,maxDelta=0,zeros=0;
const frozen=JSON.stringify([...references]);
for(const row of data.rows){
 const actual=core.mobilityPercentileFor(references,row.season,row.player_key),peers=data.rows.filter(r=>r.season===row.season&&Number.isFinite(r.scramble_contribution));
 assert.equal(actual.n,peers.length);
 if(row.scramble_contribution===null){assert.equal(actual.percentile,null);assert.equal(row.player_key,'00-0022164');assert.equal(row.season,2007);continue;}
 const below=peers.filter(r=>r.scramble_contribution<row.scramble_contribution).length,tied=peers.filter(r=>r.scramble_contribution===row.scramble_contribution).length,expected=100*(below+.5*tied)/peers.length;
 maxDelta=Math.max(maxDelta,Math.abs(actual.percentile-expected));assert.ok(Math.abs(actual.percentile-expected)<1e-12);checked++;
 if(row.scramble_runs===0){assert.equal(row.scramble_contribution,0);assert.equal(row.scramble_interval_status,'collapsed_no_observed_deletion_variation');assert.notEqual(actual.percentile,null);zeros++;}
}
assert.equal(checked,559);assert.equal(zeros,4);assert.equal(references.get(2007).n,26);assert.equal(references.get(2023).n,29);assert.equal(references.get(2024).n,32);
assert.equal(core.mobilityPercentileFor(references,2011,'00-0033873').percentile,null);assert.equal(core.mobilityPercentileFor(references,2023,'unknown').percentile,null);
for(const row of [...data.rows].reverse())core.mobilityPercentileFor(references,row.season,row.player_key);
assert.equal(JSON.stringify([...references]),frozen,'No opponent/search/lookup mutation of fixed annual reference pools');
assert.ok(data.rows.some(r=>r.scramble_contribution<0),'Signed negative contributions remain signed');
for(const bad of [new Uint8Array(),new Uint8Array(bytes).fill(32,0,1)])await assert.rejects(()=>core.validateAnnualMobility(bad,manifest,annual,legacy));
await assert.rejects(()=>core.validateAnnualMobility(bytes,new Uint8Array(),annual,legacy));
const template=data.rows[0],synthetic={...data,seasons:[2023],rows:[-1,0,0,2].map((value,i)=>({...template,player_key:String(i),season:2023,scramble_contribution:value}))};
const tied=await core.buildMobilityReferences(synthetic);assert.equal(core.mobilityPercentileFor(tied,2023,'1').percentile,50);assert.equal(core.mobilityPercentileFor(tied,2023,'0').percentile,12.5);
const single=await core.buildMobilityReferences({...synthetic,rows:synthetic.rows.slice(0,1)});assert.equal(core.mobilityPercentileFor(single,2023,'0').percentile,null);
let maxLegacyDelta=0;for(const old of legacy.rows){const row=data.rows.find(r=>r.player_key===old.player_key&&r.season===old.season);for(const field of ['scramble_contribution','scramble_contribution_lower','scramble_contribution_upper'])maxLegacyDelta=Math.max(maxLegacyDelta,Math.abs(row[field]-old[field]));}assert.ok(maxLegacyDelta<=1e-10);
let staticMobilityCells=0;const page=new URL('dist/projects/nfl-qbs-re-evaluated/index.html',root);
if(existsSync(page)){
 const html=readFileSync(page,'utf8'),table=html.match(/<table data-static-default[\s\S]*?<\/table>/)?.[0];assert.ok(table);
 const row=[...table.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/g)].slice(1)[3][0],cells=[...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)];assert.equal(cells.length,2);
 for(const [i,id]of ['00-0033873','00-0034857'].entries()){const result=core.mobilityPercentileFor(references,2023,id);assert.ok(cells[i][1].startsWith(`${Math.floor(result.percentile+.5)} percentile`));assert.ok(cells[i][1].includes('N=29'));assert.ok(cells[i][1].includes('annual finite eligible peers'));staticMobilityCells++;}
}
console.log(JSON.stringify({status:'passed',rows:560,finitePoints:checked,blockedPoints:1,naturalZeros:zeros,referenceGroups:references.size,independentPercentiles:checked,maxPercentileDelta:maxDelta,legacyNativeRecordsReconciled:40,maxLegacyDelta,hashFailureCases:3,syntheticTieZeroNegativeSingleton:'passed',fixedReferences:'unchanged',staticMobilityCells,browserChecks:'separate'},null,2));
