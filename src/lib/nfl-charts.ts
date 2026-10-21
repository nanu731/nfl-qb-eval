import {DATA_URL,MANIFEST_URL,validatePair,METRICS,fmt,type Payload,type Row} from './nfl-comparison';
import {ANNUAL_URL,ANNUAL_MANIFEST_URL,DEPTH_URL,DEPTH_MANIFEST_URL,validateAnnualDepth,type AnnualPayload,type DepthPayload,type AnnualRow,type DepthRow} from './nfl-annual';
import {buildPercentileReferences,percentileFor,displayPercentile,type PercentileReferences} from './nfl-percentiles';
import {EXPERT_RANKS,validateExpertRanks,expertFor,processingFor,expertRadius,expertSource,expertLabel,mixedExpertSources,type ExpertTrait,type ExpertRank} from './nfl-experts';
import {MOBILITY_URL,MOBILITY_MANIFEST_URL,validateAnnualMobility,buildMobilityReferences,mobilityPercentileFor,type MobilityPayload,type MobilityRow,type MobilityReferences} from './nfl-mobility';
const NS='http://www.w3.org/2000/svg';
// Match the NBA explorer's accent-, punctuation- and whitespace-tolerant search.
const normalizeSearch=(value:string)=>value.normalize('NFD').replace(/\p{M}/gu,'').toLocaleLowerCase().replace(/[\p{P}\p{S}]+/gu,' ').replace(/\s+/g,' ').trim();
const compactSearch=(value:string)=>normalizeSearch(value).replace(/\s/g,'');
type PlayerChoice={id:string;name:string};
// Same filter and prefix-first order as SpatialShotSelection.updateSuggestions.
function matchingPlayers(players:PlayerChoice[],value:string){
 const query=normalizeSearch(value),compactQuery=compactSearch(value);
 return players.filter(player=>normalizeSearch(player.name).includes(query)||compactSearch(player.name).includes(compactQuery)).sort((a,b)=>{
  const aStarts=normalizeSearch(a.name).startsWith(query)||compactSearch(a.name).startsWith(compactQuery);
  const bStarts=normalizeSearch(b.name).startsWith(query)||compactSearch(b.name).startsWith(compactQuery);
  if(aStarts!==bStarts)return aStarts?-1:1;
  return a.name.localeCompare(b.name,undefined,{sensitivity:'base'})||a.id.localeCompare(b.id);
 });
}

