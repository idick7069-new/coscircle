# GCP free-tier VM deployment

This deployment keeps costs low by running MySQL, the Express API, and the
Flutter web build on a single Compute Engine `e2-micro` VM.

Google's Free Tier currently includes one non-preemptible `e2-micro` VM per
month in `us-west1`, `us-central1`, or `us-east1`, plus 30 GB-months of standard
persistent disk. The Free Tier also has outbound data limits, so keep public
traffic modest and set a billing budget alert.

Sources:

- Google Cloud Free Tier overview:
  <https://docs.cloud.google.com/free/docs/free-cloud-features>
- Compute Engine Free Tier limits are listed under `Compute Engine` on that
  page.

## Architecture

- Compute Engine VM: `e2-micro`, Ubuntu LTS, standard persistent disk.
- MySQL: installed on the same VM and bound to `127.0.0.1`.
- API: Node.js 22 service managed by systemd.
- Web: static official website at `/`, Flutter web app at `/app/`.
- Admin: independent Flutter web admin at `admin.coscircle.xxx`; IP/test fallback at `/admin/`.
- Nginx: serves `/`, `/app/`, `/admin/`, admin subdomain, and proxies `/api/` to `127.0.0.1:8080`.
- Uploads: stored in `/var/lib/coscircle/uploads`.

This is the cheapest practical production setup, but it is not highly
available. Backups matter because the database and uploads live on the VM disk.

## Required information

I need these values before I can deploy it for you:

- GCP project ID.
- GCP billing is active and budget alerts are acceptable.
- Preferred free-tier region and zone, recommended `us-west1-b`.
- VM name, recommended `coscircle-free-vm`.
- Domain name, or approval to start with the VM external IP over HTTP.
- Production MySQL password for `coscircle_app`.
- Whether to import scraped event data during the first deploy.

Local prerequisite:

- Install and log in to the Google Cloud CLI, because this machine currently
  does not have `gcloud` available.

## 1. Create the VM

Use a Free Tier eligible region. `us-west1-b` is usually a good default.

```sh
PROJECT_ID=YOUR_PROJECT_ID \
VM_NAME=coscircle-free-vm \
ZONE=us-west1-b \
deploy/gcp/create-free-tier-vm.sh
```

Get the external IP:

```sh
gcloud compute instances describe coscircle-free-vm \
  --zone=us-west1-b \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

## 2. Bootstrap the VM

Generate a DB password locally:

```sh
openssl rand -base64 32
```

Run bootstrap:

```sh
VM_NAME=coscircle-free-vm \
ZONE=us-west1-b \
DB_PASSWORD='PASTE_DB_PASSWORD' \
CORS_ORIGINS='http://EXTERNAL_IP' \
deploy/gcp/bootstrap-remote.sh
```

If using a domain, set:

```text
CORS_ORIGINS=https://coscircle.xxx,https://admin.coscircle.xxx
```

## 3. Deploy API and web

For initial HTTP deployment by external IP:

```sh
VM_NAME=coscircle-free-vm \
ZONE=us-west1-b \
API_BASE_URL=http://EXTERNAL_IP/api \
ALLOW_INSECURE_API=true \
deploy/gcp/deploy-vm.sh
```

After this deployment:

- Official site: `http://EXTERNAL_IP/`
- User Web App: `http://EXTERNAL_IP/app/`
- Admin fallback for testing: `http://EXTERNAL_IP/admin/`

For domain/HTTPS deployment:

```sh
VM_NAME=coscircle-free-vm \
ZONE=us-west1-b \
WEB_SERVER_NAME=coscircle.xxx \
ADMIN_SERVER_NAME=admin.coscircle.xxx \
APP_API_BASE_URL=https://coscircle.xxx/api \
ADMIN_API_BASE_URL=https://admin.coscircle.xxx/api \
API_BASE_URL=https://coscircle.xxx/api \
deploy/gcp/deploy-vm.sh
```

After DNS is configured:

- Admin: `https://admin.coscircle.xxx`
- User Web App: `https://coscircle.xxx/app/`

The deploy script builds the user web app and the independent admin web entry
locally, uploads the API and web release, imports `schema.sql` when the
database is empty, restarts systemd, reloads Nginx, and checks `/api/health`.

For an existing database that predates other features, apply the non-idempotent
migrations manually in the order listed in `production-checklist.md` before
running a public release. The VM app user intentionally does not receive stored
routine privileges.

## 4. Verify

```sh
BASE_URL=http://EXTERNAL_IP deploy/gcp/verify-deployment.sh
```

The verification script checks `/api/health`, the web entry point, and the API
privacy smoke test.

## 5. HTTPS

For a real public launch, point a domain A record to the VM external IP, then
install Certbot on the VM and issue a certificate:

```sh
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.example.com
```

After HTTPS is active, redeploy web with:

```sh
WEB_SERVER_NAME=coscircle.xxx \
ADMIN_SERVER_NAME=admin.coscircle.xxx \
APP_API_BASE_URL=https://coscircle.xxx/api \
ADMIN_API_BASE_URL=https://admin.coscircle.xxx/api \
API_BASE_URL=https://coscircle.xxx/api
```

Also update `/etc/coscircle/api.env` so `CORS_ORIGINS` includes both HTTPS
origins, then restart the API:

```sh
sudo systemctl restart coscircle-api
```

## 6. Backups and cost controls

Set a budget alert in Cloud Billing before public traffic.

Minimal backup command on the VM:

```sh
sudo mkdir -p /var/backups/coscircle
set -a && . /etc/coscircle/api.env && set +a
MYSQL_PWD="$MYSQL_PASSWORD" mysqldump -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DATABASE" \
  | gzip | sudo tee "/var/backups/coscircle/coscircle-$(date +%Y%m%d%H%M%S).sql.gz" >/dev/null
sudo tar -czf "/var/backups/coscircle/uploads-$(date +%Y%m%d%H%M%S).tar.gz" \
  /var/lib/coscircle/uploads
```

For a stronger setup, copy backups to a Cloud Storage bucket in a Free Tier
eligible US region, while watching the 5 GB-month storage limit.
