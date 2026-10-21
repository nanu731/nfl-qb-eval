// Published ranks for same-year annual-eligible quarterbacks. No unlisted rank is inferred.
export type ExpertTrait='arm_strength'|'field_vision'|'decision_making';
export type ExpertRank=Readonly<{playerKey:string;year:number;trait:ExpertTrait;category:string;rank:number;rankLabel:string;tied:boolean;marker:string}>;
export const EXPERT_SOURCES=Object.freeze({
  "2021": {
    "url": "https://www.espn.in/nfl/story/_/id/32050570/nfl-quarterback-council-2021-ranking-top-10-qbs-arm-strength-accuracy-decision-making-rushing-ability-more",
    "publisher": "ESPN",
    "published": "2021-08-23",
    "window": "2021 preseason",
    "byline": "NFL experts",
    "authorship": "Panel; individual and joint contributor slots",
    "shortAuthors": "Panel, joint contributor slots",
    "method": "Points combined from personal top-ten ballots; weights not specified."
  },
  "2022": {
    "url": "https://www.espn.in/nfl/story/_/id/34408660/nfl-quarterback-council-2022-ranking-top-10-qbs-arm-strength-accuracy-decision-making-rushing-ability-more",
    "publisher": "ESPN",
    "published": "2022-08-22",
    "window": "2022 preseason",
    "byline": "NFL Experts",
    "authorship": "Panel; individual and joint contributor slots",
    "shortAuthors": "Panel, joint contributor slots",
    "method": "Points combined from personal top-ten ballots; weights not specified."
  },
  "2023": {
    "url": "https://www.espn.in/nfl/story/_/id/38151402/nfl-quarterback-council-2023-ranking-top-10-traits",
    "publisher": "ESPN",
    "published": "2023-08-14",
    "window": "2023 preseason",
    "byline": "NFL experts",
    "authorship": "Nine named analysts",
    "shortAuthors": "Nine-analyst panel",
    "method": "Points combined from personal top-ten ballots; weights not specified."
  },
  "2024": {
    "url": "https://africa.espn.com/nfl/story/_/id/40674690/2024-ranking-best-nfl-quarterbacks-top-10-trait-skill-arm-accuracy-rushing",
    "publisher": "ESPN",
    "published": "2024-08-12",
    "window": "2024 preseason",
    "byline": "Dan Orlovsky",
    "authorship": "Individual judgment",
    "shortAuthors": "Dan Orlovsky (single author)",
    "method": "Current performance and upcoming-season expectations; article uses tape observations."
  },
  "2025": {
    "url": "https://www.espn.in/nfl/story/_/id/45913841/2025-ranking-best-nfl-quarterbacks-top-10-trait-skill-arm-accuracy-rushing",
    "publisher": "ESPN",
    "published": "2025-08-11",
    "window": "2025 preseason",
    "byline": "Dan Orlovsky",
    "authorship": "Individual judgment",
    "shortAuthors": "Dan Orlovsky (single author)",
    "method": "Current performance and upcoming-season expectations; tape-based; starters only."
  }
} as const);
export const EXPERT_SOURCE=EXPERT_SOURCES['2023'];
const verified=[
 {"playerKey":"00-0023459","year":2021,"trait":"arm_strength","category":"Arm strength","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2021,"trait":"arm_strength","category":"Arm strength","rank":4,"rankLabel":"4","tied":false,"marker":""},
 {"playerKey":"00-0029263","year":2021,"trait":"arm_strength","category":"Arm strength","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0029701","year":2021,"trait":"arm_strength","category":"Arm strength","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2021,"trait":"arm_strength","category":"Arm strength","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0034855","year":2021,"trait":"arm_strength","category":"Arm strength","rank":10,"rankLabel":"10","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2021,"trait":"arm_strength","category":"Arm strength","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0035228","year":2021,"trait":"arm_strength","category":"Arm strength","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2021,"trait":"arm_strength","category":"Arm strength","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0019596","year":2021,"trait":"field_vision","category":"Field vision","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0022924","year":2021,"trait":"field_vision","category":"Field vision","rank":10,"rankLabel":"10","tied":false,"marker":""},
 {"playerKey":"00-0023459","year":2021,"trait":"field_vision","category":"Field vision","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0026143","year":2021,"trait":"field_vision","category":"Field vision","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2021,"trait":"field_vision","category":"Field vision","rank":7,"rankLabel":"7","tied":false,"marker":""},
 {"playerKey":"00-0029263","year":2021,"trait":"field_vision","category":"Field vision","rank":4,"rankLabel":"T4","tied":true,"marker":""},
 {"playerKey":"00-0031280","year":2021,"trait":"field_vision","category":"Field vision","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0033077","year":2021,"trait":"field_vision","category":"Field vision","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2021,"trait":"field_vision","category":"Field vision","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0023459","year":2022,"trait":"arm_strength","category":"Arm strength","rank":4,"rankLabel":"4","tied":false,"marker":""},
 {"playerKey":"00-0029263","year":2022,"trait":"arm_strength","category":"Arm strength","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0031280","year":2022,"trait":"arm_strength","category":"Arm strength","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0033077","year":2022,"trait":"arm_strength","category":"Arm strength","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2022,"trait":"arm_strength","category":"Arm strength","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2022,"trait":"arm_strength","category":"Arm strength","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0035228","year":2022,"trait":"arm_strength","category":"Arm strength","rank":7,"rankLabel":"7","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2022,"trait":"arm_strength","category":"Arm strength","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0019596","year":2022,"trait":"field_vision","category":"Field vision","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0023459","year":2022,"trait":"field_vision","category":"Field vision","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0026143","year":2022,"trait":"field_vision","category":"Field vision","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0033077","year":2022,"trait":"field_vision","category":"Field vision","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2022,"trait":"field_vision","category":"Field vision","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2022,"trait":"field_vision","category":"Field vision","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2022,"trait":"field_vision","category":"Field vision","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0036442","year":2022,"trait":"field_vision","category":"Field vision","rank":4,"rankLabel":"4","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2023,"trait":"arm_strength","category":"Arm strength","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2023,"trait":"arm_strength","category":"Arm strength","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0034796","year":2023,"trait":"arm_strength","category":"Arm strength","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2023,"trait":"arm_strength","category":"Arm strength","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2023,"trait":"arm_strength","category":"Arm strength","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0036389","year":2023,"trait":"arm_strength","category":"Arm strength","rank":7,"rankLabel":"7","tied":false,"marker":""},
 {"playerKey":"00-0036971","year":2023,"trait":"arm_strength","category":"Arm strength","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2023,"trait":"field_vision","category":"Field vision","rank":10,"rankLabel":"10","tied":false,"marker":""},
 {"playerKey":"00-0033077","year":2023,"trait":"field_vision","category":"Field vision","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2023,"trait":"field_vision","category":"Field vision","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2023,"trait":"field_vision","category":"Field vision","rank":4,"rankLabel":"4","tied":false,"marker":""},
 {"playerKey":"00-0036212","year":2023,"trait":"field_vision","category":"Field vision","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2023,"trait":"field_vision","category":"Field vision","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0036389","year":2023,"trait":"field_vision","category":"Field vision","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0036442","year":2023,"trait":"field_vision","category":"Field vision","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0036971","year":2023,"trait":"field_vision","category":"Field vision","rank":7,"rankLabel":"7","tied":false,"marker":""},
 {"playerKey":"00-0023459","year":2024,"trait":"arm_strength","category":"Arm strength","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2024,"trait":"arm_strength","category":"Arm strength","rank":4,"rankLabel":"4","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2024,"trait":"arm_strength","category":"Arm strength","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0034796","year":2024,"trait":"arm_strength","category":"Arm strength","rank":10,"rankLabel":"10","tied":false,"marker":""},
 {"playerKey":"00-0034855","year":2024,"trait":"arm_strength","category":"Arm strength","rank":7,"rankLabel":"7","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2024,"trait":"arm_strength","category":"Arm strength","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2024,"trait":"arm_strength","category":"Arm strength","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0039152","year":2024,"trait":"arm_strength","category":"Arm strength","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0039164","year":2024,"trait":"arm_strength","category":"Arm strength","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0023459","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0029604","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":10,"rankLabel":"10","tied":false,"marker":""},
 {"playerKey":"00-0033106","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":7,"rankLabel":"7","tied":false,"marker":""},
 {"playerKey":"00-0036264","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0036442","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0037834","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0039163","year":2024,"trait":"decision_making","category":"Decision-making with the football","rank":4,"rankLabel":"4","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2025,"trait":"arm_strength","category":"Arm strength","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2025,"trait":"arm_strength","category":"Arm strength","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0034796","year":2025,"trait":"arm_strength","category":"Arm strength","rank":4,"rankLabel":"4","tied":false,"marker":""},
 {"playerKey":"00-0034855","year":2025,"trait":"arm_strength","category":"Arm strength","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2025,"trait":"arm_strength","category":"Arm strength","rank":1,"rankLabel":"1","tied":false,"marker":""},
 {"playerKey":"00-0036264","year":2025,"trait":"arm_strength","category":"Arm strength","rank":10,"rankLabel":"10","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2025,"trait":"arm_strength","category":"Arm strength","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0039918","year":2025,"trait":"arm_strength","category":"Arm strength","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0026498","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":6,"rankLabel":"6","tied":false,"marker":""},
 {"playerKey":"00-0033873","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":5,"rankLabel":"5","tied":false,"marker":""},
 {"playerKey":"00-0034796","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":3,"rankLabel":"3","tied":false,"marker":""},
 {"playerKey":"00-0034857","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":2,"rankLabel":"2","tied":false,"marker":""},
 {"playerKey":"00-0036212","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":8,"rankLabel":"8","tied":false,"marker":""},
 {"playerKey":"00-0036355","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":7,"rankLabel":"7","tied":false,"marker":""},
 {"playerKey":"00-0036389","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":9,"rankLabel":"9","tied":false,"marker":""},
 {"playerKey":"00-0039732","year":2025,"trait":"decision_making","category":"Decision-making with the football","rank":10,"rankLabel":"10","tied":false,"marker":""}
] as const;
const expected=new Map(verified.map(row=>[`${row.playerKey}:${row.year}:${row.trait}`,row]));
export function validateExpertRanks(input:unknown):readonly ExpertRank[]{
 if(!Array.isArray(input)||input.length!==84)throw Error('Expert source coverage mismatch');
 const seen=new Set<string>();
 const rows=input.map(row=>{
  if(!row||typeof row!=='object'||Object.keys(row).sort().join(',')!=='category,marker,playerKey,rank,rankLabel,tied,trait,year')throw Error('Invalid expert record');
  const key=`${row.playerKey}:${row.year}:${row.trait}`,fact=expected.get(key);
  if(!fact||seen.has(key)||Object.entries(fact).some(([field,value])=>row[field]!==value))throw Error('Unverified expert fact');
  seen.add(key);return Object.freeze({...row}) as ExpertRank;
 });
 return Object.freeze(rows);
}
export const EXPERT_RANKS=validateExpertRanks(verified);
export function expertFor(trait:ExpertTrait,year:number,id:string):ExpertRank|undefined{return EXPERT_RANKS.find(row=>row.trait===trait&&row.year===year&&row.playerKey===id);}
// Processing remains a different partial editorial category in the later editions.
export function processingFor(year:number,id:string):ExpertRank|undefined{return expertFor(year<=2023?'field_vision':'decision_making',year,id);}
export function expertSource(fact:ExpertRank){return EXPERT_SOURCES[String(fact.year) as keyof typeof EXPERT_SOURCES];}
export function mixedExpertSources(facts:readonly ExpertRank[]){
 const editions=new Set(facts.map(fact=>fact.year));
 const methods=new Set(facts.map(fact=>{const source=expertSource(fact);return `${source.byline}|${source.authorship}|${source.method}`;}));
 const processingCategories=new Set(facts.filter(fact=>fact.trait!=='arm_strength').map(fact=>fact.trait));
 return editions.size>1||methods.size>1||processingCategories.size>1;
}
export function expertLabel(fact:ExpertRank){return (fact.rankLabel.startsWith('T')?'':'#')+fact.rankLabel+fact.marker;}
// Ordinal drawing convention, never an NFL percentile or calibrated skill grade.
export function expertRadius(rank:number|null):number|null{return rank!==null&&Number.isFinite(rank)&&Number.isInteger(rank)&&rank>=1&&rank<=10?(11-rank)/10:null;}
