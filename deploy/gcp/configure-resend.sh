#!/usr/bin/env bash
set -euo pipefail
set +x
ulimit -c 0
[[ "$EUID" == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
RECIPIENT="${1:?Provide the approved test recipient.}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test -r "$ROOT/scripts/resend-setup.js"
echo "A test email will be sent to: $RECIPIENT"
echo 'Paste the Resend API key at the next prompt, then press Enter. Input is hidden.'
KEY=''
trap 'unset KEY' EXIT
if ! IFS= read -r -s -p 'Resend API key: ' KEY < /dev/tty; then
  printf '\nSecret input was cancelled; no email was sent.\n' > /dev/tty
  exit 1
fi
printf '\n' > /dev/tty
echo 'Checking the key and sending the test email...'
printf '%s' "$KEY" | node "$ROOT/scripts/resend-setup.js" "$RECIPIENT"
unset KEY
