#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
credential="${1:?Pass uploaded sender credential}"
[[ $EUID == 0 && "$credential" =~ ^/tmp/coscircle-fcm-sender-[0-9]+\.json$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
service_user="$(systemctl show coscircle-api -p User --value)"
service_user="${service_user:-root}"
service_group="$(id -gn "$service_user")"
destination=/etc/coscircle/firebase-push-sender.json
environment=/etc/coscircle/api.env
[[ ! -L "$destination" && -f "$environment" ]]
backup="$(mktemp -d /var/backups/coscircle/fcm-sender-XXXXXXXX)"
cp -p "$environment" "$backup/api.env"
had_credential=false
if [[ -f "$destination" ]]; then cp -p "$destination" "$backup/firebase-push-sender.json";had_credential=true;fi
changed=false
recover() {
  result=$?
  if [[ "$result" != 0 ]]; then
    if [[ "$had_credential" == true ]]; then cp -p "$backup/firebase-push-sender.json" "$destination";else rm -f "$destination";fi
    if [[ "$changed" == true ]]; then cp -p "$backup/api.env" "$environment";systemctl restart coscircle-api;fi
  fi
  rm -f "$credential"
  exit "$result"
}
trap recover EXIT
python3 - "$credential" "$environment" <<'PY'
import json,sys
from pathlib import Path
c=json.loads(Path(sys.argv[1]).read_text())
assert c.get('project_id')=='coscircle' and c.get('client_email')=='coscircle-push-sender@coscircle.iam.gserviceaccount.com'
assert c.get('type')=='service_account' and c.get('private_key','').startswith('-----BEGIN PRIVATE KEY-----')
for line in Path(sys.argv[2]).read_text().splitlines():
    if '=' not in line or line.lstrip().startswith('#'):continue
    key,value=line.split('=',1);value=value.strip().strip('"\'')
    if key=='FIREBASE_SERVICE_ACCOUNT_JSON':assert not value,'Existing inline Firebase credential requires inspection'
    if key=='GOOGLE_APPLICATION_CREDENTIALS':assert not value or value=='/etc/coscircle/firebase-push-sender.json'
    if key=='FIREBASE_PROJECT_ID':assert not value or value=='coscircle'
PY
chgrp "$service_group" /etc/coscircle
chmod 0750 /etc/coscircle
install -m 0640 -o root -g "$service_group" "$credential" "$destination"
runuser -u "$service_user" -- test -r "$destination"
python3 - "$environment" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);lines=[line for line in p.read_text().splitlines() if not line.startswith(('GOOGLE_APPLICATION_CREDENTIALS=','FIREBASE_PROJECT_ID='))]
lines += ['FIREBASE_PROJECT_ID=coscircle','GOOGLE_APPLICATION_CREDENTIALS=/etc/coscircle/firebase-push-sender.json']
p.write_text('\n'.join(lines)+'\n');p.chmod(0o600)
PY
changed=true
systemctl restart coscircle-api
healthy=false
for attempt in {1..20}; do
  if curl -fsS --max-time 5 http://127.0.0.1:8080/api/health > "$backup/health.json"; then healthy=true;break;fi
  sleep 1
done
[[ "$healthy" == true ]]
python3 - "$backup/health.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1])).get('ok') is True
PY
printf 'Configured dedicated Firebase sender. Backup: %s\n' "$backup"
