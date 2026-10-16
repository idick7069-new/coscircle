#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" != 0 ]]; then
  echo "Run on the GCP VM as root."
  exit 1
fi

install -d -m 0700 /var/backups/coscircle
BACKUP_DIR="$(mktemp -d "/var/backups/coscircle/$(date -u +%Y%m%dT%H%M%SZ)-line-XXXXXX")"
mysqldump --single-transaction --routines --triggers --events --hex-blob --no-tablespaces coscircle |
  gzip >"${BACKUP_DIR}/coscircle.sql.gz"
chmod 0600 "${BACKUP_DIR}/coscircle.sql.gz"
gzip -t "${BACKUP_DIR}/coscircle.sql.gz"
cp -p /etc/coscircle/api.env "${BACKUP_DIR}/api.env"
chmod 0600 "${BACKUP_DIR}/api.env"
cp -p /etc/nginx/sites-available/coscircle "${BACKUP_DIR}/nginx-coscircle.conf"
readlink -f /opt/coscircle/api/current >"${BACKUP_DIR}/api-release.txt"
readlink -f /var/www/coscircle/current >"${BACKUP_DIR}/web-release.txt"
sha256sum "${BACKUP_DIR}/coscircle.sql.gz"
echo "Backup: ${BACKUP_DIR}"

install -d -m 0755 /var/lib/coscircle/acme
python3 -m venv /opt/coscircle/certbot-venv
/opt/coscircle/certbot-venv/bin/pip install 'certbot==5.4.0'
/opt/coscircle/certbot-venv/bin/certbot --version
