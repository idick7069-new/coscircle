#!/usr/bin/env bash
set -euo pipefail
[[ "$EUID" == 0 ]] || exit 1
API_ARCHIVE="${1:?Pass API overlay archive.}"
WEB_ARCHIVE="${2:?Pass app web archive.}"
OLD_API="$(readlink -f /opt/coscircle/api/current)"
OLD_WEB="$(readlink -f /var/www/coscircle/current)"
install -d -m 0700 /var/backups/coscircle
BACKUP="$(mktemp -d "/var/backups/coscircle/$(date -u +%Y%m%dT%H%M%SZ)-email-XXXXXX")"
mysqldump --single-transaction --routines --triggers --events --hex-blob --no-tablespaces coscircle | gzip > "$BACKUP/coscircle.sql.gz"
chmod 0600 "$BACKUP/coscircle.sql.gz"
gzip -t "$BACKUP/coscircle.sql.gz"
cp -p /etc/coscircle/api.env "$BACKUP/api.env"
chmod 0600 "$BACKUP/api.env"
printf '%s\n' "$OLD_API" > "$BACKUP/api-path"
printf '%s\n' "$OLD_WEB" > "$BACKUP/web-path"
sha256sum "$BACKUP/coscircle.sql.gz"
snapshot() {
  mysqldump --single-transaction --no-tablespaces --no-create-info --skip-comments --skip-add-locks --skip-disable-keys --order-by-primary --hex-blob \
    coscircle users user_auth_identities friendships follows circle_members event_bookings | sha256sum
}
snapshot > "$BACKUP/accounts-before.sha256"
ID="$(date -u +%Y%m%dT%H%M%SZ)-email-$$"
API="/opt/coscircle/api/releases/$ID"
WEB="/var/www/coscircle/releases/$ID"
cp -a "$OLD_API" "$API"
cp -a "$OLD_WEB" "$WEB"
tar -xzf "$API_ARCHIVE" -C "$API"
tar -xzf "$WEB_ARCHIVE" -C "$WEB"
chown -R coscircle:coscircle "$API"
node --check "$API/src/server.js"
node --test "$API/src/email-account-service.test.js" "$API/src/mail-service.test.js"
test -s "$WEB/app/main.dart.js"
nginx -t

rollback() {
  trap - ERR
  ln -sfn "$OLD_API" /opt/coscircle/api/current
  ln -sfn "$OLD_WEB" /var/www/coscircle/current
  systemctl restart coscircle-api
  echo "Restored previous API/web. Additive table retained. Backup: $BACKUP" >&2
}
trap rollback ERR
mysql coscircle < "$API/db/migrate_email_actions.sql"
ln -sfn "$API" /opt/coscircle/api/current
ln -sfn "$WEB" /var/www/coscircle/current
systemctl restart coscircle-api
for attempt in $(seq 1 45); do
  if curl -fsS http://127.0.0.1:8080/api/health > /dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/api/health
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/ > /dev/null
curl -fsS --resolve 34.187.168.222:443:127.0.0.1 https://34.187.168.222/api/health
snapshot > "$BACKUP/accounts-after.sha256"
if cmp -s "$BACKUP/accounts-before.sha256" "$BACKUP/accounts-after.sha256"; then
  echo 'Accounts, sessions and social/booking data unchanged.'
else
  echo 'Data changed during deployment; compare backups before attributing changes.'
fi
trap - ERR
printf '\nBackup: %s\nAPI: %s\nWeb: %s\n' "$BACKUP" "$API" "$WEB"
