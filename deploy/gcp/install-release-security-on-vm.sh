#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $EUID == 0 ]]
action="${1:?stage or activate}"
archive="${2:?archive or backup path}"
if [[ "$action" == stage ]];then
 [[ "$archive" =~ ^/tmp/coscircle-release-security-[0-9]+\.tar\.gz$ ]]
 exec 9>/run/lock/coscircle-api-deploy.lock;flock -n 9
 current=/opt/coscircle/api/current
 old="$(readlink -f "$current")"
 [[ "$(sha256sum "$old/src/server.js" | cut -d' ' -f1)" == 35e2f29f97927fbcfa36dcded191905d7d3182804d88c9cc46acff63d0c6fa3e ]]
 backup="$(mktemp -d /var/backups/coscircle/release-security-XXXXXXXX)"
 release="$(mktemp -d /opt/coscircle/api/releases/release-security-XXXXXXXX)"
 printf '%s' "$old" > "$backup/previous-api"
 cp -p /etc/coscircle/api.env "$backup/api.env"
 timeout 600 mysqldump --single-transaction --protocol=SOCKET --routines --triggers --events --hex-blob --no-tablespaces coscircle 2>"$backup/dump.stderr" | gzip > "$backup/coscircle.sql.gz"
 gzip -t "$backup/coscircle.sql.gz"
 cp -a "$old/." "$release/"
 tar -xzf "$archive" -C "$release" --no-same-owner
 printf '%s' "$release" > "$backup/release"
 cd "$release"
 node --check src/server.js
 node --test src/*.test.js > "$backup/tests.log" 2>&1
 python3 - <<'PY'
from pathlib import Path
import secrets,base64
p=Path('/etc/coscircle/api.env');s=p.read_text()
if not any(l.startswith('MEDIA_SIGNING_KEY=') and l.split('=',1)[1].strip() for l in s.splitlines()):
 p.write_text(s.rstrip()+'\nMEDIA_SIGNING_KEY='+base64.b64encode(secrets.token_bytes(32)).decode()+'\n');p.chmod(0o600)
PY
 node deploy/gcp/release-security-migrate.mjs prepare "$backup"
 node deploy/gcp/release-security-qa.mjs prepare "$backup"
 # The loopback-only candidate has no scheduled jobs and no public listener.
 node --input-type=module - "$backup" "$release" <<'JS'
import fs from 'node:fs';import {spawn} from 'node:child_process';import {createRequire} from 'node:module';import {execFileSync} from 'node:child_process';
const [backup,release]=process.argv.slice(2);const require=createRequire(release+'/package.json');const parsed=require('dotenv').parse(fs.readFileSync('/etc/coscircle/api.env'));
const log=fs.openSync(backup+'/candidate.log','a',0o600);
const uid=Number(execFileSync('id',['-u','coscircle'],{encoding:'utf8'}).trim()),gid=Number(execFileSync('id',['-g','coscircle'],{encoding:'utf8'}).trim());
const child=spawn(process.execPath,['src/server.js'],{cwd:release,uid,gid,env:{...process.env,...parsed,PORT:'18080',LISTEN_HOST:'127.0.0.1',BACKGROUND_JOBS_ENABLED:'false',EVENT_SCRAPER_ENABLED:'false'},stdio:['ignore',log,log],detached:true});
fs.writeFileSync(backup+'/candidate.pid',String(child.pid));child.unref();
JS
 healthy=false
 for n in {1..40};do if curl -fsS --max-time 3 http://127.0.0.1:18080/api/health > "$backup/candidate-health.json" 2>/dev/null;then healthy=true;break;fi;sleep 1;done
 [[ "$healthy" == true ]]
 node deploy/gcp/release-security-qa.mjs verify "$backup" > "$backup/candidate-qa.log" 2>&1
 printf 'Candidate verified. Backup: %s\nRelease: %s\n' "$backup" "$release"
elif [[ "$action" == activate ]];then
 backup="$archive";[[ "$backup" =~ ^/var/backups/coscircle/release-security-[A-Za-z0-9]+$ ]]
 exec 9>/run/lock/coscircle-api-deploy.lock;flock -n 9
 release="$(cat "$backup/release")";old="$(cat "$backup/previous-api")"
 [[ "$(readlink -f /opt/coscircle/api/current)" == "$old" && -f "$backup/qa-results.json" ]]
 cd "$release"
 for f in /etc/nginx/sites-enabled/coscircle /etc/nginx/coscircle-extra/coscircle.app.conf;do cp -pL "$f" "$backup/$(basename "$(dirname "$f")")-$(basename "$f")";done
 switched=false
 recover(){
  result=$?
  if [[ $result != 0 && "$switched" == true ]];then
   ln -s "$old" /opt/coscircle/api/current.rollback;mv -Tf /opt/coscircle/api/current.rollback /opt/coscircle/api/current
   node deploy/gcp/release-security-migrate.mjs rollback-sessions "$backup"
   cp -p "$backup/sites-enabled-coscircle" "$(readlink -f /etc/nginx/sites-enabled/coscircle)"
   cp -p "$backup/coscircle-extra-coscircle.app.conf" /etc/nginx/coscircle-extra/coscircle.app.conf
   systemctl restart coscircle-api;nginx -t && systemctl reload nginx
  fi
  exit "$result"
 }
 trap recover EXIT
 switched=true
 node deploy/gcp/release-security-migrate.mjs activate "$backup"
 ln -s "$release" /opt/coscircle/api/current.next;mv -Tf /opt/coscircle/api/current.next /opt/coscircle/api/current
 python3 - <<'PY'
from pathlib import Path
import re
count=0
for name in ['/etc/nginx/sites-enabled/coscircle','/etc/nginx/coscircle-extra/coscircle.app.conf']:
 p=Path(name).resolve();s=p.read_text()
 s,n=re.subn(r'location \^~ /uploads/ \{[^}]*\}', '''location ^~ /uploads/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    add_header Cache-Control "no-store" always;
  }''',s)
 count+=n;p.write_text(s)
assert count==3, f'Unexpected uploads route count: {count}'
PY
 nginx -t
 systemctl restart coscircle-api
 healthy=false
 for n in {1..40};do if curl -fsS --max-time 3 http://127.0.0.1:8080/api/health > "$backup/production-health.json" 2>/dev/null;then healthy=true;break;fi;sleep 1;done
 [[ "$healthy" == true ]]
 systemctl reload nginx
 node deploy/gcp/release-security-qa.mjs verify "$backup" http://127.0.0.1:8080 > "$backup/production-qa.log" 2>&1
 curl -fsS --max-time 15 --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/api/health > "$backup/https-health.json"
 kill "$(cat "$backup/candidate.pid")" || true
 node deploy/gcp/release-security-qa.mjs cleanup "$backup"
 printf 'Published verified API: %s\nBackup: %s\n' "$release" "$backup"
else exit 2;fi
