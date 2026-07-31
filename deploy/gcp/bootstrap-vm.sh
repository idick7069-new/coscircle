#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-coscircle}"
DB_USER="${DB_USER:-coscircle_app}"
DB_PASSWORD="${DB_PASSWORD:?Set DB_PASSWORD to a long random password before running this script.}"
API_PORT="${API_PORT:-8080}"
CORS_ORIGINS="${CORS_ORIGINS:-http://$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || echo localhost)}"

if [[ "${DB_PASSWORD}" == *"'"* ]]; then
  echo "DB_PASSWORD must not contain a single quote for this bootstrap script." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg nginx mysql-server rsync tar

if ! command -v node >/dev/null 2>&1 || ! node --version | grep -q '^v22\.'; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
fi

if ! id -u coscircle >/dev/null 2>&1; then
  useradd --system --home-dir /opt/coscircle --shell /usr/sbin/nologin coscircle
fi

mkdir -p /opt/coscircle/api/releases /opt/coscircle/api/shared /var/www/coscircle/releases /var/lib/coscircle/uploads /etc/coscircle
chown -R coscircle:coscircle /opt/coscircle /var/lib/coscircle/uploads

cat >/etc/mysql/mysql.conf.d/coscircle.cnf <<'MYSQLCNF'
[mysqld]
bind-address = 127.0.0.1
MYSQLCNF
systemctl restart mysql

mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

if [[ ! -f /etc/coscircle/api.env ]]; then
  cat >/etc/coscircle/api.env <<EOF
NODE_ENV=production
PORT=${API_PORT}
CORS_ORIGINS=${CORS_ORIGINS}
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=${DB_USER}
MYSQL_PASSWORD=${DB_PASSWORD}
MYSQL_DATABASE=${DB_NAME}
EVENT_SCRAPER_ENABLED=true
EVENT_SCRAPER_TIME_ZONE=Asia/Taipei
EOF
  chmod 0640 /etc/coscircle/api.env
  chown root:coscircle /etc/coscircle/api.env
fi

install -m 0644 /tmp/coscircle-api.service /etc/systemd/system/coscircle-api.service
install -m 0644 /tmp/nginx-coscircle.conf /etc/nginx/sites-available/coscircle
ln -sfn /etc/nginx/sites-available/coscircle /etc/nginx/sites-enabled/coscircle
rm -f /etc/nginx/sites-enabled/default

systemctl daemon-reload
systemctl enable coscircle-api
nginx -t
systemctl restart nginx

echo "CosCircle VM bootstrap completed."
