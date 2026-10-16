# coscircle.app production domain

Activated on 2026-10-13. This is the existing production GCP VM, not staging.

## Entry points

- Website: https://coscircle.app/
- Flutter app: https://coscircle.app/app/
- Admin: https://coscircle.app/admin/
- API: https://coscircle.app/api/
- Existing IP HTTPS remains available to installed Android clients.
- `www.coscircle.app` is not configured; only the apex domain is supported.

Cloudflare DNS: apex A record `34.187.168.222`, DNS only, automatic TTL.
Leave the proxy disabled until a separate proxy configuration review. Domain
activation does not configure email sending or native app/universal links.

## TLS and nginx

- Domain certificate: `/etc/letsencrypt/live/coscircle.app/`.
- IP certificate: `/etc/letsencrypt/live/coscircle-ip/`.
- Domain vhosts: `/etc/nginx/coscircle-extra/coscircle.app.conf`.
- Main vhost: `/etc/nginx/sites-available/coscircle`.
- Main IP listener must be `listen 443 ssl default_server;`: IP clients commonly
  do not send TLS SNI and must not receive the domain-only certificate.
- Domain HTTP redirects to HTTPS, except the ACME validation location.
- Existing `coscircle-cert-renew.timer` renews both certificates. Its deploy
  hook validates nginx and reloads it. ACME webroot is `/var/lib/coscircle/acme`.
- nginx template includes the persistent extra vhost directory, so full
  deployments do not erase the domain configuration.

For subsequent full `deploy-vm.sh` deployments, retain the IP as the primary
vhost, and supply the domain URLs to frontend builds:

```sh
VM_NAME=coscircle-free-vm \
ZONE=us-west1-b \
GCP_PROJECT=cos-circle \
GCP_ACCOUNT=YOUR_AUTHORIZED_GCP_ACCOUNT \
WEB_SERVER_NAME=34.187.168.222 \
API_BASE_URL=https://coscircle.app/api \
PUBLIC_APP_URL=https://coscircle.app/app \
TLS_CERT_PATH=/etc/letsencrypt/live/coscircle-ip/fullchain.pem \
TLS_KEY_PATH=/etc/letsencrypt/live/coscircle-ip/privkey.pem \
ENABLE_LINE_LOGIN=true \
RUN_MIGRATIONS=false \
deploy/gcp/deploy-vm.sh
```

Do not set `WEB_SERVER_NAME=coscircle.app` with this layout: the persistent
domain vhost already owns that hostname and uses its separate certificate.
Do not replace the primary IP certificate with the domain certificate.

## Backend and clients

`/etc/coscircle/api.env` retains existing CORS origins and adds
`https://coscircle.app`; `PUBLIC_APP_URL` is `https://coscircle.app/app`.
No database migration or backend code release was needed.

Web app and admin builds now use `https://coscircle.app/api`. The app build
also sets `PUBLIC_APP_URL=https://coscircle.app/app`. Future native builds
should use these two defines; installed IP-based clients do not require an
immediate update. Browser sessions are per-origin, so users may need to sign
in again when opening the new domain.

## Activation and rollback

`deploy/gcp/activate-domain.sh` is run as root on the VM after certificate
issuance. It accepts a trusted web archive containing `app/` and `admin/`,
clones the old web release, backs up nginx/environment files, and keeps the
API release unchanged. Failed activation restores settings and the web
symlink automatically. It does not restore or modify database data.

Successful activation backup: `/var/backups/coscircle-domain-iQBdSro3`.
Web release: `/var/www/coscircle/releases/20261013T022929Z-domain`.
API release unchanged: `/opt/coscircle/api/releases/20261012114258`.
Previous web release: `/var/www/coscircle/releases/20261012T081759Z-logo-animation`.

The first activation failed the IP certificate check and automatically rolled
back. The successful retry explicitly preserves the IP default TLS server.

## Validation

- Public HTTPS website, app, admin and API health return 200.
- HTTP domain redirects to HTTPS (301).
- Domain CORS preflight returns 204 with the exact allowed origin.
- IP HTTPS API remains valid and healthy.
- Domain certificate renewal dry-run succeeds; renewal timer is active.
- Browser renders the app login screen without observed console errors.
- Flutter analysis and 18 focused auth/logo/LINE tests pass.
- No user accounts, invitations or activity data were created during tests.
