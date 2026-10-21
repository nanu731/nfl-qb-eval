// Annual scramble contribution is separate from the preserved original 20-QB study.
import {sha,PAYLOAD_SHA,MANIFEST_SHA,type Payload} from './nfl-comparison';
import {ANNUAL_SHA,ANNUAL_MANIFEST_SHA,DEPTH_SHA,DEPTH_MANIFEST_SHA,type AnnualPayload} from './nfl-annual';
import {midpointPercentile,PERCENTILE_FORMULA_VERSION} from './nfl-percentiles';
export const MOBILITY_URL='/data/nfl-qb-mobility-2006-2025-v1.json';
export const MOBILITY_MANIFEST_URL='/data/nfl-qb-mobility-2006-2025-v1.manifest.json';
export const MOBILITY_SHA='6e34317d81aa90421d1ebb6be9d6aa21c939ef97ed1bf6b1ed73a766b52a6f4a';
export const MOBILITY_MANIFEST_SHA='9088accdc85530821387d4fec4cf479f04a2249b1777c190b9676709613208fc';
export type MobilityRow={player_key:string;season:number;observed_name:string;display_name:string;name_status:string;dropbacks:number;dropback_games:number;sacks:number;scramble_runs:number;nonscramble_runs:number;combined_opportunities:number;combined_games:number;scramble_games:number;nonscramble_games:number;scramble_contribution:number|null;scramble_contribution_lower:number|null;scramble_contribution_upper:number|null;point_status:'observed_contribution'|'blocked_pending_role_review';scramble_interval_status:string;unavailable_reason:string|null};
type CatalogRow={season:number;status:string;reason:string|null;row_count:number;finite_point_count:number};
export type MobilityPayload={schema_version:1;data_version:string;seasons:number[];season_catalog:CatalogRow[];rows:MobilityRow[];reference_population:{counts:{season:number;eligible_player_seasons:number;finite_accepted_values:number}[]}};
export type MobilityReference={year:number;n:number;keyHash:string;peers:readonly {playerKey:string;value:number}[]};
export type MobilityReferences=Map<number,MobilityReference>;
const equal=(a:unknown,b:unknown)=>JSON.stringify(a)===JSON.stringify(b);
const finite=(value:unknown):value is number=>typeof value==='number'&&Number.isFinite(value);
function requireData(value:unknown):asserts value{if(!value)throw Error('Annual Mobility data does not match the reviewed version.');}
export async function validateAnnualMobility(bytes:Uint8Array,manifestBytes:Uint8Array,annual:AnnualPayload,legacy:Payload):Promise<MobilityPayload>{
 requireData(await sha(bytes)===MOBILITY_SHA&&await sha(manifestBytes)===MOBILITY_MANIFEST_SHA);
 const p=JSON.parse(new TextDecoder().decode(bytes)),m=JSON.parse(new TextDecoder().decode(manifestBytes));
 requireData(p.schema_version===1&&p.data_version==='2006-2025-annual-mobility-v1'&&p.dataset_kind==='independent_annual_scramble_contribution');
 requireData(m.payload.filename===MOBILITY_URL.split('/').pop()&&m.payload.sha256===MOBILITY_SHA);
 for(const field of ['schema_version','data_version','dataset_kind','generated_utc','season_catalog','units','reference_population','analysis_versions'])requireData(equal(p[field],m[field]));
 requireData(equal(p.sources,m.input_provenance)&&m.export_script_sha256===p.analysis_versions.export_script_sha256);
 requireData(p.analysis_versions.method==='AMC-1.0'&&p.analysis_versions.recorded_dropbacks==='AD-1.1');
 requireData(p.analysis_versions.proposal_sha256==='621389f64511131cfa3d9841a64af9e3bf594c7c2eea7716d6916271088552a6');
 requireData(p.analysis_versions.export_script_sha256==='79c99ea8048d2bd9bc1e735d99b99123ae29132a40739261f42010e3574947a4');
 requireData(p.analysis_versions.original_rushing_script_sha256==='4f29f1e61e781f3f382ed6ef06d420f12ca45cf9dd93db7d8d89e087b3c91e07');
 const pins:Record<string,string>={'nfl-qb-2023-2024-v2.json':PAYLOAD_SHA,'nfl-qb-2023-2024-v2.manifest.json':MANIFEST_SHA,'nfl-qb-annual-2006-2025-v1.json':ANNUAL_SHA,'nfl-qb-annual-2006-2025-v1.manifest.json':ANNUAL_MANIFEST_SHA,'nfl-qb-depth-2006-2025-v1.json':DEPTH_SHA,'nfl-qb-depth-2006-2025-v1.manifest.json':DEPTH_MANIFEST_SHA};
 requireData(p.sources.unchanged_accepted_assets.length===6&&p.sources.unchanged_accepted_assets.every((r:{filename:string;sha256:string})=>pins[r.filename]===r.sha256));
 requireData(p.rows.length===560&&m.row_count===560&&m.finite_point_count===559&&m.row_keys_sha256==='2d0d23a86a39598fad210aa062700990de6282168b2149ab987fb4b084ccb59c');
 const annualRows=new Map(annual.rows.map(row=>[`${row.player_key}:${row.season}`,row])),seen=new Set<string>();let observed=0,blocked=0,zeros=0;
 for(const row of p.rows as MobilityRow[]){
  const key=`${row.player_key}:${row.season}`,source=annualRows.get(key);requireData(source&&!seen.has(key));seen.add(key);
  requireData(row.display_name===source.display_name&&row.observed_name===source.observed_name&&row.name_status===source.name_status);
  for(const field of ['dropbacks','dropback_games','sacks','scramble_runs','nonscramble_runs','combined_opportunities','combined_games','scramble_games','nonscramble_games'] as const)requireData(Number.isInteger(row[field])&&row[field]>=0);
  for(const field of ['dropbacks','dropback_games','sacks','scramble_runs'] as const)requireData(row[field]===source[field]);
  requireData(row.dropbacks>=row.sacks+row.scramble_runs&&row.combined_opportunities===row.dropbacks+row.nonscramble_runs&&row.combined_opportunities>0);
  requireData(row.combined_games>=row.dropback_games&&row.combined_games>=row.nonscramble_games&&row.combined_games<=row.dropback_games+row.nonscramble_games&&row.scramble_games<=row.dropback_games);
  if(row.point_status==='observed_contribution'){
   requireData(finite(row.scramble_contribution)&&finite(row.scramble_contribution_lower)&&finite(row.scramble_contribution_upper)&&row.scramble_contribution_lower<=row.scramble_contribution&&row.scramble_contribution<=row.scramble_contribution_upper&&row.unavailable_reason===null);
   requireData(['approximate_conditional_game_sampling_sensitivity','collapsed_no_observed_deletion_variation'].includes(row.scramble_interval_status));observed++;
   if(row.scramble_runs===0){requireData(row.scramble_contribution===0&&row.scramble_contribution_lower===0&&row.scramble_contribution_upper===0&&row.scramble_interval_status==='collapsed_no_observed_deletion_variation');zeros++;}
  }else{
   requireData(key==='00-0022164:2007'&&row.point_status==='blocked_pending_role_review'&&row.scramble_interval_status==='blocked_pending_role_review'&&row.scramble_contribution===null&&row.scramble_contribution_lower===null&&row.scramble_contribution_upper===null&&typeof row.unavailable_reason==='string'&&row.unavailable_reason.length>0);blocked++;
  }
 }
 requireData(seen.size===annualRows.size&&observed===559&&blocked===1&&zeros===4);
 requireData(equal(p.seasons,annual.season_catalog.filter(y=>y.status==='exported').map(y=>y.season))&&p.season_catalog.length===20&&p.reference_population.counts.length===19);
 for(const year of annual.season_catalog){
  const catalog=p.season_catalog.find((y:CatalogRow)=>y.season===year.season);requireData(catalog&&catalog.status===year.status&&catalog.reason===year.reason&&catalog.row_count===year.row_count);
  const rows=(p.rows as MobilityRow[]).filter(row=>row.season===year.season),n=rows.filter(row=>finite(row.scramble_contribution)).length;requireData(rows.length===year.row_count&&catalog.finite_point_count===n);
  const reference=p.reference_population.counts.find((r:{season:number})=>r.season===year.season);
  requireData(year.season===2011?!reference&&n===0:reference?.eligible_player_seasons===rows.length&&reference.finite_accepted_values===n);
 }
 for(const old of legacy.rows){
  const row=(p.rows as MobilityRow[]).find(row=>row.player_key===old.player_key&&row.season===old.season);requireData(row);
  for(const field of ['scramble_contribution','scramble_contribution_lower','scramble_contribution_upper'] as const){const value=old[field];requireData(value===null?row[field]===null:finite(value)&&finite(row[field])&&Math.abs(value-row[field])<=1e-10);}
 }
 return p as MobilityPayload;
}
export async function buildMobilityReferences(payload:MobilityPayload):Promise<MobilityReferences>{
 const references:MobilityReferences=new Map();
 for(const year of payload.seasons){
  const peers=payload.rows.filter(row=>row.season===year&&finite(row.scramble_contribution)).map(row=>({playerKey:row.player_key,value:row.scramble_contribution!})).sort((a,b)=>a.playerKey<b.playerKey?-1:a.playerKey>b.playerKey?1:0);
  const csv='metric,player_key,season\n'+peers.map(peer=>`annual_scramble_contribution,${peer.playerKey},${year}\n`).join('');
  references.set(year,{year,peers,n:peers.length,keyHash:await sha(new TextEncoder().encode(csv))});
 }
 return references;
}
export function mobilityPercentileFor(references:ReadonlyMap<number,MobilityReference>,year:number,id:string){
 const reference=references.get(year),peer=reference?.peers.find(row=>row.playerKey===id),percentile=peer&&reference?midpointPercentile(peer.value,reference.peers.map(row=>row.value)):null;
 return {percentile,n:reference?.n??0,keyHash:reference?.keyHash??null,year,cohort:'annual-mobility-v1' as const,formulaVersion:PERCENTILE_FORMULA_VERSION,reason:percentile===null?'No finite accepted annual scramble contribution for this player and year.':'available'};
}
