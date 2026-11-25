import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {normalizeWorkName,planWorkCatalog} from './work-catalog.js';
test('catalog aliases reuse existing IDs without overwriting relationships or creating alternate-spelling duplicates',()=>{
 const plans=planWorkCatalog([{id:10,name:'FGO'},{id:20,name:'原神'}],[{name:'Fate/Grand Order',aliases:['FGO']},{name:'原神',aliases:['Genshin Impact']}]);assert.deepEqual(plans.map(p=>[p.action,p.id]),[['reuse',10],['reuse',20]]);
 assert.equal(normalizeWorkName('Ｆａｔｅ／Ｇｒａｎｄ　Ｏｒｄｅｒ'),normalizeWorkName('Fate/Grand Order'));
});
test('ambiguous existing alternate names are flagged instead of silently merging users tags',()=>{
 const p=planWorkCatalog([{id:1,name:'FGO'},{id:2,name:'命運冠位指定'}],[{name:'Fate/Grand Order',aliases:['FGO','命運冠位指定']}]);assert.equal(p[0].action,'ambiguous');
});
test('bundled catalog has unique normalized canonical names and bounded aliases',()=>{const data=JSON.parse(fs.readFileSync(new URL('../data/cosplay-works.json',import.meta.url)));const names=data.works.map(w=>normalizeWorkName(w.name));assert.equal(new Set(names).size,names.length);assert(data.works.length>=100);for(const w of data.works)assert([w.name,...w.aliases].every(x=>x.length<=191));});
