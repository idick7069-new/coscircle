#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
archive="${1:?Pass the line-web payload}"
expected="${2:?Pass the expected current server SHA256}"
[[ $EUID == 0 && "$archive" =~ ^/tmp/coscircle-line-[0-9]+\.tar\.gz$ && "$expected" =~ ^[a-f0-9]{64}$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
current=/opt/coscircle/api/current
old="$(readlink -f "$current")"
[[ -L "$current" && "$old" == /opt/coscircle/api/releases/* ]]
work="$(mktemp -d /tmp/coscircle-line-stage-XXXXXXXX)"
tar -xzf "$archive" -C "$work" --no-same-owner
new_sha="$(sha256sum "$work/server.js" | cut -d ' ' -f 1)"
old_sha="$(sha256sum "$old/src/server.js" | cut -d ' ' -f 1)"
if [[ "$old_sha" == "$new_sha" ]]; then
  rm -rf "$work"
  echo 'LINE web login already installed'
  exit 0
fi
[[ "$old_sha" == "$expected" ]]
backup="$(mktemp -d /var/backups/coscircle/line-web-XXXXXXXX)"
release="$(mktemp -d /opt/coscircle/api/releases/line-web-XXXXXXXX)"
switched=false
nginx_changed=false
nginx_file=/etc/nginx/coscircle-extra/coscircle.app.conf
cleanup() {
  result=$?
  if [[ "$result" != 0 && "$switched" == true ]]; then
    ln -s "$old" "${current}.line-rollback"
    mv -Tf "${current}.line-rollback" "$current"
    systemctl restart coscircle-api
    echo "Restored previous API: $old" >&2
  fi
  if [[ "$result" != 0 && "$nginx_changed" == true ]]; then
    cp "$backup/nginx-before.conf" "$nginx_file"
    nginx -t && systemctl reload nginx
  fi
  rm -rf "$work"
  exit "$result"
}
trap cleanup EXIT

timeout 600 mysqldump --single-transaction --protocol=SOCKET --routines --triggers --events --hex-blob --no-tablespaces coscircle 2>"$backup/dump.stderr" | gzip >"$backup/coscircle.sql.gz"
gzip -t "$backup/coscircle.sql.gz"
cp "$old/src/server.js" "$backup/server-before.js"
cp -a "$old/." "$release/"
install -m 0644 "$work/server.js" "$release/src/server.js"
install -m 0644 "$work/line-web-login.js" "$release/src/line-web-login.js"
install -m 0644 "$work/migrate_line_web_login.sql" "$release/db/migrate_line_web_login.sql"
node --check "$release/src/server.js"
node --check "$release/src/line-web-login.js"
chmod -R a+rX "$release/src"
timeout 60 mysql coscircle < "$release/db/migrate_line_web_login.sql"
cp "$nginx_file" "$backup/nginx-before.conf"
python3 - "$nginx_file" "$work/line-web-callback.nginx" <<'PYCODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);text=p.read_text()
if 'location = /api/auth/line/web/callback' not in text:
    marker='  location /api/ {'
    assert text.count(marker)==1
    p.write_text(text.replace(marker,Path(sys.argv[2]).read_text()+marker))
PYCODE
nginx_changed=true
nginx -t
systemctl reload nginx
[[ "$(readlink -f "$current")" == "$old" ]]
ln -s "$release" "${current}.line-next"
mv -Tf "${current}.line-next" "$current"
switched=true
systemctl restart coscircle-api
ready=false
for attempt in {1..20}; do
  if curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/api/health > "$backup/health.json"; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]]
node -e 'const fs=require("fs");if(JSON.parse(fs.readFileSync(process.argv[1])).ok!==true)process.exit(1)' "$backup/health.json"
curl -fsS http://127.0.0.1:8080/api/auth/line/config > "$backup/line-config-public.json"
node -e 'const fs=require("fs");const x=JSON.parse(fs.readFileSync(process.argv[1]));if(typeof x.enabled!=="boolean"||typeof x.webEnabled!=="boolean")process.exit(1)' "$backup/line-config-public.json"
printf 'Published API: %s\nPrevious API retained: %s\nRoot-only DB backup: %s\n' "$release" "$old" "$backup"
