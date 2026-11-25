export function normalizeWorkName(value){
 return String(value).normalize('NFKC').toLocaleLowerCase('en-US').replace(/[\s\p{P}\p{S}]+/gu,'');
}
export function planWorkCatalog(existing,catalog){
 const lookup=new Map();for(const w of existing){const key=normalizeWorkName(w.name);if(!lookup.has(key))lookup.set(key,[]);lookup.get(key).push(w);}
 const plans=[];
 for(const item of catalog){
  const keys=[item.name,...item.aliases].map(normalizeWorkName);
  const matches=new Map(keys.flatMap(k=>lookup.get(k)??[]).map(w=>[String(w.id),w]));
  const exact=existing.find(w=>w.name===item.name);
  if(matches.size>1&&!exact){plans.push({item,action:'ambiguous',ids:[...matches.keys()]});continue;}
  plans.push({item,action:matches.size?'reuse':'insert',id:exact?.id??[...matches.values()][0]?.id,existingDuplicateIds:matches.size>1?[...matches.keys()]:[]});
 }
 return plans;
}
