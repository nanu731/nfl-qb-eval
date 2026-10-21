// Shared build/browser contract for the accepted, immutable aggregate pair.
export const DATA_URL = '/data/nfl-qb-2023-2024-v2.json';
export const MANIFEST_URL = '/data/nfl-qb-2023-2024-v2.manifest.json';
export const PAYLOAD_SHA = '56c45de0fefde398d74ca31763e56fd86b60c43dd2c3f3b20be566acb57241e1';
export const MANIFEST_SHA = 'a707dce3334864193fde79576c69940170b5cadb59ce3fa35df7b7b4f1878a62';
export type Row = { player_key: string; observed_name: string; season: number; [field: string]: string | number | null };
export type Study = { study_id: string; analysis: string; seasons: number[]; metric: string; statistic: string; estimate: number | null; lower: number | null; upper: number | null; status: string; cohort_count: number; contributing_games?: number; point_status?: string; influence?: Record<string, number> };
export type Domain = { min: number | null; max: number | null; unit: string; status: string; includes_marginal_limits?: boolean; constant_observed?: boolean };
export type Payload = { schema_version: number; data_version: string; generated_utc: string; seasons: number[]; cohort: {count: number; rows: number; definition: string; limitation: string}; rows: Row[]; study_associations: Study[]; units: Record<string,string>; domains: Record<string,Domain>; aggregate_input_hashes: Record<string,string>; analysis_versions: Record<string,{script_sha256: string; specification_sha256: string}> };
const IDS = ['00-0026498','00-0029263','00-0030565','00-0031280','00-0033106','00-0033873','00-0034796','00-0034855','00-0034857','00-0035289','00-0036212','00-0036264','00-0036355','00-0036389','00-0036442','00-0036971','00-0036972','00-0037834','00-0039150','00-0039163'];
const equal = (a: unknown,b: unknown) => JSON.stringify(a) === JSON.stringify(b);
function requireData(ok: unknown): asserts ok { if (!ok) throw new Error('The comparison data does not match the reviewed version.'); }
export async function sha(bytes: Uint8Array): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes as Uint8Array<ArrayBuffer>))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
const available = ['approximate_conditional_game_sampling_sensitivity','collapsed_no_observed_deletion_variation'];
const unavailable = ['nonpositive_O','fewer_than_two_O_games','nonpositive_deleted_O','nonfinite_ratio','nonfinite_or_invalid_variance','no_opportunities','fewer_than_two_games','nonpositive_deletion_denominator','nonfinite_mean_or_deletion','nonfinite_interval_endpoints'];
function bounds(lo: unknown,hi: unknown,status: string,yes: string[],no: string[]) {
  requireData(yes.includes(status) || no.includes(status));
  if (yes.includes(status)) requireData(typeof lo==='number' && Number.isFinite(lo) && typeof hi==='number' && Number.isFinite(hi) && lo<=hi);
  else requireData(lo===null && hi===null);
}
export async function validatePair(bytes: Uint8Array, manifestBytes: Uint8Array): Promise<Payload> {
  // Check exact approved bytes first, then schema and semantic binding in both runtimes.
  requireData(await sha(bytes)===PAYLOAD_SHA && await sha(manifestBytes)===MANIFEST_SHA);
  const p = JSON.parse(new TextDecoder().decode(bytes)) as Payload;
  const m = JSON.parse(new TextDecoder().decode(manifestBytes));
  requireData(p.schema_version===2 && p.data_version==='2023-2024-broader-profile-v2' && equal(p.seasons,[2023,2024]));
  requireData(m.payload.filename===DATA_URL.split('/').pop() && m.payload.sha256===PAYLOAD_SHA);
  for (const k of ['schema_version','data_version','generated_utc','seasons','units','domains','aggregate_input_hashes'] as const) requireData(equal(p[k],m[k]));
  requireData(p.cohort.count===20 && p.cohort.rows===40 && m.cohort_count===20 && m.row_count===40 && m.study_row_count===10);
  requireData(p.rows.length===40 && p.study_associations.length===10 && m.export_script_sha256===p.analysis_versions.export.script_sha256);
  requireData(p.analysis_versions.export.specification_sha256==='ce69303df3bb8708a3d85992bdf6c03bbf0215c7f71f69cf07911d7529328149');
  requireData(new Set(p.rows.map(r=>`${r.player_key}:${r.season}`)).size===40 && equal([...new Set(p.rows.map(r=>r.player_key))].sort(),IDS));
  for (const id of IDS) requireData(equal(p.rows.filter(r=>r.player_key===id).map(r=>r.season).sort(),[2023,2024]));
  for (const r of p.rows) {
    requireData(typeof r.observed_name==='string' && r.observed_name.length>0 && p.rows.filter(x=>x.player_key===r.player_key).every(x=>x.observed_name===r.observed_name));
    for (const [key,value] of Object.entries(r)) if (typeof value==='number') requireData(Number.isFinite(value));
    for (const key of ['eligible_throws','eligible_games','dropbacks','dropback_games','sacks','scramble_runs','nonscramble_runs','combined_opportunities','combined_games','scramble_games','nonscramble_games']) requireData(Number.isInteger(r[key]) && Number(r[key])>=0);
    requireData(Number(r.eligible_throws)>=200 && Number(r.eligible_games)>=10 && Number(r.combined_opportunities)===Number(r.dropbacks)+Number(r.nonscramble_runs));
    requireData(Number(r.dropbacks)>=Number(r.sacks)+Number(r.scramble_runs));
    requireData(Math.abs(Number(r.sack_avoidance_pct)-100*(Number(r.dropbacks)-Number(r.sacks))/Number(r.dropbacks))<1e-10);
    bounds(r.epa_lower,r.epa_upper,String(r.epa_interval_status),available,unavailable);
    for (const tag of ['scramble','nonscramble']) {
      bounds(r[`${tag}_contribution_lower`],r[`${tag}_contribution_upper`],String(r[`${tag}_interval_status`]),available,unavailable);
      requireData(Math.abs(Number(r[`${tag}_share_pct`])-100*Number(r[`${tag}_runs`])/Number(r.combined_opportunities))<1e-10);
      const zero = r[`${tag}_role_mean_status`]==='no_recorded_role_opportunities';
      requireData(zero || r[`${tag}_role_mean_status`]==='observed_role_mean');
      if (zero) requireData(r[`${tag}_runs`]===0 && r[`${tag}_share_pct`]===0 && r[`${tag}_contribution`]===0 && r[`${tag}_epa_per_run`]===null);
      else requireData(Number(r[`${tag}_runs`])>0 && typeof r[`${tag}_epa_per_run`]==='number');
    }
  }
  for (const [i,year] of [2023,2024].entries()) for (const [field,totals] of Object.entries({eligible_throws:[9705,8517],dropbacks:[11371,9989],combined_opportunities:[11759,10358],nonscramble_runs:[388,369],scramble_runs:[558,504]})) requireData(p.rows.filter(r=>r.season===year).reduce((s,r)=>s+Number(r[field]),0)===totals[i]);
  for (const [field,metric] of Object.entries(METRICS)) {
    const d=p.domains[field]; requireData(d && d.unit===metric.unit && p.units[field]===metric.unit);
    const nums=p.rows.flatMap(r=>[r[field],...(metric.lower?[r[metric.lower],r[metric.upper!]]:[])]).filter((x):x is number=>typeof x==='number');
    requireData(d.status==='available' && typeof d.min==='number' && typeof d.max==='number' && d.min<d.max && nums.every(n=>n>=d.min! && n<=d.max!));
    if (metric.unit==='percent') requireData(d.min>=0 && d.max<=100); else requireData(d.min<=0 && d.max>=0);
  }
  requireData(p.domains.study_correlation.min===-1 && p.domains.study_correlation.max===1 && p.domains.study_delta.min===-2 && p.domains.study_delta.max===2 && p.domains.recorded_composition_pct.min===0 && p.domains.recorded_composition_pct.max===100);
  const studyKeys=p.study_associations.map(s=>`${s.study_id}:${s.analysis}:${s.metric}`);
  requireData(new Set(studyKeys).size===10 && p.study_associations.filter(s=>s.study_id==='annual_cpoe_comparison').length===3 && p.study_associations.filter(s=>s.study_id==='recorded_sack_avoidance').length===3 && p.study_associations.filter(s=>s.study_id==='recorded_run_contribution').length===4);
  for (const s of p.study_associations) {
    requireData(s.cohort_count===20 && equal(s.seasons,s.analysis==='annual'?[2023,2024]:[2023]));
    bounds(s.lower,s.upper,s.status,['conditional_working_model_sensitivity','approximate_95pct_conditional_working_model_sensitivity'],['undefined_full_correlation','perfect_full_correlation','undefined_deletion_correlation','perfect_deletion_correlation','fewer_than_two_games_in_stratum','nonfinite_variance','zero_or_invalid_variance']);
    requireData(s.estimate===null || Number.isFinite(s.estimate));
    if(s.study_id!=='annual_cpoe_comparison') requireData(s.contributing_games===(s.analysis==='annual'?431:223) && ['defined','nonpositive_O_or_nonfinite_contribution','nonfinite_rate','zero_actor_variance','nonfinite_correlation','perfect_correlation'].includes(s.point_status!));
  }
  return p;
}
export type Metric = {label: string; short: string; unit: string; unitLabel: string; lower?: string; upper?: string; status?: string; population: 'E'|'D'|'O'|'role'};
export const METRICS: Record<string,Metric> = {
  cpoe_pp:{label:'CPOE',short:'CPOE (pp)',unit:'percentage_points',unitLabel:'percentage points',population:'E'},
  completion_pct:{label:'Completion percentage',short:'Completion (%)',unit:'percent',unitLabel:'percent',population:'E'},
  epa_per_dropback:{label:'Recorded-dropback EPA',short:'EPA / dropback',unit:'expected_points_per_dropback',unitLabel:'expected points per dropback',lower:'epa_lower',upper:'epa_upper',status:'epa_interval_status',population:'D'},
  sack_avoidance_pct:{label:'Recorded sack avoidance',short:'Sack avoidance (%)',unit:'percent',unitLabel:'percent of dropbacks',population:'D'},
  scramble_share_pct:{label:'Scramble share',short:'Scramble share (%)',unit:'percent',unitLabel:'percent of combined opportunities',population:'O'},
  nonscramble_share_pct:{label:'Non-scramble run share',short:'Run share (%)',unit:'percent',unitLabel:'percent of combined opportunities',population:'O'},
  scramble_contribution:{label:'Scramble contribution',short:'Scramble EPA / O',unit:'expected_points_per_combined_opportunity',unitLabel:'expected points per combined opportunity',lower:'scramble_contribution_lower',upper:'scramble_contribution_upper',status:'scramble_interval_status',population:'O'},
  nonscramble_contribution:{label:'Non-scramble run contribution',short:'Run EPA / O',unit:'expected_points_per_combined_opportunity',unitLabel:'expected points per combined opportunity',lower:'nonscramble_contribution_lower',upper:'nonscramble_contribution_upper',status:'nonscramble_interval_status',population:'O'},
  scramble_epa_per_run:{label:'Scramble EPA per run',short:'EPA / scramble',unit:'expected_points_per_role_run',unitLabel:'expected points per role run',population:'role'},
  nonscramble_epa_per_run:{label:'Non-scramble EPA per run',short:'EPA / run',unit:'expected_points_per_role_run',unitLabel:'expected points per role run',population:'role'},
};
export const PRIMARY = ['cpoe_pp','epa_per_dropback','sack_avoidance_pct','scramble_contribution','nonscramble_contribution','completion_pct'];
export const VIEWS = {
  compare:{title:'Player comparison',metrics:PRIMARY,annual:false,description:'Two recorded values on one native-unit scale. Bars show available marginal 95% conditional sensitivities; they do not test the difference between players.'},
  change:{title:'Two-season trajectories',metrics:PRIMARY,annual:true,description:'Observed values in 2023 and 2024. Marginal endpoint intervals do not test season changes or establish development.'},
  usage:{title:'Usage and contribution',metrics:['scramble_contribution','nonscramble_contribution'],annual:false,description:'All 20 passers: role frequency versus contribution per combined opportunity. Contribution mechanically combines frequency and shared value; it does not isolate athletic ability.'},
  composition:{title:'Recorded composition',metrics:['composition'],annual:false,description:'Other D passes, sacks, scrambles and recorded non-scramble runs form disjoint parts of O. Non-scramble runs include aborted and lateral plays; intent remains unknown.'},
  study:{title:'Study-level evidence',metrics:['study'],annual:true,description:'All ten accepted study rows in a fixed order. Split and annual associations answer different questions. The paired correlation difference has a separate scale. These studies share data.'},
  association:{title:'Paired-season association',metrics:['cpoe_pp','completion_pct','sack_avoidance_pct','scramble_contribution','nonscramble_contribution'],annual:true,description:'All 20 passers across both years. The copied annual association describes alignment within this selected cohort; it does not establish a forecast or isolated skill.'},
};
export type View = keyof typeof VIEWS;
export function fmt(n: number|string|null|undefined,places=3): string {
  if(typeof n!=='number' || !Number.isFinite(n)) return 'Unavailable';
  if(n!==0 && Math.abs(n)<10**(-places)) return n.toPrecision(3);
  return Number(n.toFixed(places)).toString();
}
export function evidence(r: Row,f:string): string {
  const m=METRICS[f];
  const pop=m.population==='E'?`${r.eligible_throws} throws; ${r.eligible_games} E games`:m.population==='D'?`${r.dropbacks} dropbacks; ${r.dropback_games} D games`:`${r.combined_opportunities} combined opportunities; ${r.combined_games} O games`;
  return pop+(f.startsWith('scramble')?`; ${r.scramble_runs} scrambles in ${r.scramble_games} games`:f.startsWith('nonscramble')?`; ${r.nonscramble_runs} non-scramble runs in ${r.nonscramble_games} games`:f==='sack_avoidance_pct'?`; ${r.sacks} sacks`:'');
}
export function interval(r:Row,f:string): string { const m=METRICS[f];return m.lower?`${fmt(r[m.lower])} to ${fmt(r[m.upper!])}; ${String(r[m.status!]).replaceAll('_',' ')}`:'Individual interval not estimated'; }
export function studyLabel(s:Study): string {
  const metric=s.statistic==='Delta'?'CPOE minus completion r':METRICS[s.metric]?.label ?? s.metric;
  const period=s.analysis==='annual'?'2023–2024 annual':`2023 ${s.analysis}`;
  return `${metric} · ${period}`;
}
export function composition(r:Row): [string,number][] {return [['Other D passes',Number(r.dropbacks)-Number(r.sacks)-Number(r.scramble_runs)],['Sacks',Number(r.sacks)],['Scrambles',Number(r.scramble_runs)],['Non-scramble runs',Number(r.nonscramble_runs)]];}
