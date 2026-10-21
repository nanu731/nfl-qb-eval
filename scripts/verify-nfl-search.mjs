// Source-level parity checks. Real DOM, pointer and keyboard checks are separate.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {runInNewContext} from 'node:vm';
import {resolve} from 'node:path';
const nba=readFileSync(resolve(process.env.NFL_PORTFOLIO_ROOT??'.','src/components/SpatialShotSelection.astro'),'utf8');
const nfl=readFileSync('src/lib/nfl-charts.ts','utf8');
const source=readFileSync('src/components/NFLComparison.astro','utf8');
const annual=JSON.parse(readFileSync('public/data/nfl-qb-annual-2006-2025-v1.json'));
const nbaNormalization=nba.slice(nba.indexOf('const normalizeSearch ='),nba.indexOf('class SpatialShotExplorer'));
const nbaUpdate=nba.slice(nba.indexOf('private updateSuggestions() {'),nba.indexOf('private showAllSuggestions()')).replace('private updateSuggestions()','function updateSuggestions()');
const reference=runInNewContext(stripTypeScriptTypes(`${nbaNormalization}\n${nbaUpdate}\nupdateSuggestions`));
const candidate=runInNewContext(stripTypeScriptTypes(nfl.slice(nfl.indexOf('const normalizeSearch='),nfl.indexOf('function element(')))+'\nmatchingPlayers');
let comparisons=0;
for(const year of annual.season_catalog.map(s=>s.season)){
 const players=annual.rows.filter(r=>r.season===year).map(r=>({id:r.player_key,name:r.display_name}));
 for(const query of ['', 'jo', 'JO', 'allen', 'máhomes', 'cjstroud', 'C. J.', 'roethlisberger', '  jO  ', 'zzzxq', '!!!']){
  const ctx={players:players.map(p=>({player_id:p.id,player_name:p.name})),search:{value:query},selectedSeason:String(year),renderSuggestions(){},openSuggestions(){},setStatus(){},seasonLabel(s){return s;}};
  reference.call(ctx);
  assert.deepEqual(Array.from(candidate(players,query),p=>p.id),Array.from(ctx.matches,p=>p.player_id),`${year}: ${JSON.stringify(query)}`);
  comparisons++;
 }
}
function method(name,next,globals={}){
 const text=nfl.slice(nfl.indexOf(`  ${name}(`),nfl.indexOf(`  ${next}(`));
 return runInNewContext(stripTypeScriptTypes('({'+text+'})'),globals)[name];
}
const close=method('closeSuggestions','showSuggestions');
const field={value:'Unfinished query',attrs:{'aria-expanded':'true','aria-activedescendant':'old'},setAttribute(k,v){this.attrs[k]=v;},removeAttribute(k){delete this.attrs[k];}};
const menu={hidden:false};const state={a:{matches:[1],active:0}};
close.call({suggestions:()=>menu,search:()=>field,suggestionState:state},'a');
assert.equal(menu.hidden,true);assert.equal(field.value,'Unfinished query');assert.equal(field.attrs['aria-expanded'],'false');assert.equal(field.attrs['aria-activedescendant'],undefined);assert.equal(state.a.active,-1);
let renders=0,closed=false;const selected={value:'old'},input={value:'query'},season={value:'2024'};
method('choosePlayer','searchKeydown').call({control:k=>k==='a'?selected:season,selectionNotice:{a:''},updateSeasons(){},refreshSearchSeason(){input.value='Ben Roethlisberger';closed=true;},render(){renders++;}},'a',{id:'new',name:'Ben Roethlisberger'});
assert.equal(selected.value,'new');assert.equal(input.value,'Ben Roethlisberger');assert.equal(closed,true);assert.equal(renders,1);
const subset=method('seasonPlayers','refreshSearchSeason').call({annual,control:()=>({value:'2024'}),players:[...new Map(annual.rows.map(r=>[r.player_key,{id:r.player_key,name:r.display_name}])).values()]},'a');
assert.equal(subset.length,annual.rows.filter(r=>r.season===2024).length);
assert.ok(!subset.some(p=>p.name==='Tom Brady'));
assert.match(nfl,/addEventListener\('focus',\(\)=>this.showSuggestions\(side,true\)\)/);
assert.match(nfl,/document.addEventListener\('pointerdown',this.handleOutsidePointer\)/);
assert.match(nfl,/No players found\. Try another name or season\./);
assert.equal((source.match(/Open the list or type a name\. Accents and punctuation are optional\./g)||[]).length,0);
for(const side of ['a','b'])assert.ok(source.includes(`<label class="visually-hidden" for="nfl-search-${side}">Quarterback ${side.toUpperCase()}</label>`),'Search retains an accessible label without repeated visible instructions');
assert.match(source,/padding:var\(--space-2xs\) var\(--space-s\)/);
assert.match(source,/--control-height:3rem/);
const menuFeedback={};const feedback=method('renderSuggestions','choosePlayer',{document:{createElement(){return {attrs:{},setAttribute(k,v){this.attrs[k]=v;}};}}});
for(const [year,view]of [['2023','stats'],['','stats'],['2023','profile']]){
 feedback.call({suggestionState:{a:{matches:[],active:-1}},view,control:()=>({value:year}),suggestions:()=>({replaceChildren(node){menuFeedback[view+year]=node;}})},'a');
}
assert.match(menuFeedback.stats2023.textContent,/2023/);assert.match(menuFeedback.stats2023.textContent,/Choose season/);assert.match(menuFeedback.stats2023.textContent,/across years/);
assert.match(menuFeedback.stats.textContent,/across eligible seasons/);assert.match(menuFeedback.stats.textContent,/another name/);assert.equal(menuFeedback.stats2023.attrs['aria-disabled'],'true');
console.log(JSON.stringify({sourceChecks:'passed',nbaFilterComparisons:comparisons,noResultsFeedbackCases:3,seasons:annual.season_catalog.length,additional:'close preserves text, selection retains name, season scoping, focus/outside-pointer wiring and UI contract',browserChecks:'not performed by this script'}));
