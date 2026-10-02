#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:?Set VM_NAME, for example coscircle-free-vm.}"
ZONE="${ZONE:?Set ZONE, for example us-west1-b.}"
API_BASE_URL="${API_BASE_URL:?Set API_BASE_URL, for example http://EXTERNAL_IP/api or https://your-domain/api.}"
APP_API_BASE_URL="${APP_API_BASE_URL:-${API_BASE_URL}}"
ADMIN_API_BASE_URL="${ADMIN_API_BASE_URL:-${API_BASE_URL}}"
WEB_SERVER_NAME="${WEB_SERVER_NAME:-_}"
ADMIN_SERVER_NAME="${ADMIN_SERVER_NAME:-admin.coscircle.local}"
ALLOW_INSECURE_API="${ALLOW_INSECURE_API:-false}"
RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"

RELEASE_ID="$(date +%Y%m%d%H%M%S)"
TMP_DIR="$(mktemp -d)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cd "${ROOT_DIR}"

flutter build web \
  --release \
  --base-href=/app/ \
  --dart-define=API_BASE_URL="${APP_API_BASE_URL}" \
  --dart-define=ALLOW_INSECURE_API="${ALLOW_INSECURE_API}"

mkdir -p "${TMP_DIR}/api" "${TMP_DIR}/web"
rsync -a \
  backend/package.json backend/package-lock.json backend/src backend/scripts backend/db \
  "${TMP_DIR}/api/"
mkdir -p "${TMP_DIR}/web/official"
rsync -a web/official/ "${TMP_DIR}/web/official/"
cp web/official/index.html "${TMP_DIR}/web/index.html"
rsync -a web/favicon.png web/icons "${TMP_DIR}/web/"
mkdir -p "${TMP_DIR}/web/app"
rsync -a build/web/ "${TMP_DIR}/web/app/"

flutter build web \
  --release \
  --target=lib/admin_main.dart \
  --base-href=/ \
  --dart-define=API_BASE_URL="${ADMIN_API_BASE_URL}" \
  --dart-define=ALLOW_INSECURE_API="${ALLOW_INSECURE_API}"
mkdir -p "${TMP_DIR}/web/admin-root"
rsync -a build/web/ "${TMP_DIR}/web/admin-root/"

flutter build web \
  --release \
  --target=lib/admin_main.dart \
  --base-href=/admin/ \
  --dart-define=API_BASE_URL="${ADMIN_API_BASE_URL}" \
  --dart-define=ALLOW_INSECURE_API="${ALLOW_INSECURE_API}"
mkdir -p "${TMP_DIR}/web/admin"
rsync -a build/web/ "${TMP_DIR}/web/admin/"

sed \
  -e "s/__WEB_SERVER_NAME__/${WEB_SERVER_NAME}/g" \
  -e "s/__ADMIN_SERVER_NAME__/${ADMIN_SERVER_NAME}/g" \
  deploy/gcp/nginx-coscircle.conf >"${TMP_DIR}/nginx-coscircle.conf"

tar -C "${TMP_DIR}/api" -czf "${TMP_DIR}/coscircle-api-${RELEASE_ID}.tar.gz" .
tar -C "${TMP_DIR}/web" -czf "${TMP_DIR}/coscircle-web-${RELEASE_ID}.tar.gz" .

gcloud compute scp \
  "${TMP_DIR}/coscircle-api-${RELEASE_ID}.tar.gz" \
  "${TMP_DIR}/coscircle-web-${RELEASE_ID}.tar.gz" \
  "${TMP_DIR}/nginx-coscircle.conf" \
  "${VM_NAME}:/tmp/" \
  --zone "${ZONE}"

gcloud compute ssh "${VM_NAME}" --zone "${ZONE}" --command "
set -euo pipefail
sudo mkdir -p /opt/coscircle/api/releases/${RELEASE_ID} /var/www/coscircle/releases/${RELEASE_ID} /var/lib/coscircle/uploads
sudo chown -R coscircle:coscircle /var/lib/coscircle/uploads
sudo tar -xzf /tmp/coscircle-api-${RELEASE_ID}.tar.gz -C /opt/coscircle/api/releases/${RELEASE_ID}
sudo tar -xzf /tmp/coscircle-web-${RELEASE_ID}.tar.gz -C /var/www/coscircle/releases/${RELEASE_ID}
sudo rm -rf /opt/coscircle/api/releases/${RELEASE_ID}/uploads
sudo ln -sfn /var/lib/coscircle/uploads /opt/coscircle/api/releases/${RELEASE_ID}/uploads
sudo chown -R coscircle:coscircle /opt/coscircle/api/releases/${RELEASE_ID}
sudo ln -sfn /opt/coscircle/api/releases/${RELEASE_ID} /opt/coscircle/api/current
sudo ln -sfn /var/www/coscircle/releases/${RELEASE_ID} /var/www/coscircle/current
sudo install -m 0644 /tmp/nginx-coscircle.conf /etc/nginx/sites-available/coscircle
cd /opt/coscircle/api/current
sudo -u coscircle npm ci --omit=dev
if [[ '${RUN_MIGRATIONS}' == 'true' ]]; then
  sudo bash -c '
    set -euo pipefail
    cd /opt/coscircle/api/current
    set -a
    . /etc/coscircle/api.env
    set +a
    USERS_TABLE_COUNT=\$(MYSQL_PWD=\"\${MYSQL_PASSWORD}\" mysql -N -B -h \"\${MYSQL_HOST}\" -P \"\${MYSQL_PORT}\" -u \"\${MYSQL_USER}\" \"\${MYSQL_DATABASE}\" -e \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '\''users'\'';\")
    if [[ \"\${USERS_TABLE_COUNT}\" == \"0\" ]]; then
      MYSQL_PWD=\"\${MYSQL_PASSWORD}\" mysql -h \"\${MYSQL_HOST}\" -P \"\${MYSQL_PORT}\" -u \"\${MYSQL_USER}\" \"\${MYSQL_DATABASE}\" < db/schema.sql
    else
      echo \"Existing database detected; skipping automatic migrations. Apply pending migrations with a DB admin account before deploying incompatible changes.\"
    fi
  '
fi
sudo systemctl daemon-reload
sudo systemctl restart coscircle-api
sudo nginx -t
sudo systemctl reload nginx
for attempt in \$(seq 1 20); do
  if curl -fsS http://127.0.0.1:8080/api/health; then
    exit 0
  fi
  sleep 1
done
sudo systemctl status coscircle-api --no-pager -l
exit 1
"

echo "Deployed release ${RELEASE_ID} to ${VM_NAME}."
