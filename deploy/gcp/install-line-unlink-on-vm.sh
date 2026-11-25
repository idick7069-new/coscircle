#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
archive="${1:?Pass the LINE unlink payload}"
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
if [[ "$old_sha" == "$new_sha" && "$(sha256sum "$old/src/auth-identities.js" | cut -d ' ' -f 1)" == "$(sha256sum "$work/auth-identities.js" | cut -d ' ' -f 1)" ]]; then
  rm -rf "$work"
  echo 'LINE unlink already installed'
  exit 0
fi
[[ "$old_sha" == "$expected" ]]
backup="$(mktemp -d /var/backups/coscircle/line-unlink-XXXXXXXX)"
release="$(mktemp -d /opt/coscircle/api/releases/line-unlink-XXXXXXXX)"
switched=false
cleanup() {
  result=$?
  if [[ "$result" != 0 && "$switched" == true ]]; then
    ln -s "$old" "${current}.line-rollback"
    mv -Tf "${current}.line-rollback" "$current"
    systemctl restart coscircle-api
    echo "Restored previous API: $old" >&2
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
install -m 0644 "$work/auth-identities.js" "$release/src/auth-identities.js"
install -m 0600 "$work/line-unlink-production-qa.mjs" "$release/scripts/line-unlink-production-qa.mjs"
node --check "$release/src/server.js"
node --check "$release/src/auth-identities.js"
chmod -R a+rX "$release/src"
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