function element(tag:string,attrs:Record<string,string|number>={},text?:string){const e=document.createElementNS(NS,tag);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,String(v));if(text!==undefined)e.textContent=text;return e;}
function cell(tag:string,text:string){const e=document.createElement(tag);e.textContent=text;if(tag==='th')e.setAttribute('scope','row');return e;}
type Axis={trait:string;title:string;label:string[];field?:string;bin?:string;target?:string;unit?:string;expert?:ExpertTrait|'processing';guide:string};
type Selected={side:'a'|'b';id:string;name:string;year:number;row?:AnnualRow;legacy?:Row;mobility?:MobilityRow;depth:DepthRow[]};
type Outcome={value:number|null;lower:number|null;upper:number|null;status:string;counts:string;reason:string};
const AXES:Axis[]=[
 {trait:'Arm strength',guide:'nfl-attribute-arm-strength',title:'Arm strength',label:['Arm strength','Expert rank'],expert:'arm_strength',target:'nfl-unmeasured-traits'},
 {trait:'Processing',guide:'nfl-attribute-processing',title:'Partial processing assessment',label:['Processing','Expert rank'],expert:'processing',target:'nfl-unmeasured-traits'},
 {trait:'Pocket presence',guide:'nfl-attribute-pocket-presence',title:'Dropbacks without a sack',label:['Dropbacks without','a sack','Pocket presence proxy'],field:'sack_avoidance_pct',target:'nfl-definition-sack-avoidance',unit:'%'},
 {trait:'Mobility',guide:'nfl-attribute-mobility',title:'Scramble contribution',label:['Scramble contribution','Mobility proxy','annual finite peers'],field:'annual_scramble_contribution',target:'nfl-definition-annual-mobility',unit:'expected points per included QB play'},
 {trait:'Short accuracy',guide:'nfl-attribute-short-accuracy',title:'Short completions above expectation',label:['Short completions','above expectation','Short accuracy proxy'],field:'short_cpoe_pp',bin:'short',target:'nfl-definition-depth',unit:'pp'},
 {trait:'Medium accuracy',guide:'nfl-attribute-medium-accuracy',title:'Medium completions above expectation',label:['Medium completions','above expectation','Medium accuracy proxy'],field:'medium_cpoe_pp',bin:'medium',target:'nfl-definition-depth',unit:'pp'},
 {trait:'Deep accuracy',guide:'nfl-attribute-deep-accuracy',title:'Deep completions above expectation',label:['Deep completions','above expectation','Deep accuracy proxy'],field:'deep_cpoe_pp',bin:'deep',target:'nfl-definition-depth',unit:'pp'},
];
export const STATS=[
 {field:'cpoe_pp',label:'CPOE',target:'nfl-definition-cpoe',unit:'percentage points',digits:1,meaning:'Completed passes compared with the model’s expected completions on the included throws. Positive values mean more completions than expected.'},
 {field:'epa_per_dropback',label:'EPA per recorded dropback',target:'nfl-definition-epa-dropback',unit:'expected points per recorded dropback',digits:2,meaning:'Average change in the offense’s expected scoring value on recorded passes, sacks and scrambles.'},
 {field:'sack_avoidance_pct',label:'Sack avoidance',target:'nfl-definition-sack-avoidance',unit:'percent',digits:1,meaning:'The share of recorded dropbacks that ended without a sack. Protection, receivers and quarterback decisions also affect it.'},
] as const;
export function formatStatValue(field:string,value:number|null){
 if(value===null||!Number.isFinite(value))return 'Unavailable';
 const metric=STATS.find(item=>item.field===field)!;
 return (field==='cpoe_pp'&&value>=0?'+':'')+value.toFixed(metric.digits);
}
export function readableStatTicks(min:number,max:number){
 const raw=(max-min)/4,magnitude=10**Math.floor(Math.log10(raw)),ratio=raw/magnitude;
 let step=(ratio<=1?1:ratio<=2?2:ratio<=5?5:10)*magnitude;
 const ticks=()=>Array.from({length:Math.max(0,Math.floor(max/step)-Math.ceil(min/step)+1)},(_,i)=>Number(((Math.ceil(min/step)+i)*step).toPrecision(12)));
 if(ticks().length<3)step/=2;
 return ticks();
}
export function registerNFL(){
 if(customElements.get('nfl-comparison'))return;
 class NFLComparison extends HTMLElement{
  annual?:AnnualPayload;depth?:DepthPayload;legacy?:Payload;mobility?:MobilityPayload;references?:PercentileReferences;mobilityReferences?:MobilityReferences;observer?:ResizeObserver;request=0;requiredMask=0;view:'profile'|'stats'='profile';statMetric:string='cpoe_pp';players:PlayerChoice[]=[];selectionNotice:Record<string,string>={a:"",b:""};suggestionState:Record<string,{matches:PlayerChoice[];active:number}>={a:{matches:[],active:-1},b:{matches:[],active:-1}};
  control(key:string){return this.querySelector<HTMLSelectElement>(`[data-${key}]`)!;}
  search(side:string){return this.querySelector<HTMLInputElement>(`[data-search-${side}]`)!;}
  label(s:Selected){return s.id?`${s.name} · ${s.year||"choose season"}`:`Choose quarterback${s.year?" · "+s.year:""}`;}
  playerSeason(side:'a'|'b',id:string,year:number):Selected{
   return {side,id,year,name:this.players.find(p=>p.id===id)?.name??'',row:this.annual!.rows.find(r=>r.player_key===id&&r.season===year),legacy:this.legacy!.rows.find(r=>r.player_key===id&&r.season===year),mobility:this.mobility?.rows.find(r=>r.player_key===id&&r.season===year),depth:this.depth!.rows.filter(r=>r.player_key===id&&r.season===year)};
  }
  selected(side:'a'|'b'):Selected{return this.playerSeason(side,this.control(side).value,Number(this.control(`season-${side}`).value));}
  missing(s:Selected){return !s.id||!s.year?(this.selectionNotice[s.side]||'Choose a quarterback and season to compare.') : s.year===2011?'2011 is excluded from this comparison.':'No eligible player-season record: this year requires at least 200 included throws in ten games.';}
  outcome(s:Selected,a:Axis):Outcome{
   const empty=(reason:string):Outcome=>({value:null,lower:null,upper:null,status:'unavailable',counts:'',reason});
   if(!a.field)return empty('Expert assessment uses its separately attributed rank.');
   if(!s.row)return empty(this.missing(s));
   if(a.bin){const d=s.depth.find(r=>r.bin===a.bin);if(!d)return empty('No audited depth record.');return {value:d.cpoe_pp,lower:d.lower,upper:d.upper,status:d.interval_status,counts:`${d.bin_throws} throws · ${d.positive_bin_games} games with bin throws / ${d.eligible_games} included-throw games`,reason:d.cpoe_pp===null?'No defined depth outcome.':''};}
   if(a.field==='annual_scramble_contribution'){const r=s.mobility;if(!r)return empty('No accepted annual scramble-contribution record.');if(r.scramble_contribution===null)return empty(r.unavailable_reason??'Recorded-role review pending.');return {value:r.scramble_contribution,lower:r.scramble_contribution_lower,upper:r.scramble_contribution_upper,status:r.scramble_interval_status,counts:`${r.scramble_runs} scrambles / ${r.combined_opportunities} included recorded QB plays · ${r.combined_games} games`,reason:''};}
   return {value:s.row.sack_avoidance_pct,lower:null,upper:null,status:'individual_range_not_estimated',counts:`${s.row.sacks} sacks / ${s.row.dropbacks} recorded dropbacks · ${s.row.dropback_games} games`,reason:''};
  }
  standing(s:Selected,a:Axis){
   const result=a.field==='annual_scramble_contribution'?mobilityPercentileFor(this.mobilityReferences!,s.year,s.id):percentileFor(this.references!,a.field??'',s.year,s.id);
   return Number.isFinite(this.outcome(s,a).value)?result:{...result,percentile:null};
  }
  referenceLabel(s:Selected,a:Axis){const p=this.standing(s,a);return `${s.year} · annual finite eligible peers · N=${p.n}`;}
  profilePoint(s:Selected,a:Axis):{radius:number|null;display:string;kind:string;rank:number|null;reason:string;fact?:ExpertRank}{
   if(a.expert){const fact=a.expert==='processing'?processingFor(s.year,s.id):expertFor(a.expert,s.year,s.id);return {radius:expertRadius(fact?.rank??null),display:fact?expertLabel(fact):'Unavailable',kind:'expert',rank:fact?.rank??null,fact,reason:fact?'':'No adopted expert assessment for this quarterback, category and preseason.'};}
   const p=this.standing(s,a);return {radius:p.percentile===null?null:p.percentile/100,display:displayPercentile(p.percentile),kind:'outcome',rank:null,reason:this.outcome(s,a).reason||p.reason};
  }
  appendExpertValue(target:HTMLElement,selected:Selected,axis:Axis,detail=false){
   const point=this.profilePoint(selected,axis),fact=point.fact;
   if(!fact){target.append(cell('strong','Unavailable'),cell('small',point.reason));return;}
   const source=expertSource(fact),link=document.createElement('a');link.className='expert-source';link.href=source.url;link.textContent=`${source.publisher} · ${source.published}`;
   target.dataset.rank=String(fact.rank);target.dataset.expertCategory=fact.trait;target.dataset.edition=String(fact.year);
   target.append(cell('strong',`${point.display} rank`));
   if(detail)target.append(cell('small',`${fact.category} · ${fact.year} preseason`),link,cell('small',source.shortAuthors),cell('small',`${source.byline}; ${source.authorship}. ${source.method} Ordinal drawing index, not a percentile or calibrated skill grade.`));
   else if(axis.expert==='processing')target.append(cell('small',fact.category));
  }
  statsAvailable(id:string,year:number){
   const row=this.annual?.rows.find(r=>r.player_key===id&&r.season===year);
   return !!row&&STATS.every(metric=>Number.isFinite(row[metric.field]));
  }
  selectionMatches(id:string,year:number){return this.view==='stats'?this.statsAvailable(id,year):!this.requiredMask||this.requirementsMatch(id,year);}
  setView(view:'profile'|'stats',navigate=false){
   if(navigate&&location.hash!==`#nfl-${view}-panel`)history.pushState({...history.state,nflAttributeOrigin:null},'',`#nfl-${view}-panel`);
   this.view=view;
   this.querySelectorAll<HTMLElement>('[data-view-panel]').forEach(panel=>panel.hidden=panel.dataset.viewPanel!==view);
   this.querySelectorAll<HTMLElement>('[data-view-intro]').forEach(intro=>intro.hidden=intro.dataset.viewIntro!==view);
   this.querySelectorAll<HTMLButtonElement>('[data-project-view]').forEach(tab=>{const active=tab.dataset.projectView===view;tab.setAttribute('aria-selected',String(active));tab.tabIndex=active?0:-1;});
   this.querySelector('[data-view-scope]')!.textContent=view==='profile'?'Attribute filters apply only to Attribute profile.':'Attribute filters are saved for Attribute profile. Stats comparison uses available season stats.';
   if(this.annual){this.selectionNotice={a:'',b:''};for(const side of ['a','b'])this.reconcileSelection(side);this.render();}
  }
  readonly handleViewHistory=()=>{
   const view=location.hash==='#nfl-stats-panel'?'stats':location.hash==='#nfl-profile-panel'?'profile':null;
   if(!view)return;
   if(this.view!==view)this.setView(view);
   if(!(history.state?.nflAttributeFragment===location.hash&&history.state?.nflAttributeOrigin))this.querySelector<HTMLButtonElement>(`[data-project-view="${view}"]`)!.focus({preventScroll:true});
  };
  loadExample(){
   for(const [side,id]of [['a','00-0033873'],['b','00-0034857']]){this.control(side).value=id;this.updateSeasons(side,'2023');this.selectionNotice[side]='';this.refreshSearchSeason(side);}
   this.render();
  }
  readonly handleOutsidePointer=(event:PointerEvent)=>{
   for(const side of ['a','b'])if(event.target instanceof Node&&!this.querySelector(`[data-combobox-${side}]`)!.contains(event.target))this.closeSuggestions(side);
  };
  // Preserve native fragment navigation; Back also returns keyboard focus to its chart link.
  readonly handleAttributeClick=(event:MouseEvent)=>{
   if(event.button!==0||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
   const link=event.target instanceof Element?event.target.closest('.radar-attribute-link'):null;
   if(!link||!this.contains(link))return;
   history.replaceState({...history.state,nflAttributeOrigin:link.id,nflAttributeFragment:location.hash},'');
  };
  readonly handleAttributeBack=()=>{
   const state=history.state;
   if(state?.nflAttributeFragment===location.hash&&typeof state?.nflAttributeOrigin==='string')this.frameAttributeReturn(state.nflAttributeOrigin);
  };
  frameAttributeReturn(id:string){
   if(this.view!=='profile')this.setView('profile');
   // Resolve after any view-triggered redraw, rather than retaining a detached SVG node.
   requestAnimationFrame(()=>{
    const link=document.getElementById(id);
    if(link instanceof SVGElement&&this.contains(link)){link.focus({preventScroll:true});this.querySelector('[data-radar-legend]')!.scrollIntoView({block:'start',behavior:'instant'});}
    else{this.querySelector<HTMLButtonElement>('[data-project-view="profile"]')!.focus({preventScroll:true});this.querySelector('#nfl-radar-heading')!.scrollIntoView({block:'start',behavior:'instant'});}
   });
  }
  readonly handleAttributeReturn=()=>{
   if(history.state?.nflAttributeFragment===location.hash&&history.state?.nflAttributeOrigin){this.handleAttributeBack();return;}
   const id=location.hash.slice(1);if(id.startsWith('nfl-radar-link-'))this.frameAttributeReturn(id);
  };
  // Availability is the same finite radius used by the renderer, including zero.
  requirementsMatch(id:string,year:number,mask=this.requiredMask){
   const selected=this.playerSeason('a',id,year);
   return AXES.every((axis,i)=>!(mask&(1<<i))||Number.isFinite(this.profilePoint(selected,axis).radius));
  }
  seasonChoices(side:string){
   const id=this.control(side).value;
   return [...this.annual!.season_catalog].sort((a,b)=>b.season-a.season).filter(y=>this.view!=='stats'&&!this.requiredMask||this.annual!.rows.some(r=>r.season===y.season&&(!id||r.player_key===id)&&this.selectionMatches(r.player_key,r.season)));
  }
  updateSeasons(side:string,current=this.control(`season-${side}`).value){
   const select=this.control(`season-${side}`),choices=this.seasonChoices(side);
   select.replaceChildren(...choices.map(y=>{const option=document.createElement('option');option.value=String(y.season);option.textContent=String(y.season)+(y.status==='source_blocked'?' · excluded':'');return option;}));
   const available=!!current&&choices.some(y=>String(y.season)===current);
   if(this.view==='stats'||!available){
    const placeholder=document.createElement('option');placeholder.value='';placeholder.textContent=choices.length?'Choose season':'No matching seasons';select.prepend(placeholder);select.value=available?current:'';
   }else select.value=current;
  }
  reconcileSelection(side:string){
   const id=this.control(side).value,year=Number(this.control(`season-${side}`).value);
   if(id&&!(year?this.selectionMatches(id,year):this.annual!.rows.some(r=>r.player_key===id&&this.selectionMatches(id,r.season)))){
    this.control(side).value='';this.selectionNotice[side]=this.view==='stats'?'Selection cleared: this quarterback and season has no available season-stat record. Choose an eligible player and year.':'Selection cleared: choose a quarterback and season with every checked attribute available.';
   }
   this.updateSeasons(side);this.refreshSearchSeason(side);
  }
  changeRequirements(clear=false){
   const boxes=[...this.querySelectorAll<HTMLInputElement>('[data-require-attribute]')];
   if(clear)boxes.forEach(box=>box.checked=false);
   this.requiredMask=boxes.reduce((mask,box)=>mask|(box.checked?1<<Number(box.dataset.requireAttribute):0),0);
   if(!this.requiredMask)this.selectionNotice={a:'',b:''};
   for(const side of ['a','b'])this.reconcileSelection(side);
   this.render();
  }
  seasonPlayers(side:string){
   const year=Number(this.control(`season-${side}`).value);
   const ids=new Set(this.annual?.rows.filter(r=>(!year||r.season===year)&&(this.view!=='stats'&&!this.requiredMask||this.selectionMatches(r.player_key,r.season))).map(r=>r.player_key));
   return this.players.filter(p=>ids.has(p.id));
  }
  refreshSearchSeason(side:string){
   this.closeSuggestions(side);this.search(side).value=this.selectedName(side);
   const year=this.control(`season-${side}`).value;this.search(side).placeholder=year?`Search players in ${year}`:'Search eligible quarterbacks';this.suggestions(side).setAttribute('aria-label',year?`Players in ${year}`:'Players with an eligible season');
   this.searchStatus(side,(this.selectedName(side)?`${this.selectedName(side)}, ${year||'choose a season'}.`:(this.selectionNotice[side]||`Choose a quarterback${year?' in '+year:' and season'}.`))+(!year&&this.view==='stats'?' Search across eligible seasons, then choose one season to show its stats.':''));
  }
  suggestions(side:string){return this.querySelector<HTMLElement>(`[data-suggestions-${side}]`)!;}
  searchStatus(side:string,text:string){this.querySelector(`[data-search-status-${side}]`)!.textContent=text;}
  selectedName(side:string){return this.players.find(p=>p.id===this.control(side).value)?.name??'';}
  closeSuggestions(side:string){
   this.suggestions(side).hidden=true;this.search(side).setAttribute('aria-expanded','false');this.search(side).removeAttribute('aria-activedescendant');
   this.suggestionState[side]={matches:[],active:-1};
  }
  showSuggestions(side:string,all=false){
   if(this.search(side).disabled)return;
   const players=this.seasonPlayers(side);
   this.closeSuggestions(side==='a'?'b':'a');
   const matches=all?[...players]:matchingPlayers(players,this.search(side).value);
   this.suggestionState[side]={matches,active:-1};this.search(side).removeAttribute('aria-activedescendant');this.renderSuggestions(side);this.suggestions(side).hidden=false;this.search(side).setAttribute('aria-expanded','true');
   const year=this.control(`season-${side}`).value||(this.view==='stats'?'eligible seasons; choose one season to display stats':'eligible seasons');
   this.searchStatus(side,all?`${players.length} players in ${year}. Type to narrow the list.`:`${matches.length} ${matches.length===1?'player matches':'players match'} in ${year}.`);
  }
  renderSuggestions(side:string){
   const {matches,active}=this.suggestionState[side];
   if(!matches.length){const empty=document.createElement('p');empty.className='no-results';empty.setAttribute('role','option');empty.setAttribute('aria-disabled','true');empty.setAttribute('aria-selected','false');const year=this.control(`season-${side}`).value;empty.textContent=this.view==='stats'?(year?`No players match in ${year}. Change the season, or choose “Choose season” to search across years.`:'No players match this search across eligible seasons. Try another name or choose a season to show its stats.'):'No players found. Try another name or season.';this.suggestions(side).replaceChildren(empty);return;}
   this.suggestions(side).replaceChildren(...matches.map((p,i)=>{
    const option=document.createElement('div');option.id=`nfl-option-${side}-${p.id}`;option.className='suggestion-option';option.setAttribute('role','option');option.setAttribute('aria-selected',String(i===active));option.textContent=p.name;
    option.addEventListener('mousedown',e=>e.preventDefault());option.addEventListener('click',()=>this.choosePlayer(side,p));return option;
   }));
  }
  choosePlayer(side:string,p:PlayerChoice){
   if((this.view==='stats'||this.requiredMask)&&!this.seasonPlayers(side).some(choice=>choice.id===p.id))return;
   this.control(side).value=p.id;this.selectionNotice[side]='';this.updateSeasons(side);this.refreshSearchSeason(side);this.render();
  }
  searchKeydown(side:string,e:KeyboardEvent){
   if(e.isComposing)return;
   if(e.key==='Escape'||e.key==='Tab'){if(e.key==='Escape'&&!this.suggestions(side).hidden)e.preventDefault();this.closeSuggestions(side);return;}
   if(e.key==='ArrowDown'||e.key==='ArrowUp'){
    e.preventDefault();if(this.suggestions(side).hidden)this.showSuggestions(side,true);
    const state=this.suggestionState[side];if(!state.matches.length)return;
    const step=e.key==='ArrowDown'?1:-1;state.active=state.active===-1?(step===1?0:state.matches.length-1):(state.active+step+state.matches.length)%state.matches.length;
    this.renderSuggestions(side);const option=this.suggestions(side).children[state.active] as HTMLElement;this.search(side).setAttribute('aria-activedescendant',option.id);option.scrollIntoView({block:'nearest'});return;
   }
   if(e.key==='Enter'){
    const state=this.suggestionState[side];if(!this.suggestions(side).hidden&&state.active>=0){e.preventDefault();this.choosePlayer(side,state.matches[state.active]);}
   }
  }
  openChart(view:'profile'|'stats'){
   if(this.dataset.state!=='ready')return;
   const dialog=this.querySelector<HTMLDialogElement>('[data-chart-lightbox]')!;
   if(dialog.open)return;
   const source=this.querySelector<HTMLElement>(`[data-expandable-chart="${view}"]`)!,svg=source.querySelector('svg[data-radar],svg[data-stat-plot]');
   if(!svg||svg.hasAttribute('hidden'))return;
   // Copy the current vector drawing, keeping the selections and plotted values exact.
   const snapshot=source.cloneNode(true) as HTMLElement;
   snapshot.querySelector('[data-expand-chart]')?.remove();
   const ids=new Map<string,string>();
   for(const node of [snapshot,...snapshot.querySelectorAll<HTMLElement|SVGElement>('*')]){
    if(node.id){ids.set(node.id,`nfl-enlarged-${node.id}`);node.id=`nfl-enlarged-${node.id}`;}
    for(const attr of [...node.attributes])if((attr.name.startsWith('data-')&&!attr.name.startsWith('data-astro-'))||attr.name==='tabindex')node.removeAttribute(attr.name);
   }
   snapshot.querySelectorAll('[aria-labelledby],[aria-describedby]').forEach(node=>{for(const attr of ['aria-labelledby','aria-describedby'])if(node.hasAttribute(attr))node.setAttribute(attr,node.getAttribute(attr)!.split(' ').map(id=>ids.get(id)??id).join(' '));});
   // The enlarged chart is a static image; definition links remain on the original.
   snapshot.querySelectorAll('svg a').forEach(link=>{const group=document.createElementNS('http://www.w3.org/2000/svg','g');group.append(...link.childNodes);link.replaceWith(group);});
   snapshot.querySelector('svg:not([aria-hidden])')?.setAttribute('role','img');
   const metric=STATS.find(item=>item.field===this.statMetric)!;
   this.querySelector('[data-chart-lightbox-title]')!.textContent=view==='profile'?'Attribute profile':metric.label;
   const unit=this.querySelector<HTMLElement>('[data-chart-lightbox-unit]')!;unit.hidden=view==='profile';unit.textContent=view==='stats'?metric.unit:'';
   const content=this.querySelector<HTMLElement>('[data-enlarged-content]')!;content.replaceChildren(snapshot);
   this.querySelector<HTMLButtonElement>(`[data-expand-chart="${view}"]`)!.focus({preventScroll:true});
   dialog.showModal();content.scrollLeft=Math.max(0,(content.scrollWidth-content.clientWidth)/2);
  }
  connectedCallback(){
   if(this.dataset.initialized)return;this.dataset.initialized='true';this.players=[...this.control('a').options].filter(o=>o.value).map(o=>({id:o.value,name:o.textContent!}));
   for(const side of ['a','b']){
    this.search(side).addEventListener('input',()=>this.showSuggestions(side));
    this.search(side).addEventListener('focus',()=>this.showSuggestions(side,true));
    this.search(side).addEventListener('keydown',e=>this.searchKeydown(side,e));
    const shell=this.querySelector<HTMLElement>(`[data-combobox-${side}]`)!;
    shell.addEventListener('focusout',e=>{if(!(e.relatedTarget instanceof Node)||!shell.contains(e.relatedTarget))this.closeSuggestions(side);});
   }
   const dialog=this.querySelector<HTMLDialogElement>('[data-chart-lightbox]')!;
   this.querySelectorAll<HTMLElement>('[data-expandable-chart]').forEach(figure=>figure.addEventListener('click',event=>{
    const target=event.target as Element;if(target.closest('a'))return;
    if(target.closest('[data-expand-chart],svg[data-radar],svg[data-stat-plot]'))this.openChart(figure.dataset.expandableChart as 'profile'|'stats');
   }));
   this.querySelector('[data-chart-close]')!.addEventListener('click',()=>dialog.close());
   dialog.addEventListener('click',event=>{if(event.target!==dialog)return;const box=dialog.getBoundingClientRect();if(event.clientX<box.left||event.clientX>box.right||event.clientY<box.top||event.clientY>box.bottom)dialog.close();});
   dialog.addEventListener('close',()=>this.querySelector('[data-enlarged-content]')!.replaceChildren());
   const tabs=[...this.querySelectorAll<HTMLButtonElement>('[data-project-view]')];
   tabs.forEach((tab,index)=>{
    tab.addEventListener('click',()=>this.setView(tab.dataset.projectView as 'profile'|'stats',true));
    tab.addEventListener('keydown',event=>{let next=index;if(event.key==='ArrowRight')next=(index+1)%tabs.length;else if(event.key==='ArrowLeft')next=(index+tabs.length-1)%tabs.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=tabs.length-1;else return;event.preventDefault();tabs[next].focus();this.setView(tabs[next].dataset.projectView as 'profile'|'stats',true);});
   });
   this.querySelector<HTMLElement>('[data-project-views]')!.hidden=false;this.setView(location.hash==='#nfl-stats-panel'?'stats':'profile');
   this.querySelectorAll<HTMLInputElement>('[data-stat-metric]').forEach(input=>input.addEventListener('change',()=>{this.statMetric=input.value;this.render();}));
   document.addEventListener('pointerdown',this.handleOutsidePointer);this.addEventListener('click',this.handleAttributeClick);window.addEventListener('popstate',this.handleAttributeBack);window.addEventListener('hashchange',this.handleAttributeReturn);window.addEventListener('popstate',this.handleViewHistory);window.addEventListener('hashchange',this.handleViewHistory);
   for(const side of ['a','b'])this.control(`season-${side}`).addEventListener('change',()=>{this.selectionNotice[side]='';this.reconcileSelection(side);this.render();});
   this.querySelector('[data-retry]')!.addEventListener('click',()=>this.load());
   this.querySelector('[data-complete-example]')!.addEventListener('click',()=>this.loadExample());
   this.querySelectorAll('[data-require-attribute]').forEach(box=>box.addEventListener('change',()=>this.changeRequirements()));
   this.querySelector('[data-clear-requirements]')!.addEventListener('click',()=>this.changeRequirements(true));
   this.querySelectorAll('[data-sack-section],[data-comparison-evidence]').forEach(e=>e.addEventListener('toggle',()=>{if(this.annual)this.render(false);}));
   this.observer=new ResizeObserver(()=>{if(this.annual)this.render(false);});this.querySelectorAll('[data-chart-host]').forEach(e=>this.observer!.observe(e));this.load();
  }
  disconnectedCallback(){this.observer?.disconnect();document.removeEventListener('pointerdown',this.handleOutsidePointer);this.removeEventListener('click',this.handleAttributeClick);window.removeEventListener('popstate',this.handleAttributeBack);window.removeEventListener('hashchange',this.handleAttributeReturn);window.removeEventListener('popstate',this.handleViewHistory);window.removeEventListener('hashchange',this.handleViewHistory);this.querySelector<HTMLDialogElement>('[data-chart-lightbox]')?.close();this.request++;}
  clear(){
   const dialog=this.querySelector<HTMLDialogElement>('[data-chart-lightbox]');if(dialog?.open)dialog.close();
   this.querySelectorAll('svg[data-field],svg[data-radar],svg[data-stat-plot]').forEach(s=>{s.replaceChildren();s.setAttribute('hidden','');});
   this.querySelectorAll('[data-selected-values],[data-radar-values],[data-selected-depth]').forEach(e=>e.replaceChildren());
   this.querySelectorAll<HTMLElement>('[data-profile-values] td').forEach(td=>{td.textContent='Unavailable';td.className='unavailable';td.removeAttribute('data-rank');td.removeAttribute('data-percentile');});
   this.querySelectorAll('[data-counts],[data-pair-legend],[data-expert-summary],[data-radar-counts],[data-radar-gaps],[data-availability-a],[data-availability-b]').forEach(e=>e.textContent='');
   this.querySelectorAll<HTMLElement>('[data-stat-value],[data-stat-counts],[data-stat-range],[data-stat-player]').forEach(e=>{e.textContent='Unavailable';e.removeAttribute('data-value');});
   this.querySelectorAll('[data-radar-legend-name]').forEach(e=>e.textContent='Unavailable');
   const methodNote=this.querySelector<HTMLElement>('[data-expert-method-note]')!;methodNote.textContent='';methodNote.hidden=true;
   this.querySelector('[data-radar-a]')!.textContent='Quarterback A';this.querySelector('[data-radar-b]')!.textContent='Quarterback B';
   for(const side of ['a','b'])this.closeSuggestions(side);
   this.querySelectorAll<HTMLSelectElement|HTMLInputElement|HTMLButtonElement>('select,input[type=search],[data-complete-example],[data-require-attribute],[data-clear-requirements],[data-stat-metric],[data-expand-chart]').forEach(e=>e.disabled=true);
  }
  async load(){
   const restore=this.querySelector('[data-retry]')===document.activeElement,token=++this.request;
   this.annual=undefined;this.depth=undefined;this.legacy=undefined;this.mobility=undefined;this.references=undefined;this.mobilityReferences=undefined;this.clear();this.dataset.state='loading';this.querySelector<HTMLButtonElement>('[data-retry]')!.hidden=true;this.querySelector('[data-comparison-status]')!.textContent='Checking comparison data…';
   try{
    const responses=await Promise.all([ANNUAL_URL,ANNUAL_MANIFEST_URL,DEPTH_URL,DEPTH_MANIFEST_URL,DATA_URL,MANIFEST_URL,MOBILITY_URL,MOBILITY_MANIFEST_URL].map(url=>fetch(url,{cache:'no-store',headers:{Accept:'application/json'}})));
    if(responses.some(r=>!r.ok))throw Error('Data unavailable');const bytes=await Promise.all(responses.map(async r=>new Uint8Array(await r.arrayBuffer())));
    const [{annual,depth},legacy]=await Promise.all([validateAnnualDepth(bytes[0],bytes[1],bytes[2],bytes[3]),validatePair(bytes[4],bytes[5])]);const mobility=await validateAnnualMobility(bytes[6],bytes[7],annual,legacy);validateExpertRanks(EXPERT_RANKS);const [references,mobilityReferences]=await Promise.all([buildPercentileReferences(annual,depth,legacy),buildMobilityReferences(mobility)]);await document.fonts.ready;
    if(token!==this.request||!this.isConnected)return;this.annual=annual;this.depth=depth;this.legacy=legacy;this.mobility=mobility;this.references=references;this.mobilityReferences=mobilityReferences;this.dataset.state='ready';
    this.querySelectorAll<HTMLSelectElement|HTMLInputElement|HTMLButtonElement>('select,input[type=search],[data-complete-example],[data-require-attribute],[data-clear-requirements],[data-stat-metric],[data-expand-chart]').forEach(e=>e.disabled=false);for(const side of ['a','b'])this.reconcileSelection(side);this.render();if(restore)this.search('a').focus();
   }catch{if(token!==this.request)return;this.clear();this.dataset.state='error';this.querySelector('[data-comparison-status]')!.textContent='The comparison data could not be verified. Retry, or open Data and research details below for tables and downloads.';this.querySelector<HTMLButtonElement>('[data-retry]')!.hidden=false;}
  }
  render(announce=true){
   if(!this.annual||!this.depth||!this.legacy)return;
   const active=document.activeElement,focusedLink=active instanceof SVGElement&&active.matches('.radar-attribute-link')&&this.contains(active)?active.id:null;
   const pair=[this.selected('a'),this.selected('b')];
   pair.forEach(s=>{this.querySelector(`[data-availability-${s.side}]`)!.textContent=s.row?'':`${s.side.toUpperCase()} · ${this.label(s)}: ${this.missing(s)}${s.id&&s.year?' The selection is retained.':''}`;});
   this.drawRadar(pair);this.renderEvidence(pair);
   this.querySelectorAll<SVGSVGElement>('svg[data-field]').forEach(svg=>{const main=svg.closest<HTMLDetailsElement>('[data-comparison-evidence]'),sack=svg.closest<HTMLDetailsElement>('[data-sack-section]');if(!main?.open||(sack&&!sack.open)){svg.replaceChildren();svg.setAttribute('hidden','');return;}const width=Math.round(svg.parentElement!.getBoundingClientRect().width);if(width>0)this.draw(svg,pair,svg.dataset.field!,width);});
   for(const field of ['epa_per_dropback','cpoe_pp','sack_avoidance_pct']){
    const body=this.querySelector(`[data-evidence="${field}"] [data-selected-values]`)!;body.replaceChildren();
    pair.forEach(s=>{const tr=document.createElement('tr');tr.append(cell('th',`${s.side.toUpperCase()} · ${this.label(s)}`));const r=s.row;if(!r){tr.append(cell('td','Unavailable'),cell('td',this.missing(s)));if(field==='epa_per_dropback')tr.append(cell('td','Unavailable'));}else{tr.append(cell('td',fmt(r[field])),cell('td',field==='cpoe_pp'?`${r.eligible_throws} throws in ${r.eligible_games} games`:`${r.dropbacks} dropbacks in ${r.dropback_games} games${field==='sack_avoidance_pct'?`; ${r.sacks} sacks`:''}`));if(field==='epa_per_dropback')tr.append(cell('td',`${fmt(r.epa_lower)} to ${fmt(r.epa_upper)}; ${r.epa_interval_status.replaceAll('_',' ')}`));}body.append(tr);});
   }
   for(const [tag,field]of [['epa','dropbacks'],['cpoe','eligible_throws']])this.querySelector(`[data-counts="${tag}"]`)!.textContent=pair.map(s=>`${s.side.toUpperCase()} · ${this.label(s)}: ${s.row?`${s.row[field]} ${tag==='epa'?'dropbacks':'included throws'}`:'Unavailable'}`).join(' · ');
   this.querySelector('[data-pair-legend]')!.textContent=`Filled circle: A, ${this.label(pair[0])}. Open diamond: B, ${this.label(pair[1])}.`;
   this.renderStats(pair);
   // SVG replacement must not discard the reader's current chart-link focus.
   if(focusedLink&&this.view==='profile'&&(document.activeElement===document.body||document.activeElement===active)){
    const replacement=document.getElementById(focusedLink);if(replacement instanceof SVGElement&&this.contains(replacement))replacement.focus({preventScroll:true});
   }
   if(announce)this.querySelector('[data-comparison-status]')!.textContent=pair.map(s=>`${s.side.toUpperCase()} · ${this.label(s)}${s.row?'':' · unavailable'}`).join(' versus ');
  }
  renderStats(pair:Selected[]){
   const metric=STATS.find(item=>item.field===this.statMetric)!;
   this.querySelector('[data-stat-meaning]')!.textContent=metric.meaning;
   this.querySelector('[data-stat-unit]')!.textContent=metric.unit;
   pair.forEach(selected=>{
    const card=this.querySelector(`[data-stat-side="${selected.side}"]`)!,row=selected.row,value=card.querySelector<HTMLElement>('[data-stat-value]')!;
    card.querySelector('[data-stat-player]')!.textContent=`${selected.side.toUpperCase()} · ${this.label(selected)}`;
    card.querySelector('[data-stat-label]')!.textContent=metric.label;card.querySelector('[data-stat-label]')!.setAttribute('href','#'+metric.target);
    card.querySelector('[data-stat-units]')!.textContent=metric.unit;
    value.removeAttribute('data-value');value.textContent=row?formatStatValue(metric.field,row[metric.field]):'Unavailable';
    if(row)value.dataset.value=String(row[metric.field]);
    card.querySelector('[data-stat-counts]')!.textContent=!row?this.missing(selected):metric.field==='cpoe_pp'?`${row.eligible_throws} included throws across ${row.eligible_games} games`:`${row.dropbacks} recorded dropbacks across ${row.dropback_games} games${metric.field==='sack_avoidance_pct'?`; ${row.sacks} sacks`:''}`;
    const range=this.querySelector(`[data-stat-range="${selected.side}"]`)!;
    range.textContent=`${selected.side.toUpperCase()} · ${this.label(selected)}: `+(!row?'Unavailable':metric.field==='epa_per_dropback'?(row.epa_lower!==null?`${fmt(row.epa_lower)} to ${fmt(row.epa_upper)} expected points per recorded dropback; ${row.epa_interval_status.replaceAll('_',' ')}`:row.epa_interval_status.replaceAll('_',' ')):'Individual ranges were not estimated for this statistic.');
   });
   const svg=this.querySelector<SVGSVGElement>('[data-stat-plot]')!;
   if(this.view!=='stats'){svg.replaceChildren();svg.setAttribute('hidden','');return;}
   const width=Math.round(svg.parentElement!.getBoundingClientRect().width);if(width>0)this.draw(svg,pair,metric.field,width,false);
  }
  drawRadar(pair:Selected[]){
   const svg=this.querySelector<SVGSVGElement>('[data-radar]')!,width=Math.round(svg.parentElement!.getBoundingClientRect().width);if(width<=0)return;
   const small=width<440,cx=width/2,cy=small?190:240,R=small?Math.min(94,(width-155)/2):Math.min(155,(width-190)/2),height=small?380:455;
   svg.replaceChildren();svg.removeAttribute('hidden');svg.setAttribute('viewBox',`0 0 ${width} ${height}`);
   const point=(i:number,r:number)=>{const angle=-Math.PI/2+i*2*Math.PI/7;return {x:cx+Math.cos(angle)*r,y:cy+Math.sin(angle)*r,angle};};
   const radius=(fraction:number)=>fraction*R;
   const line=(a:{x:number;y:number},b:{x:number;y:number},attrs:Record<string,string|number>)=>svg.append(element('line',{x1:a.x,y1:a.y,x2:b.x,y2:b.y,...attrs}));
   svg.append(element('title',{id:'nfl-radar-title'},`Quarterback attribute profile: ${pair.map(s=>`${s.side.toUpperCase()} · ${this.label(s)}`).join(' versus ')}`));
   svg.append(element('desc',{id:'nfl-radar-description'},'Two expert assessments and five season outcomes use different drawing scales. Expert rank 1 is outer and rank 10 is inner; the ordinal index is not an NFL percentile or skill grade. Higher outcome percentiles are farther out. Only verified player-year ranks appear; no carry-forward. '+pair.map(s=>`${s.side.toUpperCase()} · ${this.label(s)}: `+AXES.map(a=>{const p=this.profilePoint(s,a);return `${a.title}: ${p.radius===null?p.reason:p.display+(p.fact?` expert rank; ${p.fact.category}; ${p.fact.year} preseason; ${expertSource(p.fact).shortAuthors}; ${expertSource(p.fact).published}`:' percentile; '+this.referenceLabel(s,a))}`;}).join('; ')).join('. ')+'. Adjacent available positions connect. The final edge appears only when all seven positions are available. No fill or overall score.'));
   for(const f of [.25,.5,.75,1])svg.append(element('circle',{cx,cy,r:R*f,class:'radar-ring'}));
   const positions=[{x:cx,y:small?34:30,anchor:'middle'},{x:width*.8,y:small?95:92,anchor:'middle'},
    {x:width-8,y:small?300:360,anchor:'end'},{x:width*.73,y:small?348:425,anchor:'middle'},
    {x:width*.23,y:small?348:425,anchor:'middle'},{x:8,y:small?300:360,anchor:'start'},{x:width*.2,y:small?95:92,anchor:'middle'}];
   AXES.forEach((a,i)=>{
    line({x:cx,y:cy},point(i,R),{class:`radar-spoke${a.expert?' expert-spoke':''}`,'data-position':i,'data-trait':a.trait});
    const pos=positions[i],linkId='nfl-radar-link-'+a.guide.replace('nfl-attribute-','');
    const link=element('a',{id:linkId,href:'#'+a.guide,class:'radar-attribute-link',role:'link','data-axis-label':i,'data-trait':a.trait,'data-reference-target':'',tabindex:0});
    const label=element('text',{x:pos.x,y:pos.y,'text-anchor':pos.anchor,class:'radar-label'},a.trait);
    link.append(label);svg.append(link);
    const fallbackWidth=a.trait.length*8,anchor=pos.anchor==='middle'?fallbackWidth/2:pos.anchor==='end'?fallbackWidth:0;
    const box=typeof label.getBBox==='function'?label.getBBox():{x:pos.x-anchor,y:pos.y-14,width:fallbackWidth,height:18};
    const hit=element('rect',{x:box.x-6,y:box.y-6,width:box.width+12,height:Math.max(28,box.height+12),fill:'transparent','aria-hidden':'true'});
    link.append(hit);
   });
   pair.forEach(s=>{const points=AXES.map(a=>this.profilePoint(s,a)),series=`series-${s.side}`;
    for(let i=0;i<AXES.length-1;i++){const a=points[i].radius,b=points[i+1].radius;if(a!==null&&b!==null)line(point(i,radius(a)),point(i+1,radius(b)),{class:`radar-segment ${series}`,'data-side':s.side,'data-from':i,'data-to':i+1});}
    if(points.every(p=>p.radius!==null))line(point(6,radius(points[6].radius!)),point(0,radius(points[0].radius!)),{class:`radar-segment ${series}`,'data-side':s.side,'data-from':6,'data-to':0});
    AXES.forEach((a,i)=>{const value=points[i];if(value.radius===null)return;const p=point(i,radius(value.radius));
     const mark=s.side==='b'?element('path',{d:`M ${p.x} ${p.y-5.5} l 5.5 5.5 l -5.5 5.5 l -5.5 -5.5 Z`,class:`mark-b radar-mark${a.expert?' expert-mark':''}`}):element('circle',{cx:p.x,cy:p.y,r:4.5,class:`mark-a radar-mark${a.expert?' expert-mark':''}`});
     const attrs:Record<string,string|number>={'data-side':s.side,'data-position':i,'data-field':a.field??a.expert!,'data-kind':value.kind,'data-radius':radius(value.radius),'data-radius-max':R,'data-year':s.year};
     if(value.fact){attrs['data-rank']=value.rank!;attrs['data-source']=expertSource(value.fact).url;attrs['data-expert-category']=value.fact.trait;attrs['data-edition']=value.fact.year;attrs['data-rank-label']=value.fact.rankLabel;attrs['data-tied']=String(value.fact.tied);attrs['data-marker']=value.fact.marker;attrs['data-field']=value.fact.trait;}else{const rank=this.standing(s,a);Object.assign(attrs,{'data-value':this.outcome(s,a).value!,'data-percentile':rank.percentile!,'data-n':rank.n,'data-key-hash':rank.keyHash!,'data-cohort':rank.cohort});}
     for(const[k,v]of Object.entries(attrs))mark.setAttribute(k,String(v));mark.append(element('title',{},`${s.side.toUpperCase()} · ${this.label(s)} · ${a.title}: ${value.display}${value.fact?` expert rank · ${value.fact.category} · ${value.fact.year} preseason · ${expertSource(value.fact).shortAuthors} · ${expertSource(value.fact).published}`:` percentile; ${this.referenceLabel(s,a)}`}`));svg.append(mark);
    });
   });
   svg.dataset.scale='mixed-expert-rank-and-outcome-percentile';svg.dataset.formulaVersion='HA-1.0 / OP-1.0';
  }
  renderEvidence(pair:Selected[]){
   const body=this.querySelector('[data-radar-values]')!;body.replaceChildren();
   AXES.forEach((a,i)=>{const tr=document.createElement('tr'),th=cell('th',''),title=document.createElement(a.target?'a':'strong');tr.dataset.position=String(i);tr.dataset.trait=a.trait;title.textContent=a.title;if(a.target)title.setAttribute('href','#'+a.target);th.append(title);if(a.field){const mapping=document.createElement('small');mapping.textContent=`Desired trait: ${a.trait.toLowerCase()}, not directly measured. Shown: ${a.bin?'depth residual':'recorded outcome'} proxy.`;th.append(mapping);}tr.append(th);
    if(a.expert){pair.forEach(s=>{const td=cell('td','');td.dataset.player=`${s.side.toUpperCase()} · ${this.label(s)}`;this.appendExpertValue(td,s,a,true);tr.append(td);});body.append(tr);return;}
    pair.forEach(s=>{const td=cell('td',''),o=this.outcome(s,a),p=this.standing(s,a);td.dataset.player=`${s.side.toUpperCase()} · ${this.label(s)}`;const value=document.createElement('strong');value.textContent=o.value===null?o.reason:`Recorded value: ${fmt(o.value,a.field==='sack_avoidance_pct'?1:3)} ${a.unit}`;td.append(value);if(o.value!==null){td.dataset.value=String(o.value);const count=document.createElement('small'),range=document.createElement('small'),rank=document.createElement('small');count.textContent=o.counts;range.textContent=o.lower!==null?`Raw range: ${fmt(o.lower)} to ${fmt(o.upper)} ${a.unit}; ${o.status.replaceAll('_',' ')}. Not a percentile interval.`:`Raw range: ${o.status.replaceAll('_',' ')}`;rank.textContent=`${displayPercentile(p.percentile)} percentile · ${this.referenceLabel(s,a)} · OP-1.0`;td.append(count,range,rank);}tr.append(td);});body.append(tr);
   });
   AXES.forEach((axis,i)=>pair.forEach(selected=>{
    const td=this.querySelector<HTMLElement>(`[data-profile-values] tr[data-attribute-index="${i}"] [data-side="${selected.side}"]`)!,point=this.profilePoint(selected,axis);
    td.replaceChildren();td.className='';td.removeAttribute('data-rank');td.removeAttribute('data-percentile');td.removeAttribute('data-expert-category');td.removeAttribute('data-edition');
    if(point.radius===null){td.textContent='Unavailable';td.className='unavailable';if(axis.field==='annual_scramble_contribution'&&selected.mobility?.point_status==='blocked_pending_role_review')td.append(cell('small','Recorded-role review pending.'));}
    else if(axis.expert)this.appendExpertValue(td,selected,axis);
    else{const p=this.standing(selected,axis);td.dataset.percentile=String(p.percentile);td.append(cell('strong',point.display),cell('small','percentile'));}
   }));
   this.querySelector('[data-profile-a]')!.textContent='A';this.querySelector('[data-profile-b]')!.textContent='B';
   const incomplete=pair.some(s=>AXES.some(a=>this.profilePoint(s,a).radius===null)),gaps=this.querySelector<HTMLElement>('[data-radar-gaps]')!;
   gaps.hidden=!incomplete;gaps.textContent=incomplete?'Unavailable attributes are left blank.':'';
   this.querySelector<HTMLButtonElement>('[data-complete-example]')!.hidden=!incomplete;
   this.querySelector('[data-profile-window]')!.textContent='Expert ranks describe their listed preseason. Stats describe each selected regular season.';
   const opinions=pair.flatMap(s=>[expertFor('arm_strength',s.year,s.id),processingFor(s.year,s.id)]).filter((fact):fact is ExpertRank=>!!fact),mixed=mixedExpertSources(opinions);
   const notice=this.querySelector<HTMLElement>('[data-expert-method-note]')!;notice.hidden=!mixed;notice.textContent=mixed?'These expert lists use different editions or methods. Rank changes do not measure improvement.':'';
   const summary=this.querySelector('[data-expert-summary]')!;summary.replaceChildren();
   const sources=new Map<number,{fact:ExpertRank;sides:string[]}>();
   for(const selected of pair)for(const fact of [expertFor('arm_strength',selected.year,selected.id),processingFor(selected.year,selected.id)])if(fact){const entry=sources.get(fact.year)??{fact,sides:[]};if(!entry.sides.includes(selected.side))entry.sides.push(selected.side);sources.set(fact.year,entry);}
   if(sources.size){summary.append('Expert rankings: ');let i=0;for(const {fact,sides}of sources.values()){if(i++)summary.append(' · ');const source=expertSource(fact),link=document.createElement('a');link.href=source.url;link.textContent=`${sides.length===2?'':sides.join('/').toUpperCase()+' · '}${fact.year} preseason · ${source.shortAuthors} · ${source.published}`;summary.append(link);}}
   this.querySelector('[data-radar-a]')!.textContent=`A · ${this.label(pair[0])}`;this.querySelector('[data-radar-b]')!.textContent=`B · ${this.label(pair[1])}`;pair.forEach(s=>{this.querySelector(`[data-radar-legend-name="${s.side}"]`)!.textContent=`${s.side.toUpperCase()} · ${this.label(s)}`;});this.querySelector('[data-radar-counts]')!.textContent='All five outcomes use their own fixed same-year finite annual-eligible peers. The one blocked Mobility point is excluded from its percentile pool. Raw ranges are not percentile intervals.';
   const selected=this.querySelector('[data-selected-depth]')!;selected.replaceChildren();pair.forEach(s=>{if(!s.row){const tr=document.createElement('tr');tr.append(cell('th',`${s.side.toUpperCase()} · ${this.label(s)}`),cell('td','Unavailable'),cell('td',this.missing(s)),cell('td','Unavailable'));selected.append(tr);return;}s.depth.forEach(r=>{const tr=document.createElement('tr');tr.dataset.side=s.side;tr.dataset.bin=r.bin;tr.append(cell('th',`${s.side.toUpperCase()} · ${this.label(s)} · ${r.bin} [${r.air_yards_lower}, ${r.air_yards_upper})`),cell('td',fmt(r.cpoe_pp)),cell('td',`${r.bin_throws} throws; ${r.positive_bin_games} positive-bin games / ${r.eligible_games} all E games`),cell('td',`${fmt(r.lower)} to ${fmt(r.upper)} pp; ${r.interval_status.replaceAll('_',' ')}`));selected.append(tr);});});
  }
  draw(svg:SVGSVGElement,pair:Selected[],field:string,width:number,showRanges=true){
   const displayValue=(value:number)=>showRanges?fmt(value):formatStatValue(field,value);
   const domain=this.annual!.domains[field],metric=METRICS[field],L=18,R=width-18,axisY=150,x=(v:number)=>L+(v-domain.min!)/(domain.max!-domain.min!)*(R-L);
   svg.replaceChildren();svg.removeAttribute('hidden');svg.setAttribute('viewBox',`0 0 ${width} 186`);const id=svg.id;
   svg.append(element('title',{id:id+'-title'},`${field==='epa_per_dropback'?'Value per dropback':field==='cpoe_pp'?'Completions above expectation':'Dropbacks without a sack'}: ${pair.map(s=>this.label(s)).join(' versus ')}`));svg.append(element('desc',{id:id+'-description'},pair.map(s=>`${s.side.toUpperCase()} · ${this.label(s)}: ${s.row?displayValue(s.row[field])+' '+metric.unitLabel:this.missing(s)}`).join('; ')+'. Available points are shown independently; no difference statistic is calculated.'));
   const line=(x1:number,y1:number,x2:number,y2:number,cls:string)=>svg.append(element('line',{x1,y1,x2,y2,class:cls}));const text=(px:number,py:number,t:string,anchor='start',cls='')=>svg.append(element('text',{x:px,y:py,'text-anchor':anchor,class:cls},t));const hasZero=domain.min!<=0&&domain.max!>=0;if(hasZero)line(x(0),35,x(0),138,'zero');
   pair.forEach((s,i)=>{const nameY=20+i*67,py=48+i*67; text(L,nameY,`${s.side.toUpperCase()} · ${this.label(s)}`);if(!s.row){text(L,py,'Unavailable','start','value');return;}const r=s.row,v=Number(r[field]);text(R,py,displayValue(v),'end','value');if(showRanges&&metric.lower&&typeof r[metric.lower]==='number'&&typeof r[metric.upper!]==='number'){const lo=x(Number(r[metric.lower])),hi=x(Number(r[metric.upper!]));line(lo,py,hi,py,`interval series-${s.side}`);line(lo,py-5,lo,py+5,`interval series-${s.side}`);line(hi,py-5,hi,py+5,`interval series-${s.side}`);}const px=x(v),mark=i?element('path',{d:`M ${px} ${py-6} l 6 6 l -6 6 l -6 -6 Z`,class:'mark-b'}):element('circle',{cx:px,cy:py,r:6,class:'mark-a'});mark.dataset.side=s.side;mark.dataset.value=String(v);mark.append(element('title',{},`${s.side.toUpperCase()} · ${this.label(s)}: ${displayValue(v)}`));svg.append(mark);});
   line(L,axisY,R,axisY,'axis');const span=domain.max!-domain.min!;let ticks=[domain.min!,domain.min!+span/2,domain.max!];if(hasZero){ticks=ticks.filter(v=>v===domain.min||v===domain.max||Math.abs(v)/span>.17);if(!ticks.includes(0))ticks.push(0);}if(!showRanges)ticks=readableStatTicks(domain.min!,domain.max!);for(const v of ticks){line(x(v),axisY,x(v),axisY+5,'axis');text(x(v),axisY+25,fmt(v,2),v===domain.min?'start':v===domain.max?'end':'middle','tick');}svg.dataset.domain=`${domain.min},${domain.max}`;
  }
 }
 customElements.define('nfl-comparison',NFLComparison);
}
