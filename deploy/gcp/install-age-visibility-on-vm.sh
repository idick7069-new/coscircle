#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
archive="${1:?Pass the age-visibility payload}"
expected="${2:?Pass the expected current server SHA256}"
[[ $EUID == 0 && "$archive" =~ ^/tmp/coscircle-age-[0-9]+\.tar\.gz$ && "$expected" =~ ^[a-f0-9]{64}$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
current=/opt/coscircle/api/current
old="$(readlink -f "$current")"
[[ -L "$current" && "$old" == /opt/coscircle/api/releases/* ]]
work="$(mktemp -d /tmp/coscircle-age-stage-XXXXXXXX)"
tar -xzf "$archive" -C "$work" --no-same-owner
new_sha="$(sha256sum "$work/server.js" | cut -d ' ' -f 1)"
old_sha="$(sha256sum "$old/src/server.js" | cut -d ' ' -f 1)"
if [[ "$old_sha" == "$new_sha" ]]; then
  rm -rf "$work"
  echo 'Age visibility already installed'
  exit 0
fi
[[ "$old_sha" == "$expected" ]]
backup="$(mktemp -d /var/backups/coscircle/age-visibility-XXXXXXXX)"
release="$(mktemp -d /opt/coscircle/api/releases/age-visibility-XXXXXXXX)"
switched=false
cleanup() {
  result=$?
  if [[ "$result" != 0 && "$switched" == true ]]; then
    ln -s "$old" "${current}.age-rollback"
    mv -Tf "${current}.age-rollback" "$current"
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
install -m 0644 "$work/profile-age-privacy.js" "$release/src/profile-age-privacy.js"
install -m 0644 "$work/migrate_age_visibility.sql" "$release/db/migrate_age_visibility.sql"
node --check "$release/src/server.js"
node --check "$release/src/profile-age-privacy.js"
chmod -R a+rX "$release"
timeout 60 mysql coscircle < "$release/db/migrate_age_visibility.sql"
[[ "$(readlink -f "$current")" == "$old" ]]
ln -s "$release" "${current}.age-next"
mv -Tf "${current}.age-next" "$current"
switched=true
systemctl restart coscircle-api
ready=false
for attempt in {1..20}; do
  if curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/api/health > "$backup/health.json"; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]]
node -e 'const fs=require("fs");if(JSON.parse(fs.readFileSync(process.argv[1])).ok!==true)process.exit(1)' "$backup/health.json"
printf 'Published API: %s\nPrevious API retained: %s\nRoot-only DB backup: %s\n' "$release" "$old" "$backup"
