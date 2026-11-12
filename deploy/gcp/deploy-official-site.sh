#!/usr/bin/env bash
set -euo pipefail
: "${GCP_PROJECT:?Set the intended GCP project}"
: "${GCP_ACCOUNT:?Set the intended GCP account}"
vm="${VM_NAME:-coscircle-free-vm}"
zone="${ZONE:-us-west1-b}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_id="$(date -u +%Y%m%d%H%M%S)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/site/official"
cp -R "$root/web/official/." "$work/site/official/"
cp "$root/web/official/index.html" "$root/web/official/android-testing.html" "$work/site/"
archive="coscircle-official-${release_id}.tar.gz"
COPYFILE_DISABLE=1 tar -C "$work/site" -czf "$work/$archive" .
gcloud compute scp "$work/$archive" "$vm:/tmp/$archive" --zone "$zone" --project "$GCP_PROJECT" --account "$GCP_ACCOUNT"
gcloud compute ssh "$vm" --zone "$zone" --project "$GCP_PROJECT" --account "$GCP_ACCOUNT" --command "sudo bash -s -- /tmp/$archive" < "$root/deploy/gcp/install-official-on-vm.sh"
