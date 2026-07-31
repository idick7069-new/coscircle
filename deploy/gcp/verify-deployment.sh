#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:?Set BASE_URL, for example http://EXTERNAL_IP or https://your-domain.}"
API_BASE_URL="${BASE_URL%/}/api"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

curl -fsS "${API_BASE_URL}/health"
curl -fsSI "${BASE_URL%/}/" >/dev/null

(
  cd "${ROOT_DIR}/backend"
  API_BASE_URL="${API_BASE_URL}" npm run smoke:privacy
)

echo "CosCircle deployment verified at ${BASE_URL%/}."
