import fs from 'node:fs';import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const {normalizeWorkName,planWorkCatalog}=await import(pathToFileURL(process.cwd()+'/src/work-catalog.js'));
const require=createRequire(process.cwd()+'/package.json'),env=require('dotenv').parse(fs.readFileSync('/etc/coscircle/api.env'));
const [mode,backup]=process.argv.slice(2);if(!['--preview','--apply'].includes(mode))throw Error('Use --preview or --apply');
if(mode==='--apply'&&(process.getuid()!==0||!/^\/var\/backups\/coscircle\/social-feed-[A-Za-z0-9]+$/.test(backup??'')||!fs.existsSync(backup+'/coscircle.sql.gz')))throw Error('Full restricted DB backup required');
const mysql=require('mysql2/promise');const db=await mysql.createConnection({host:env.MYSQL_HOST||'127.0.0.1',user:env.MYSQL_USER,password:env.MYSQL_PASSWORD,database:env.MYSQL_DATABASE||'coscircle'});
try{
 const catalog=JSON.parse(fs.readFileSync(process.cwd()+'/data/cosplay-works.json')).works;
 const [existing]=await db.query('SELECT id,name FROM works WHERE is_test_work=FALSE');const plans=planWorkCatalog(existing,catalog);
 const report={catalog:catalog.length,insert:plans.filter(x=>x.action==='insert').length,reuse:plans.filter(x=>x.action==='reuse').length,ambiguous:plans.filter(x=>x.action==='ambiguous').map(x=>({name:x.item.name,ids:x.ids})),existingDuplicateGroups:plans.filter(x=>x.existingDuplicateIds?.length).map(x=>({name:x.item.name,ids:x.existingDuplicateIds})),aliasConflicts:[]};
 if(mode==='--apply'){
  const [[lock]]=await db.query("SELECT GET_LOCK('coscircle-work-catalog',10) locked");if(!lock.locked)throw Error('Catalog busy');
  try{await db.beginTransaction();
   for(const plan of plans){if(plan.action==='ambiguous')continue;let id=plan.id;
    if(!id){await db.execute('INSERT IGNORE INTO works(name,is_test_work)VALUES(?,FALSE)',[plan.item.name]);const [[w]]=await db.execute('SELECT id,is_test_work FROM works WHERE name=?',[plan.item.name]);if(w.is_test_work)throw Error('Fixture name conflict');id=w.id;}
    for(const alias of [plan.item.name,...plan.item.aliases]){const key=normalizeWorkName(alias);await db.execute('INSERT IGNORE INTO work_aliases(normalized_alias,alias_name,work_id)VALUES(?,?,?)',[key,alias,id]);const [[a]]=await db.execute('SELECT work_id FROM work_aliases WHERE normalized_alias=?',[key]);if(String(a.work_id)!==String(id))report.aliasConflicts.push(alias);}
   }await db.commit();}catch(e){await db.rollback();throw e;}finally{await db.query("SELECT RELEASE_LOCK('coscircle-work-catalog')");}
  fs.writeFileSync(backup+'/work-catalog-result.json',JSON.stringify(report,null,2),{mode:0o600});
 }
 console.log(JSON.stringify(report));
}finally{await db.end();}
