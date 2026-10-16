#!/usr/bin/env bash
set -euo pipefail

# Secret input happens on the VM's SSH terminal, not in chat or local files.
exec gcloud compute ssh coscircle-free-vm \
  --zone us-west1-b --project cos-circle --account idick7069@gmail.com \
  --ssh-flag=-t \
  --command='sudo bash /opt/coscircle/mail-tools/current/deploy/configure-resend.sh idick7069jp@gmail.com'
