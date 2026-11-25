import fs from 'node:fs';import assert from 'node:assert/strict';import {createRequire} from 'node:module';
const backup=process.argv[2];if(process.getuid()!==0||!/^\/var\/backups\/coscircle\/release-security-[A-Za-z0-9]+$/.test(backup||''))throw Error('Invalid backup');
const require=createRequire(process.cwd()+'/package.json'),env=require('dotenv').parse(fs.readFileSync('/etc/coscircle/api.env'));
const db=await require('mysql2/promise').createConnection({host:env.MYSQL_HOST||'127.0.0.1',user:env.MYSQL_USER,password:env.MYSQL_PASSWORD,database:env.MYSQL_DATABASE||'coscircle'});
try{
 const snapshot=JSON.parse(fs.readFileSync(backup+'/sessions-before.json'));let preserved=0,denied=0;
 for(const s of snapshot){if(!s.sessionToken||s.sessionToken.startsWith('sha256:'))continue;const [[u]]=await db.execute('SELECT is_admin,is_test_account,can_view_test_data FROM users WHERE id=?',[s.id]);if(!u)continue;
 const response=await fetch('http://127.0.0.1:8080/api/me',{headers:{Authorization:'Bearer '+s.sessionToken,'X-Forwarded-Proto':'https'}});
 const allowed=!u.is_test_account||u.can_view_test_data||u.is_admin;assert.equal(response.status,allowed?200:401);if(allowed)preserved++;else denied++;
 }
 const [[counts]]=await db.query("SELECT SUM(session_token IS NOT NULL AND session_token NOT LIKE 'sha256:%') rawSessions,SUM(is_test_account) fixtures,SUM(can_view_test_data) reviewers FROM users");assert.equal(Number(counts.rawSessions),0);assert.equal(Number(counts.reviewers),2);
 const [[temp]]=await db.query("SELECT COUNT(*) n FROM users WHERE provider_user_id LIKE 'release-security-%@example.invalid'");assert.equal(temp.n,0);
 const [[media]]=await db.query('SELECT file_name FROM account_uploads LIMIT 1');
 if(media){const r=await fetch('https://coscircle.app/uploads/'+encodeURIComponent(media.file_name));assert.equal(r.status,404);assert.match(r.headers.get('cache-control'),/no-store/);}
 const result={existingSessionsPreserved:preserved,nonReviewFixtureSessionsDenied:denied,rawDatabaseSessions:0,testUsers:Number(counts.fixtures),reviewAccessAccounts:2,disposableQaRemoved:true,publicUnsignedUploadDenied:true};fs.writeFileSync(backup+'/postcheck.json',JSON.stringify(result,null,2),{mode:0o600});console.log(JSON.stringify(result));
}finally{await db.end();}
