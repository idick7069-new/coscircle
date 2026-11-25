#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
archive="${1:?Pass the account-safety payload}"
expected="${2:?Pass the expected current server SHA256}"
[[ $EUID == 0 && "$archive" =~ ^/tmp/coscircle-safety-[0-9]+\.tar\.gz$ && "$expected" =~ ^[a-f0-9]{64}$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
current=/opt/coscircle/api/current
old="$(readlink -f "$current")"
[[ -L "$current" && "$old" == /opt/coscircle/api/releases/* ]]
work="$(mktemp -d /tmp/coscircle-safety-stage-XXXXXXXX)"
tar -xzf "$archive" -C "$work" --no-same-owner
new_sha="$(sha256sum "$work/server.js" | cut -d ' ' -f 1)"
old_sha="$(sha256sum "$old/src/server.js" | cut -d ' ' -f 1)"
if [[ "$old_sha" == "$new_sha" ]]; then
  rm -rf "$work"
  echo 'Account safety already installed'
  exit 0
fi
[[ "$old_sha" == "$expected" ]]
# The service uses the existing transaction helper; refuse an unexpected implementation.
cmp "$work/db-transaction.js" "$old/src/db-transaction.js"
backup="$(mktemp -d /var/backups/coscircle/account-safety-XXXXXXXX)"
release="$(mktemp -d /opt/coscircle/api/releases/account-safety-XXXXXXXX)"
switched=false
cleanup() {
  result=$?
  if [[ "$result" != 0 && "$switched" == true ]]; then
    ln -s "$old" "${current}.safety-rollback"
    mv -Tf "${current}.safety-rollback" "$current"
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
for file in server.js account-deletion.js content-reports.js; do
  install -m 0644 "$work/$file" "$release/src/$file"
  node --check "$release/src/$file"
done
for file in migrate_account_deletion.sql migrate_content_reports.sql; do
  install -m 0644 "$work/$file" "$release/db/$file"
  timeout 60 mysql coscircle < "$release/db/$file"
done
install -m 0600 "$work/safety-production-qa.mjs" "$release/scripts/safety-production-qa.mjs"
chmod -R a+rX "$release/src"
[[ "$(readlink -f "$current")" == "$old" ]]
ln -s "$release" "${current}.safety-next"
mv -Tf "${current}.safety-next" "$current"
switched=true
systemctl restart coscircle-api
ready=false
for attempt in {1..20}; do
  if curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/api/health > "$backup/health.json"; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]]
node -e 'const fs=require("fs");if(JSON.parse(fs.readFileSync(process.argv[1])).ok!==true)process.exit(1)' "$backup/health.json"
# This creates and erases only isolated QA accounts and records; never logs credentials.
DOTENV_CONFIG_PATH=/etc/coscircle/api.env node "$release/scripts/safety-production-qa.mjs" --run-production-qa | tee "$backup/qa.log"
printf 'Published API: %s\nPrevious API retained: %s\nRoot-only DB backup: %s\n' "$release" "$old" "$backup"
