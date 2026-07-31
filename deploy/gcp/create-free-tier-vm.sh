#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID to your GCP project ID.}"
VM_NAME="${VM_NAME:-coscircle-free-vm}"
ZONE="${ZONE:-us-west1-b}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-micro}"
BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-30GB}"
BOOT_DISK_TYPE="${BOOT_DISK_TYPE:-pd-standard}"
TAGS="${TAGS:-coscircle-web}"

gcloud config set project "${PROJECT_ID}"
gcloud services enable compute.googleapis.com

if ! gcloud compute instances describe "${VM_NAME}" --zone "${ZONE}" >/dev/null 2>&1; then
  gcloud compute instances create "${VM_NAME}" \
    --zone="${ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --image-family=ubuntu-2404-lts-amd64 \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size="${BOOT_DISK_SIZE}" \
    --boot-disk-type="${BOOT_DISK_TYPE}" \
    --tags="${TAGS}" \
    --metadata=enable-oslogin=TRUE
fi

if ! gcloud compute firewall-rules describe coscircle-allow-http >/dev/null 2>&1; then
  gcloud compute firewall-rules create coscircle-allow-http \
    --allow=tcp:80 \
    --target-tags="${TAGS}" \
    --description="Allow HTTP for CosCircle web and API"
fi

EXTERNAL_IP="$(gcloud compute instances describe "${VM_NAME}" \
  --zone="${ZONE}" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"

echo "VM_NAME=${VM_NAME}"
echo "ZONE=${ZONE}"
echo "EXTERNAL_IP=${EXTERNAL_IP}"
echo "API_BASE_URL=http://${EXTERNAL_IP}/api"
