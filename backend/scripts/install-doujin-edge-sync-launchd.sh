#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NODE_BIN="${NODE_BIN:-$(command -v node)}"
API_BASE_URL="${COSCIRCLE_API_BASE_URL:-http://34.187.168.222/api}"
SOURCE_URL="${DOUJIN_SOURCE_URL:-https://www.doujin.com.tw/events/alist/all}"
TOKEN="${COSCIRCLE_SYNC_INGEST_TOKEN:-}"
INTERVAL_SECONDS="${COSCIRCLE_SYNC_INTERVAL_SECONDS:-21600}"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/CosCircle"
LOG_DIR="${HOME}/Library/Logs/CosCircle"
ENV_FILE="${APP_SUPPORT_DIR}/doujin-edge-sync.env"
PLIST_FILE="${HOME}/Library/LaunchAgents/app.coscircle.doujin-edge-sync.plist"

if [[ -z "${NODE_BIN}" ]]; then
  echo "node was not found. Install Node.js or pass NODE_BIN=/path/to/node." >&2
  exit 2
fi

if [[ ${#TOKEN} -lt 32 ]]; then
  echo "COSCIRCLE_SYNC_INGEST_TOKEN is required and must be at least 32 characters." >&2
  exit 2
fi

mkdir -p "${APP_SUPPORT_DIR}" "${LOG_DIR}" "${HOME}/Library/LaunchAgents"
chmod 700 "${APP_SUPPORT_DIR}"

cat > "${ENV_FILE}" <<ENV
COSCIRCLE_API_BASE_URL=${API_BASE_URL}
COSCIRCLE_SYNC_INGEST_TOKEN=${TOKEN}
DOUJIN_SOURCE_URL=${SOURCE_URL}
ENV
chmod 600 "${ENV_FILE}"

cat > "${PLIST_FILE}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>app.coscircle.doujin-edge-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${ROOT_DIR}/backend/scripts/doujin-edge-sync.js</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}/backend</string>
  <key>StartInterval</key>
  <integer>${INTERVAL_SECONDS}</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/doujin-edge-sync.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/doujin-edge-sync.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "${PLIST_FILE}" >/dev/null 2>&1 || true
launchctl load "${PLIST_FILE}"

echo "Installed app.coscircle.doujin-edge-sync"
echo "Config: ${ENV_FILE}"
echo "Logs: ${LOG_DIR}/doujin-edge-sync.out.log"
