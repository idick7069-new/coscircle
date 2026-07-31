#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-coscircle-free-vm}"
ZONE="${ZONE:-us-west1-b}"
DB_PASSWORD="${DB_PASSWORD:?Set DB_PASSWORD to the production database password.}"
CORS_ORIGINS="${CORS_ORIGINS:?Set CORS_ORIGINS, for example http://EXTERNAL_IP or https://your-domain.}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB_PASSWORD_B64="$(printf '%s' "${DB_PASSWORD}" | base64)"
CORS_ORIGINS_B64="$(printf '%s' "${CORS_ORIGINS}" | base64)"

cd "${ROOT_DIR}"

gcloud compute scp \
  deploy/gcp/bootstrap-vm.sh \
  deploy/gcp/coscircle-api.service \
  deploy/gcp/nginx-coscircle.conf \
  "${VM_NAME}:/tmp/" \
  --zone="${ZONE}"

gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command "
set -euo pipefail
DB_PASSWORD=\$(printf '%s' '${DB_PASSWORD_B64}' | base64 --decode)
CORS_ORIGINS=\$(printf '%s' '${CORS_ORIGINS_B64}' | base64 --decode)
sudo DB_PASSWORD=\"\${DB_PASSWORD}\" CORS_ORIGINS=\"\${CORS_ORIGINS}\" bash /tmp/bootstrap-vm.sh
"
