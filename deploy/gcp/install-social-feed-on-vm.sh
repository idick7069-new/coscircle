#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $EUID == 0 && "$1" =~ ^/tmp/coscircle-social-feed-[0-9]+\.tar\.gz$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock;flock -n 9
old="$(readlink -f /opt/coscircle/api/current)"
[[ "$(sha256sum "$old/src/server.js" | cut -d' ' -f1)" == 229cb8bc2130a982d16e41ad0497cd1cc16500c85d52b4cff3764dca47ae8be2 ]]
backup="$(mktemp -d /var/backups/coscircle/social-feed-XXXXXXXX)"
release="$(mktemp -d /opt/coscircle/api/releases/social-feed-XXXXXXXX)"
printf '%s' "$old" > "$backup/previous-api"
printf '%s' "$release" > "$backup/release"
cp -p /etc/coscircle/api.env "$backup/api.env"
timeout 600 mysqldump --single-transaction --protocol=SOCKET --routines --triggers --events --hex-blob --no-tablespaces coscircle 2>"$backup/dump.stderr" | gzip > "$backup/coscircle.sql.gz"
gzip -t "$backup/coscircle.sql.gz"
cp -a "$old/." "$release/"
tar -xzf "$1" -C "$release" --no-same-owner
cd "$release"
node --check src/server.js
node --test src/*.test.js > "$backup/unit-tests.log" 2>&1
mysql coscircle < db/migrate_social_feed.sql
mysql coscircle < db/migrate_work_aliases.sql
node deploy/gcp/seed-work-catalog.mjs --preview > "$backup/work-catalog-preview.json"
node deploy/gcp/seed-work-catalog.mjs --apply "$backup" > "$backup/work-catalog-import.log"
node deploy/gcp/social-feed-qa.mjs prepare "$backup"
node --input-type=module - "$backup" "$release" <<'JS'
import fs from 'node:fs';import {spawn,execFileSync} from 'node:child_process';import {createRequire} from 'node:module';
const [backup,release]=process.argv.slice(2),require=createRequire(release+'/package.json');const env=require('dotenv').parse(fs.readFileSync('/etc/coscircle/api.env'));
const log=fs.openSync(backup+'/candidate.log','a',0o600);
const child=spawn(process.execPath,['src/server.js'],{cwd:release,uid:Number(execFileSync('id',['-u','coscircle'],{encoding:'utf8'})),gid:Number(execFileSync('id',['-g','coscircle'],{encoding:'utf8'})),env:{...process.env,...env,PORT:'18081',LISTEN_HOST:'127.0.0.1',BACKGROUND_JOBS_ENABLED:'false',EVENT_SCRAPER_ENABLED:'false'},stdio:['ignore',log,log],detached:true});fs.writeFileSync(backup+'/candidate.pid',String(child.pid));child.unref();
JS
switched=false
recover(){
 result=$?
 if [[ $result != 0 && "$switched" == true ]];then ln -s "$old" /opt/coscircle/api/current.feed-rollback;mv -Tf /opt/coscircle/api/current.feed-rollback /opt/coscircle/api/current;systemctl restart coscircle-api;fi
 if [[ -f "$backup/candidate.pid" ]];then kill "$(cat "$backup/candidate.pid")" 2>/dev/null || true;fi
 if [[ -f "$backup/qa-state.json" ]];then node deploy/gcp/social-feed-qa.mjs cleanup "$backup" > "$backup/cleanup.log" 2>&1 || true;fi
 printf 'Restricted backup: %s\nCandidate release: %s\n' "$backup" "$release"
 exit "$result"
}
trap recover EXIT
healthy=false
for n in {1..40};do if curl -fsS --max-time 3 http://127.0.0.1:18081/api/health >/dev/null 2>&1;then healthy=true;break;fi;sleep 1;done
[[ "$healthy" == true ]]
node deploy/gcp/social-feed-qa.mjs verify "$backup" > "$backup/candidate-qa.log" 2>&1
[[ "$(readlink -f /opt/coscircle/api/current)" == "$old" ]]
ln -s "$release" /opt/coscircle/api/current.feed-next;mv -Tf /opt/coscircle/api/current.feed-next /opt/coscircle/api/current
switched=true
systemctl restart coscircle-api
healthy=false
for n in {1..40};do if curl -fsS --max-time 3 http://127.0.0.1:8080/api/health > "$backup/health.json" 2>/dev/null;then healthy=true;break;fi;sleep 1;done
[[ "$healthy" == true ]]
node deploy/gcp/social-feed-qa.mjs verify "$backup" http://127.0.0.1:8080 > "$backup/production-qa.log" 2>&1
curl -fsS --max-time 15 --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/api/health > "$backup/https-health.json"
printf 'Published verified feed API: %s\nWork catalog: ' "$release"
cat "$backup/work-catalog-import.log"
