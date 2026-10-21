// Node24 source checks; native interaction and visual checks are recorded separately.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
const root=new URL('../',import.meta.url),cache=new Map();
const buildRoot=process.env.NFL_PORTFOLIO_ROOT?pathToFileURL(resolve(process.env.NFL_PORTFOLIO_ROOT)+'/'):root;
async function load(relative){
 if(cache.has(relative))return cache.get(relative);
 let source=stripTypeScriptTypes(readFileSync(new URL(relative,root),'utf8'));
 for(const match of [...source.matchAll(/from\s+['"](.\/.+?)['"]/g)]){
  const target=fileURLToPath(new URL(match[1]+'.ts',new URL(relative,root))).slice(fileURLToPath(root).length);
  source=source.replace(match[0],`from '${await load(target)}'`);
 }
 const url=`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;cache.set(relative,url);return url;
}
const experts=await import(await load('src/lib/nfl-experts.ts'));
const {EXPERT_RANKS,EXPERT_SOURCE,EXPERT_SOURCES,expertFor,processingFor,expertRadius,validateExpertRanks}=experts;
const expected=[['00-0033873','arm_strength',2,.9],['00-0034857','arm_strength',1,1],['00-0033873','field_vision',1,1],['00-0034857','field_vision',4,.7]];
assert.equal(EXPERT_SOURCE.published,'2023-08-14');
assert.equal(EXPERT_SOURCE.url,'https://www.espn.in/nfl/story/_/id/38151402/nfl-quarterback-council-2023-ranking-top-10-traits');
assert.equal(EXPERT_RANKS.length,84);assert.equal(createHash('sha256').update(JSON.stringify(EXPERT_RANKS)).digest('hex'),'08c20ea843c3a37735e3828d7df99a43544b36fbc3cc4c6ddcdd45eed2afb46c');
assert.deepEqual(['arm_strength','field_vision','decision_making'].map(t=>EXPERT_RANKS.filter(r=>r.trait===t).length),[41,26,17]);
assert.equal(processingFor(2024,'00-0034857'),undefined);assert.equal(expertFor('arm_strength',2024,'00-0034857').rank,2);
assert.equal(experts.mixedExpertSources(expected.map(([id,trait])=>expertFor(trait,2023,id))),false);
assert.equal(experts.mixedExpertSources([expertFor('arm_strength',2023,'00-0033873'),expertFor('arm_strength',2024,'00-0034857')]),true,'Arm-source changes warn even without a Processing entry');
assert.equal(experts.mixedExpertSources([]),false);
assert.equal(EXPERT_RANKS.find(r=>r.tied).rankLabel,'T4');assert.equal(EXPERT_SOURCES['2024'].byline,'Dan Orlovsky');
for(const [id,trait,rank,radius] of expected){assert.equal(expertFor(trait,2023,id).rank,rank);assert.equal(expertRadius(rank),radius);}
for(const rank of [null,NaN,Infinity,-1,0,1.5,11])assert.equal(expertRadius(rank),null);
assert.equal(expertRadius(10),.1);
const annual=JSON.parse(readFileSync(new URL('public/data/nfl-qb-annual-2006-2025-v1.json',root)));
const depth=JSON.parse(readFileSync(new URL('public/data/nfl-qb-depth-2006-2025-v1.json',root)));
const legacy=JSON.parse(readFileSync(new URL('public/data/nfl-qb-2023-2024-v2.json',root)));
let lookups=0;
for(const row of annual.rows)for(const trait of ['arm_strength','field_vision','decision_making']){
 const found=expertFor(trait,row.season,row.player_key),fact=EXPERT_RANKS.find(r=>r.playerKey===row.player_key&&r.trait===trait&&r.year===row.season);
 assert.equal(found?.rank,fact?.rank);lookups++;
}
assert.equal(expertFor('arm_strength',2011,'00-0033873'),undefined);
assert.equal(expertFor('field_vision',2024,'00-0034857'),undefined);
for(const mutate of [rows=>rows.pop(),rows=>rows.push({...rows[0]}),rows=>rows[0].rank=NaN,rows=>rows[0].rank=0,rows=>rows[0].rank=11,rows=>rows[0].rank=1.5,rows=>rows[0].rank=rows[0].rank===3?2:3,rows=>rows[0].year=2024,rows=>rows[0].playerKey='unknown',rows=>rows[0].trait='decision_making',rows=>rows[0].extra=true,rows=>rows[0]={...rows[1]}]){
 const rows=structuredClone(EXPERT_RANKS);mutate(rows);assert.throws(()=>validateExpertRanks(rows));
}
const mobilityCore=await import(await load('src/lib/nfl-mobility.ts'));
const mobilityData=await mobilityCore.validateAnnualMobility(new Uint8Array(readFileSync(new URL('public'+mobilityCore.MOBILITY_URL,root))),new Uint8Array(readFileSync(new URL('public'+mobilityCore.MOBILITY_MANIFEST_URL,root))),annual,legacy);
// Exercise the real renderer with a minimal SVG DOM. Native-browser checks remain separate.
class Node {constructor(tag){this.tag=tag;this.attrs={};this.children=[];this.dataset={};this.parentElement={getBoundingClientRect:()=>({width:560})};}setAttribute(k,v){this.attrs[k]=String(v);}removeAttribute(k){delete this.attrs[k];}append(...els){this.children.push(...els);}replaceChildren(...els){this.children=els;}}
globalThis.document={createElementNS:(_,tag)=>new Node(tag)};
globalThis.HTMLElement=class {};
const registry=new Map();globalThis.customElements={get:k=>registry.get(k),define:(k,v)=>registry.set(k,v)};
const charts=await import(await load('src/lib/nfl-charts.ts'));charts.registerNFL();
const host=new (registry.get('nfl-comparison'))(),svg=new Node('svg');host.querySelector=()=>svg;host.annual=annual;host.depth=depth;host.legacy=legacy;host.mobility=mobilityData;host.mobilityReferences=await mobilityCore.buildMobilityReferences(mobilityData);
const percentile=await import(await load('src/lib/nfl-percentiles.ts'));host.references=await percentile.buildPercentileReferences(annual,depth,legacy);
const selected=(side,id,year)=>({side,id,year,name:annual.rows.find(r=>r.player_key===id)?.display_name??id,row:annual.rows.find(r=>r.player_key===id&&r.season===year),legacy:legacy.rows.find(r=>r.player_key===id&&r.season===year),mobility:mobilityData.rows.find(r=>r.player_key===id&&r.season===year),depth:depth.rows.filter(r=>r.player_key===id&&r.season===year)});
const a=selected('a','00-0033873',2023),b=selected('b','00-0034857',2023);
const nodes=cls=>svg.children.filter(n=>(n.attrs.class??'').split(' ').includes(cls));
host.drawRadar([a,b]);assert.equal(nodes('radar-mark').length,14);assert.equal(nodes('radar-segment').length,14);assert.equal(nodes('expert-spoke').length,2);
assert.equal(svg.children.some(n=>n.tag==='polygon'),false);assert.equal(svg.children.some(n=>n.attrs.class==='tick'),false);
for(const mark of nodes('radar-mark')){
 const attrs=mark.attrs,fraction=Number(attrs['data-radius'])/Number(attrs['data-radius-max']);
 if(attrs['data-kind']==='expert'){
  const fact=expected.find(([id,trait])=>id===(attrs['data-side']==='a'?a.id:b.id)&&trait===attrs['data-field']);
  assert.equal(Number(attrs['data-rank']),fact[2]);assert.equal(attrs['data-percentile'],undefined);assert.ok(Math.abs(fraction-fact[3])<1e-12);
 }else assert.ok(Math.abs(fraction-Number(attrs['data-percentile'])/100)<1e-12);
}
for(const [name,pair,counts,closing] of [
 ['independent2024',[a,selected('b',b.id,2024)],[7,6],[true,false]],
 ['sourceblocked2011',[a,selected('b',b.id,2011)],[7,0],[true,false]],
 ['unauditedQB',[a,selected('b','00-0037077',2023)],[7,5],[true,false]],
 ['identical',[a,{...a,side:'b'}],[7,7],[true,true]],
 ['nativeNull',[{...a,depth:a.depth.map(r=>r.bin==='medium'?{...r,cpoe_pp:null}:r)},b],[6,7],[false,true]],
]){
 host.drawRadar(pair);
 for(const [i,side]of ['a','b'].entries()){
  assert.equal(nodes('radar-mark').filter(n=>n.attrs['data-side']===side).length,counts[i],name);
  assert.equal(nodes('radar-segment').some(n=>n.attrs['data-side']===side&&n.attrs['data-from']==='6'&&n.attrs['data-to']==='0'),closing[i],name);
 }
 assert.ok(nodes('radar-segment').every(n=>Number(n.attrs['data-to'])===Number(n.attrs['data-from'])+1||(n.attrs['data-from']==='6'&&n.attrs['data-to']==='0')),'No gap-bridging segment');
}
const html=readFileSync(new URL('dist/projects/nfl-qbs-re-evaluated/index.html',buildRoot),'utf8');
assert.ok(html.includes('2006–2025, excluding 2011'));
assert.ok(!/source[- ]blocked/i.test(html),'Visitor copy describes 2011 as excluded');
assert.equal((html.match(/data-view-intro=/g)??[]).length,2,'One introductory paragraph is available for each comparison view');
const table=html.match(/<table data-static-default[\s\S]*?<\/table>/)[0];
const expertCells=[...table.matchAll(/<td\b[^>]*data-static-expert[^>]*>([\s\S]*?)<\/td>/g)];
assert.equal(expertCells.length,4);
[2,1,1,4].forEach((rank,i)=>{assert.ok(expertCells[i][1].startsWith(`#${rank} expert rank`));assert.ok(expertCells[i][1].includes(EXPERT_SOURCE.url));});
assert.ok(/<button\b[^>]*data-complete-example/.test(html));
const labels=['Arm strength','Processing','Pocket presence','Mobility','Short accuracy','Medium accuracy','Deep accuracy'];
const keys=['arm-strength','processing','pocket-presence','mobility','short-accuracy','medium-accuracy','deep-accuracy'];
host.drawRadar([a,b]);
const links=nodes('radar-attribute-link');assert.equal(links.length,7);
links.forEach((link,i)=>{
 assert.equal(link.tag,'a');assert.equal(link.attrs.href,'#nfl-attribute-'+keys[i]);assert.equal(link.attrs.id,'nfl-radar-link-'+keys[i]);assert.equal(link.attrs.tabindex,'0');assert.equal(link.attrs.role,'link');
 assert.equal(link.children.find(n=>n.tag==='text').textContent,labels[i]);
 const hit=link.children.find(n=>n.tag==='rect');assert.ok(Number(hit.attrs.width)>=24&&Number(hit.attrs.height)>=24);
});
assert.ok(/<svg\b[^>]*data-radar[^>]*role="group"/.test(html),'Interactive chart exposes child links rather than flattening them into one image');
const guide=html.match(/<section\b[^>]*class="nfl-attribute-guide"[^>]*>([\s\S]*?)<\/section>/)?.[1];assert.ok(guide,'Always-open static guide is present');
assert.equal((guide.match(/<h3\b/g)??[]).length,7);
for(const key of keys){
 assert.ok(new RegExp('<h3\\b[^>]*id="nfl-attribute-'+key+'"[^>]*tabindex="-1"','i').test(guide));
 assert.ok(guide.includes('href="#nfl-radar-link-'+key+'"'));
}
// Compare every requirement subset with the marks emitted by the real renderer.
const referencesBefore=JSON.stringify(host.references),sourcesBefore=JSON.stringify([annual,depth,legacy]);
let availabilityComparisons=0;const complete=[],mobility=[];
for(const row of annual.rows){
 const choice=selected('a',row.player_key,row.season);host.drawRadar([choice,{...choice,side:'b'}]);
 const available=nodes('radar-mark').filter(n=>n.attrs['data-side']==='a').reduce((mask,n)=>mask|(1<<Number(n.attrs['data-position'])),0);
 for(let mask=0;mask<128;mask++){
  assert.equal(host.requirementsMatch(row.player_key,row.season,mask),(available&mask)===mask,`${row.player_key}/${row.season} subset ${mask}`);availabilityComparisons++;
 }
 if(host.requirementsMatch(row.player_key,row.season,127))complete.push([row.player_key,row.season]);
 if(host.requirementsMatch(row.player_key,row.season,8))mobility.push([row.player_key,row.season]);
}
assert.deepEqual(complete.sort(),[["00-0023459",2021],["00-0023459",2022],["00-0023459",2024],["00-0026498",2021],["00-0026498",2023],["00-0026498",2024],["00-0026498",2025],["00-0029263",2021],["00-0033077",2022],["00-0033873",2021],["00-0033873",2022],["00-0033873",2023],["00-0033873",2024],["00-0033873",2025],["00-0034796",2025],["00-0034857",2022],["00-0034857",2023],["00-0034857",2025],["00-0036355",2022],["00-0036355",2023],["00-0036355",2025],["00-0036389",2023],["00-0036971",2023]]);
assert.equal(mobility.length,559);assert.ok(!mobility.some(([id,year])=>id==='00-0022164'&&year===2007));
const orton=annual.rows.find(r=>r.observed_name==='K.Orton'&&r.season===2008)??annual.rows.find(r=>r.display_name==='Kyle Orton'&&r.season===2008);
assert.ok(orton);assert.equal(host.requirementsMatch(orton.player_key,2008,8),true);
assert.equal(host.requirementsMatch(a.id,2011,8),false);assert.equal(host.requirementsMatch(a.id,2024,1),true);
const originalPoint=host.profilePoint;
for(const [radius,expected]of [[0,true],[null,false],[NaN,false],[Infinity,false]]){host.profilePoint=()=>({radius});assert.equal(host.requirementsMatch(a.id,2023,1),expected,'Finite zero remains available');}
host.profilePoint=originalPoint;
host.players=[...new Map(annual.rows.map(r=>[r.player_key,{id:r.player_key,name:r.display_name}])).values()];
const controls={a:{value:orton.player_key},b:{value:b.id},'season-a':{value:'2008'},'season-b':{value:'2023'}};
host.control=key=>controls[key];host.requiredMask=8;
assert.ok(host.seasonPlayers('a').some(p=>p.id===orton.player_key));
assert.ok(host.seasonChoices('a').some(y=>y.season===2008));
assert.equal(host.requirementsMatch('00-0022164',2007,8),false);
controls.a.value='';controls['season-a'].value='';
assert.deepEqual(host.seasonChoices('a').map(y=>y.season),[...mobilityData.seasons].sort((a,b)=>b-a));
assert.ok(host.seasonPlayers('a').length>0,'Cleared year can search eligible players across matching years');
host.requiredMask=127;
assert.deepEqual(host.seasonPlayers('a').map(p=>p.id).sort(),[...new Set(complete.map(([id])=>id))].sort());
controls.a.value=a.id;assert.deepEqual(host.seasonChoices('a').map(y=>y.season),complete.filter(([id])=>id===a.id).map(([,year])=>year).sort((a,b)=>b-a));
host.requiredMask=0;assert.equal(host.seasonChoices('a').length,20);assert.ok(host.seasonChoices('a').some(y=>y.season===2011));
assert.equal(JSON.stringify(host.references),referencesBefore,'Requirements never alter reference pools');
assert.equal(JSON.stringify([annual,depth,legacy]),sourcesBefore,'Requirements never alter input records');
assert.equal((html.match(/type="checkbox"[^>]*data-require-attribute=/g)??[]).length,7);
assert.ok(/<button\b[^>]*data-clear-requirements/.test(html));
// Stats uses annual records and ignores the saved profile requirements.
const {readableStatTicks}=charts;
assert.deepEqual(readableStatTicks(-12.01,10.78),[-10,0,10]);assert.deepEqual(readableStatTicks(-.60,.58),[-.5,0,.5]);assert.deepEqual(readableStatTicks(85.85,98.3),[87.5,90,92.5,95,97.5]);
assert.ok(!html.includes('data-all-mobility'),'Raw Mobility ledger is not rendered in the visitor interface');
assert.ok(html.includes('data-expert-summary'),'Consolidated visible attribution remains available');
for(const side of ['a','b'])assert.ok(html.includes(`data-radar-legend-name="${side}"`));
assert.ok(!html.includes('circle, solid line')&&!html.includes('open diamond, dashed line'));
const {STATS,formatStatValue}=charts;assert.deepEqual(STATS.map(s=>s.field),['cpoe_pp','epa_per_dropback','sack_avoidance_pct']);
assert.equal(formatStatValue('cpoe_pp',1.24),'+1.2');assert.equal(formatStatValue('cpoe_pp',-1.24),'-1.2');assert.equal(formatStatValue('cpoe_pp',0),'+0.0');
assert.equal(formatStatValue('epa_per_dropback',.234),'0.23');assert.equal(formatStatValue('sack_avoidance_pct',98.456),'98.5');assert.equal(formatStatValue('cpoe_pp',null),'Unavailable');
host.view='stats';host.requiredMask=127;let statsAvailabilityComparisons=0;
for(const row of annual.rows){assert.equal(host.statsAvailable(row.player_key,row.season),true);assert.equal(host.selectionMatches(row.player_key,row.season),true);statsAvailabilityComparisons++;}
assert.equal(host.statsAvailable(a.id,2011),false);assert.equal(host.statsAvailable('unknown',2023),false);
controls.a.value=a.id;controls['season-a'].value='2024';
assert.equal(host.seasonPlayers('a').length,annual.rows.filter(r=>r.season===2024).length);
assert.deepEqual(host.seasonChoices('a').map(y=>y.season),annual.rows.filter(r=>r.player_key===a.id).map(r=>r.season).sort((a,b)=>b-a));
host.view='profile';assert.equal(host.selectionMatches(b.id,2024),false);assert.equal(host.selectionMatches(a.id,2024),true);assert.equal(host.selectionMatches(b.id,2023),true);
const savedAnnual=host.annual;host.annual={...annual,rows:[{...a.row,cpoe_pp:0,epa_per_dropback:0,sack_avoidance_pct:0}]};assert.equal(host.statsAvailable(a.id,2023),true);host.annual=savedAnnual;
for(const metric of STATS){
 const plot=new Node('svg');plot.id='stats-test';host.draw(plot,[a,b],metric.field,560,false);
 const marks=plot.children.filter(n=>n.attrs.class==='mark-a'||n.attrs.class==='mark-b');assert.equal(marks.length,2);
 for(const [i,mark]of marks.entries())assert.equal(Number(mark.dataset.value),[a,b][i].row[metric.field]);
 assert.equal(plot.children.some(n=>(n.attrs.class??'').includes('interval')),false,'No default sensitivity whiskers in Stats');
 assert.equal(plot.dataset.domain,`${annual.domains[metric.field].min},${annual.domains[metric.field].max}`);
}
for(const [view,id]of [['profile','nfl-profile-panel'],['stats','nfl-stats-panel']]){
 assert.ok(new RegExp('<button[^>]*role="tab"[^>]*data-project-view="'+view+'"[^>]*aria-controls="'+id+'"').test(html));
 assert.ok(html.includes('id="'+id+'"'));
}
const statsTable=html.match(/<table data-static-stats[\s\S]*?<\/table>/)?.[0];assert.ok(statsTable);assert.equal((statsTable.match(/<td\b/g)??[]).length,6);
for(const path of ['dist/index.html','dist/projects/index.html','dist/projects/nfl-qbs-re-evaluated/index.html']){
 const built=readFileSync(new URL(path,buildRoot),'utf8');assert.ok(built.includes('NFL QBs Visualized'),path);assert.ok(!built.includes('NFL QBs Re-evaluated'),path);
}
assert.equal(JSON.stringify(host.references),referencesBefore,'Stats choices do not change profile reference pools');
console.log(JSON.stringify({status:'passed',expertFacts:84,expertLookups:lookups,invalidRecordCases:12,defaultPoints:14,defaultSegments:14,rendererScenarios:5,staticExpertCells:4,sourceDate:EXPERT_SOURCE.published,attributeLinks:7,staticGuideEntries:7,availabilityComparisons,requirementSubsets:128,completePlayerSeasons:complete,mobilityPlayerSeasons:mobility.length,finiteZeroAndNonfinite:'passed',fixedReferences:'unchanged',statsAvailabilityComparisons,statsMetrics:3,staticStatsCells:6,statsDefaultWhiskers:0,nativeBrowserChecks:'separate'},null,2));
