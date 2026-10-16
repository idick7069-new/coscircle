#!/usr/bin/env bash
set -euo pipefail
[[ "$EUID" == 0 ]] || { echo 'Run on the VM with sudo.' >&2; exit 1; }
ARCHIVE="${1:?Pass an archive containing app/.}"
EXPECTED_SHA="${2:?Pass the archive SHA-256.}"
[[ "$EXPECTED_SHA" =~ ^[a-f0-9]{64}$ ]] || exit 1
printf '%s  %s\n' "$EXPECTED_SHA" "$ARCHIVE" | sha256sum -c -
OLD_WEB="$(readlink -f /var/www/coscircle/current)"
API="$(readlink -f /opt/coscircle/api/current)"
ID="$(date -u +%Y%m%dT%H%M%SZ)-feedback-$$"
NEW_WEB="/var/www/coscircle/releases/$ID"
install -d -m 0700 /var/backups/coscircle
BACKUP="$(mktemp -d "/var/backups/coscircle/$ID-XXXXXX")"
printf '%s\n' "$OLD_WEB" > "$BACKUP/web-path"
printf '%s\n' "$API" > "$BACKUP/api-path"
cp -a "$OLD_WEB" "$NEW_WEB"
tar -xzf "$ARCHIVE" -C "$NEW_WEB"
test -s "$NEW_WEB/app/main.dart.js"
grep -Fq 'https://forms.gle/WGFe57Y1AFW1LQda8' "$NEW_WEB/app/main.dart.js"
nginx -t
rollback() {
  trap - ERR
  ln -sfn "$OLD_WEB" /var/www/coscircle/current
  echo "Restored previous website. Backup: $BACKUP" >&2
}
trap rollback ERR
ln -sfn "$NEW_WEB" /var/www/coscircle/current
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/api/health
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/ > /dev/null
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/admin/ > /dev/null
curl -fsS --resolve 34.187.168.222:443:127.0.0.1 https://34.187.168.222/api/health
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/main.dart.js | sha256sum > "$BACKUP/served-app.sha256"
sha256sum "$NEW_WEB/app/main.dart.js" | cut -d ' ' -f 1 > "$BACKUP/expected-app.sha256"
cut -d ' ' -f 1 "$BACKUP/served-app.sha256" | cmp - "$BACKUP/expected-app.sha256"
[[ "$(readlink -f /opt/coscircle/api/current)" == "$API" ]]
trap - ERR
printf '\nBackup: %s\nWeb: %s\nAPI unchanged: %s\n' "$BACKUP" "$NEW_WEB" "$API"
cat "$BACKUP/served-app.sha256"
