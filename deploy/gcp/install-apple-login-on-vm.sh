#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
archive="${1:?Apple payload archive}"
key="${2:?Uploaded Apple private key}"
[[ $EUID == 0 && "$archive" =~ ^/tmp/coscircle-apple-[0-9]+\.tar\.gz$ && "$key" =~ ^/tmp/coscircle-apple-[0-9]+\.p8$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
current=/opt/coscircle/api/current
old="$(readlink -f "$current")"
[[ -L "$current" && "$old" == /opt/coscircle/api/releases/* ]]
stage="$(mktemp -d /tmp/coscircle-apple-stage-XXXXXXXX)"
backup="$(mktemp -d /var/backups/coscircle/apple-login-XXXXXXXX)"
release="$(mktemp -d /opt/coscircle/api/releases/apple-login-XXXXXXXX)"
environment=/etc/coscircle/api.env
destination=/etc/coscircle/apple-login.p8
cp -p "$environment" "$backup/api.env"
had_key=false
if [[ -f "$destination" ]]; then cp -p "$destination" "$backup/apple-login.p8";had_key=true;fi
changed=false
switched=false
recover() {
 result=$?
 if [[ "$result" != 0 ]]; then
  if [[ "$switched" == true ]]; then ln -s "$old" "${current}.apple-rollback";mv -Tf "${current}.apple-rollback" "$current";fi
  if [[ "$changed" == true ]]; then
   cp -p "$backup/api.env" "$environment"
   if [[ "$had_key" == true ]]; then cp -p "$backup/apple-login.p8" "$destination";else rm -f "$destination";fi
   systemctl restart coscircle-api
  fi
 fi
 rm -f "$key"
 rm -rf "$stage"
 exit "$result"
}
trap recover EXIT
tar -xzf "$archive" -C "$stage" --no-same-owner
python3 - "$old" "$stage/baseline-hashes.json" <<'PY'
import json,hashlib,sys
from pathlib import Path
for name,expected in json.loads(Path(sys.argv[2]).read_text()).items():
 assert hashlib.sha256((Path(sys.argv[1])/'src'/name).read_bytes()).hexdigest()==expected,'Production baseline changed: '+name
PY
node --input-type=module - "$key" <<'JS'
import fs from 'node:fs';import crypto from 'node:crypto';
const key=crypto.createPrivateKey(fs.readFileSync(process.argv[2]));
if(key.asymmetricKeyType!=='ec'||key.asymmetricKeyDetails.namedCurve!=='prime256v1')throw Error('Incorrect Apple key type');
JS
timeout 600 mysqldump --single-transaction --protocol=SOCKET --routines --triggers --events --hex-blob --no-tablespaces coscircle 2>"$backup/dump.stderr" | gzip >"$backup/coscircle.sql.gz"
gzip -t "$backup/coscircle.sql.gz"
cp -a "$old/." "$release/"
for file in server.js account-deletion.js apple-auth.js apple-auth.test.js account-deletion.test.js auth-identity-unlink.test.js;do install -m0644 "$stage/$file" "$release/src/$file";done
install -m0644 "$stage/migrate_apple_login.sql" "$release/db/migrate_apple_login.sql"
node --check "$release/src/server.js"
node --test "$release/src/apple-auth.test.js" "$release/src/account-deletion.test.js" "$release/src/auth-identity-unlink.test.js" >"$backup/tests.log" 2>&1
service_user="$(systemctl show coscircle-api -p User --value)";service_user="${service_user:-root}"
service_group="$(id -gn "$service_user")"
changed=true
install -m0640 -o root -g "$service_group" "$key" "$destination"
runuser -u "$service_user" -- test -r "$destination"
python3 - "$environment" <<'PY'
from pathlib import Path
import sys,base64,secrets
p=Path(sys.argv[1]);s=p.read_text();values={}
for line in s.splitlines():
 if '=' in line and not line.lstrip().startswith('#'):
  a,b=line.split('=',1);values[a]=b.strip().strip('"\'')
assert values.get('APPLE_LOGIN_ENABLED','false')!='true','Apple already configured; inspect before replacing'
assert not values.get('APPLE_TOKEN_ENCRYPTION_KEY'),'Existing encryption key requires inspection'
updates={'APPLE_LOGIN_ENABLED':'true','APPLE_CLIENT_ID':'com.hikakineame.coscircle','APPLE_TEAM_ID':'UF6P9B6PBV','APPLE_KEY_ID':'9TK5PUN53Q','APPLE_PRIVATE_KEY_PATH':'/etc/coscircle/apple-login.p8','APPLE_TOKEN_ENCRYPTION_KEY':base64.b64encode(secrets.token_bytes(32)).decode()}
lines=[line for line in s.splitlines() if line.split('=',1)[0] not in updates]
lines += [a+'='+b for a,b in updates.items()]
p.write_text('\n'.join(lines)+'\n');p.chmod(0o600)
PY
[[ "$(readlink -f "$current")" == "$old" ]]
ln -s "$release" "${current}.apple-next";mv -Tf "${current}.apple-next" "$current"
switched=true
systemctl restart coscircle-api
healthy=false
for attempt in {1..40};do
 if curl -fsS --max-time 3 http://127.0.0.1:8080/api/health >"$backup/health.json" 2>/dev/null;then healthy=true;break;fi
 sleep 1
done
[[ "$healthy" == true ]]
curl -fsS --max-time 15 --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/api/auth/apple/config >"$backup/apple-public-config.json"
node -e 'const fs=require("fs");if(JSON.parse(fs.readFileSync(process.argv[1])).enabled!==true)process.exit(1)' "$backup/apple-public-config.json"
printf 'Published Apple API: %s\nPrevious API retained: %s\nRestricted DB/config backup: %s\n' "$release" "$old" "$backup"
