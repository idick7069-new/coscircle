#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:?Set VM_NAME, for example coscircle-free-vm.}"
ZONE="${ZONE:?Set ZONE, for example us-west1-b.}"
GCP_PROJECT="${GCP_PROJECT:?Set the intended GCP project.}"
GCP_ACCOUNT="${GCP_ACCOUNT:?Set the intended GCP account.}"
API_BASE_URL="${API_BASE_URL:?Set API_BASE_URL, for example http://EXTERNAL_IP/api or https://your-domain/api.}"
APP_API_BASE_URL="${APP_API_BASE_URL:-${API_BASE_URL}}"
ADMIN_API_BASE_URL="${ADMIN_API_BASE_URL:-${API_BASE_URL}}"
WEB_SERVER_NAME="${WEB_SERVER_NAME:-_}"
ADMIN_SERVER_NAME="${ADMIN_SERVER_NAME:-admin.coscircle.local}"
ALLOW_INSECURE_API="${ALLOW_INSECURE_API:-false}"
PUBLIC_APP_URL="${PUBLIC_APP_URL:-${APP_API_BASE_URL%/api}/app}"
BUG_REPORT_URL="${BUG_REPORT_URL:-}"
FEEDBACK_FORM_URL="${FEEDBACK_FORM_URL:-https://forms.gle/WGFe57Y1AFW1LQda8}"
RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"
ENABLE_LINE_LOGIN="${ENABLE_LINE_LOGIN:-false}"
TLS_CERT_PATH="${TLS_CERT_PATH:-}"
TLS_KEY_PATH="${TLS_KEY_PATH:-}"
TLS_LISTEN=""
TLS_CONFIG=""
if [[ "${API_BASE_URL}" == https://* ]]; then
  : "${TLS_CERT_PATH:?HTTPS deployment requires TLS_CERT_PATH.}"
  : "${TLS_KEY_PATH:?HTTPS deployment requires TLS_KEY_PATH.}"
  [[ "${TLS_CERT_PATH}" =~ ^/[A-Za-z0-9_./-]+$ && "${TLS_KEY_PATH}" =~ ^/[A-Za-z0-9_./-]+$ ]] || exit 1
  TLS_LISTEN="listen 443 ssl default_server;"
  TLS_CONFIG="ssl_certificate ${TLS_CERT_PATH}; ssl_certificate_key ${TLS_KEY_PATH}; ssl_protocols TLSv1.2 TLSv1.3;"
fi

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
  --dart-define=PUBLIC_APP_URL="${PUBLIC_APP_URL}" \
  --dart-define=BUG_REPORT_URL="${BUG_REPORT_URL}" \
  --dart-define=FEEDBACK_FORM_URL="${FEEDBACK_FORM_URL}" \
  --dart-define=ENABLE_LINE_LOGIN="${ENABLE_LINE_LOGIN}" \
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
  -e "s|__TLS_LISTEN__|${TLS_LISTEN}|g" \
  -e "s|__TLS_CONFIG__|${TLS_CONFIG}|g" \
  deploy/gcp/nginx-coscircle.conf >"${TMP_DIR}/nginx-coscircle.conf"

tar -C "${TMP_DIR}/api" -czf "${TMP_DIR}/coscircle-api-${RELEASE_ID}.tar.gz" .
tar -C "${TMP_DIR}/web" -czf "${TMP_DIR}/coscircle-web-${RELEASE_ID}.tar.gz" .

gcloud compute scp \
  "${TMP_DIR}/coscircle-api-${RELEASE_ID}.tar.gz" \
  "${TMP_DIR}/coscircle-web-${RELEASE_ID}.tar.gz" \
  "${TMP_DIR}/nginx-coscircle.conf" \
  "${VM_NAME}:/tmp/" \
  --zone "${ZONE}" \
  --project "${GCP_PROJECT}" --account "${GCP_ACCOUNT}"

gcloud compute ssh "${VM_NAME}" --zone "${ZONE}" --project "${GCP_PROJECT}" --account "${GCP_ACCOUNT}" --command "
set -euo pipefail
sudo mkdir -p /opt/coscircle/api/releases/${RELEASE_ID} /var/www/coscircle/releases/${RELEASE_ID} /var/lib/coscircle/uploads
sudo chown -R coscircle:coscircle /var/lib/coscircle/uploads
sudo tar -xzf /tmp/coscircle-api-${RELEASE_ID}.tar.gz -C /opt/coscircle/api/releases/${RELEASE_ID}
sudo tar -xzf /tmp/coscircle-web-${RELEASE_ID}.tar.gz -C /var/www/coscircle/releases/${RELEASE_ID}
sudo rm -rf /opt/coscircle/api/releases/${RELEASE_ID}/uploads
sudo ln -sfn /var/lib/coscircle/uploads /opt/coscircle/api/releases/${RELEASE_ID}/uploads
sudo chown -R coscircle:coscircle /opt/coscircle/api/releases/${RELEASE_ID}
sudo python3 -m venv /opt/coscircle/api/releases/${RELEASE_ID}/.crawler-venv
sudo /opt/coscircle/api/releases/${RELEASE_ID}/.crawler-venv/bin/python -m pip install -r /opt/coscircle/api/releases/${RELEASE_ID}/scripts/requirements-crawler.txt
sudo -u coscircle /opt/coscircle/api/releases/${RELEASE_ID}/.crawler-venv/bin/python -c 'import curl_cffi; print(curl_cffi.__version__)'
cd /opt/coscircle/api/releases/${RELEASE_ID}
sudo -u coscircle npm ci --omit=dev
if [[ '${RUN_MIGRATIONS}' == 'true' ]]; then
  sudo bash -c '
    set -euo pipefail
    cd /opt/coscircle/api/releases/${RELEASE_ID}
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
sudo install -m 0644 /tmp/nginx-coscircle.conf /etc/nginx/sites-available/coscircle
sudo nginx -t
sudo ln -sfn /opt/coscircle/api/releases/${RELEASE_ID} /opt/coscircle/api/current
sudo ln -sfn /var/www/coscircle/releases/${RELEASE_ID} /var/www/coscircle/current
sudo systemctl daemon-reload
sudo systemctl restart coscircle-api
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
