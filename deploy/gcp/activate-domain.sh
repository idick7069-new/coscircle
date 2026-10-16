#!/usr/bin/env bash
set -euo pipefail

# Run on the production VM after issuing the domain certificate and uploading
# a tarball containing the rebuilt app/ and admin/ directories.
[[ "${EUID}" == 0 ]] || { echo "Run as root." >&2; exit 1; }
ARCHIVE="${1:?Pass the web archive path.}"
[[ -f "$ARCHIVE" ]] || exit 1
test -s /etc/letsencrypt/live/coscircle.app/fullchain.pem
test -s /etc/letsencrypt/live/coscircle.app/privkey.pem
nginx -t

BACKUP="$(mktemp -d /var/backups/coscircle-domain-XXXXXXXX)"
chmod 700 "$BACKUP"
cp -a /etc/coscircle/api.env "$BACKUP/api.env"
cp -a /etc/nginx/sites-available/coscircle "$BACKUP/nginx.conf"
mkdir -p /etc/nginx/coscircle-extra
EXTRA=/etc/nginx/coscircle-extra/coscircle.app.conf
if [[ -f "$EXTRA" ]]; then cp -a "$EXTRA" "$BACKUP/domain.conf"; fi
OLD_WEB="$(readlink -f /var/www/coscircle/current)"
API="$(readlink -f /opt/coscircle/api/current)"
printf '%s\n' "$OLD_WEB" > "$BACKUP/web-path"
RELEASE="/var/www/coscircle/releases/$(date -u +%Y%m%dT%H%M%SZ)-domain"
cp -a "$OLD_WEB" "$RELEASE"
tar -xzf "$ARCHIVE" -C "$RELEASE"
test -s "$RELEASE/app/main.dart.js"
test -s "$RELEASE/admin/main.dart.js"

rollback() {
  trap - ERR
  cp -a "$BACKUP/api.env" /etc/coscircle/api.env
  cp -a "$BACKUP/nginx.conf" /etc/nginx/sites-available/coscircle
  if [[ -f "$BACKUP/domain.conf" ]]; then
    cp -a "$BACKUP/domain.conf" "$EXTRA"
  else
    rm -f "$EXTRA"
  fi
  ln -sfn "$OLD_WEB" /var/www/coscircle/current
  nginx -t && systemctl reload nginx
  systemctl restart coscircle-api
  echo "Rolled back. Backup: $BACKUP" >&2
}
trap rollback ERR

API="$API" node <<'NODE'
const fs = require('node:fs');
const dotenv = require(`${process.env.API}/node_modules/dotenv`);
const mainPath = '/etc/nginx/sites-available/coscircle';
let main = fs.readFileSync(mainPath, 'utf8');
const first = main.indexOf('server {');
const next = main.indexOf('\nserver {', first + 1);
if (first < 0 || next < 0) throw new Error('Unexpected nginx layout');
let domain = main.slice(first, next);
if (!domain.includes('server_name 34.187.168.222;') ||
    !domain.includes('/etc/letsencrypt/live/coscircle-ip/')) {
  throw new Error('Expected existing IP server; do not replace its certificate');
}
domain = domain.replace('  listen 80 default_server;\n', '')
  .replace('listen 443 ssl default_server;', 'listen 443 ssl;')
  .replace('server_name 34.187.168.222;', 'server_name coscircle.app;')
  .replaceAll('/etc/letsencrypt/live/coscircle-ip/', '/etc/letsencrypt/live/coscircle.app/');
const http = `server {
  listen 80;
  server_name coscircle.app;
  location ^~ /.well-known/acme-challenge/ {
    root /var/lib/coscircle/acme;
    default_type text/plain;
    try_files $uri =404;
  }
  location / { return 301 https://coscircle.app$request_uri; }
}
`;
fs.writeFileSync('/etc/nginx/coscircle-extra/coscircle.app.conf', http + domain, { mode: 0o644 });
const include = 'include /etc/nginx/coscircle-extra/*.conf;';
// IP clients generally send no TLS SNI, so they must retain the default cert.
main = main.replace('listen 443 ssl;', 'listen 443 ssl default_server;');
if (!main.includes(include)) main = include + '\n\n' + main;
fs.writeFileSync(mainPath, main);

const envPath = '/etc/coscircle/api.env';
let content = fs.readFileSync(envPath, 'utf8');
const parsed = dotenv.parse(content);
const origins = new Set((parsed.CORS_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean));
origins.add('https://coscircle.app');
for (const [key, value] of Object.entries({
  CORS_ORIGINS: [...origins].join(','),
  PUBLIC_APP_URL: 'https://coscircle.app/app',
})) {
  const pattern = new RegExp(`^${key}=.*$`, 'm');
  const line = `${key}=${JSON.stringify(value)}`;
  content = pattern.test(content) ? content.replace(pattern, line) : content.trimEnd() + '\n' + line + '\n';
}
const stat = fs.statSync(envPath);
const temporary = `${envPath}.domain-new`;
fs.writeFileSync(temporary, content, { mode: stat.mode & 0o777 });
fs.chownSync(temporary, stat.uid, stat.gid);
fs.renameSync(temporary, envPath);
NODE

nginx -t
ln -sfn "$RELEASE" /var/www/coscircle/current
systemctl restart coscircle-api
systemctl reload nginx
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/api/health > /dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/api/health
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/ > /dev/null
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/admin/ > /dev/null
curl -fsS --resolve 34.187.168.222:443:127.0.0.1 https://34.187.168.222/api/health
[[ "$(readlink -f /opt/coscircle/api/current)" == "$API" ]]
trap - ERR
printf '\nBackup: %s\nWeb release: %s\nAPI unchanged: %s\n' "$BACKUP" "$RELEASE" "$API"
