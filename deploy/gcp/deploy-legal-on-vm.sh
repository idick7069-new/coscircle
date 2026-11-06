#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
die() { printf '%s\n' "$*" >&2; exit 1; }
[[ $EUID == 0 ]] || die 'Run as root on the VM.'
[[ $# == 1 ]] || die 'Usage: EXPECTED_API_RELEASE=<basename> deploy-legal-on-vm.sh reviewed-overlay.tar.gz (or EXPECTED_SOURCE_SHA256=<sha256>)'
[[ -n ${EXPECTED_API_RELEASE:-}${EXPECTED_SOURCE_SHA256:-} ]] || die 'Expected release or source hash is required.'
[[ ${EXPECTED_OVERLAY_SHA256:-} =~ ^[a-f0-9]{64}$ ]] || die 'Expected reviewed overlay SHA256 is required.'
for tool in flock readlink sha256sum python3 node mysql mysqldump gzip tar timeout curl systemctl cp mv install stat mktemp chmod mkdir ln rm sleep; do
  command -v "$tool" >/dev/null || die "Missing $tool"
done
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9 || die 'Another API deployment holds the lock.'
CURRENT=/opt/coscircle/api/current
[[ -L $CURRENT ]] || die 'current must be a symlink.'
OLD_API="$(readlink -f -- "$CURRENT")"
[[ $OLD_API == /opt/coscircle/api/releases/* && -d $OLD_API ]] || die 'Unexpected active release path.'
[[ -z ${EXPECTED_API_RELEASE:-} || ${OLD_API##*/} == "$EXPECTED_API_RELEASE" ]] || die 'Active release drift.'
[[ -f $OLD_API/src/server.js && ! -L $OLD_API/src && ! -L $OLD_API/src/server.js ]] || die 'Unexpected server path.'
SOURCE_HASH="$(sha256sum "$OLD_API/src/server.js")"
SOURCE_HASH="${SOURCE_HASH%% *}"
if [[ -n ${EXPECTED_SOURCE_SHA256:-} ]]; then
  [[ $EXPECTED_SOURCE_SHA256 =~ ^[a-f0-9]{64}$ && $SOURCE_HASH == "$EXPECTED_SOURCE_SHA256" ]] || die 'Server source drift.'
fi
[[ -L $OLD_API/uploads ]] || die 'Expected shared uploads symlink.'
UPLOADS="$(readlink -f -- "$OLD_API/uploads")"
[[ -d $UPLOADS ]] || die 'Shared uploads target missing.'
[[ ! -L $OLD_API/db && -d $OLD_API/db ]] || die 'Unexpected db directory.'
[[ ! -e $OLD_API/src/legal-consent.js && ! -L $OLD_API/src/legal-consent.js ]] || die 'Legal module already exists.'
[[ ! -e $OLD_API/db/migrate_legal_consent.sql && ! -L $OLD_API/db/migrate_legal_consent.sql ]] || die 'Legal migration already exists.'
install -d -m 0700 /var/backups/coscircle
BACKUP="$(mktemp -d /var/backups/coscircle/legal-XXXXXXXX)"
STAGE="$BACKUP/overlay"
mkdir -m 0700 "$STAGE"
[[ -f $1 && ! -L $1 ]] || die 'Overlay must be a regular non-symlink file.'
OVERLAY="$BACKUP/reviewed-overlay.tar.gz"
install -m 0600 -- "$1" "$OVERLAY"
OVERLAY_HASH="$(sha256sum "$OVERLAY")"
[[ ${OVERLAY_HASH%% *} == "$EXPECTED_OVERLAY_SHA256" ]] || die 'Reviewed overlay hash mismatch.'
timeout 60 gzip -t -- "$OVERLAY"

# Read only regular whitelist members; never let tar resolve archive paths on disk.
python3 - "$OVERLAY" "$STAGE" <<'PY'
import pathlib, re, sys, tarfile
allowed = {'src/server.js', 'src/legal-consent.js', 'db/migrate_legal_consent.sql'}
expected_sql = '''CREATE TABLE IF NOT EXISTS user_legal_consents (
  user_id BIGINT UNSIGNED NOT NULL,
  version VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  accepted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, version),
  CONSTRAINT fk_legal_consent_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);'''
files = {}
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive:
        if member.name not in allowed or member.name in files or not member.isfile() or not 0 < member.size <= 4 * 1024 * 1024:
            raise SystemExit('Unexpected, duplicate, linked, or oversized overlay member: ' + member.name)
        files[member.name] = archive.extractfile(member).read()
if set(files) != allowed:
    raise SystemExit('Overlay must contain exactly the three whitelist files, without directory entries')
if re.sub(r'\s+', ' ', files['db/migrate_legal_consent.sql'].decode()).strip() != re.sub(r'\s+', ' ', expected_sql).strip():
    raise SystemExit('Only the reviewed additive consent-table CREATE statement is permitted')
for name, data in files.items():
    target = pathlib.Path(sys.argv[2]) / name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with target.open('xb') as output:
        output.write(data)
PY
node --input-type=module - "$OLD_API/src/server.js" "$STAGE/src/server.js" <<'JS'
import {readFileSync} from 'node:fs';
// BEGIN standalone transform
const legalImport = "import { createLegalService, registerLegalRoutes } from './legal-consent.js';\n";
const legalMount = 'registerLegalRoutes(app, createLegalService(pool));\n\n';
const legalCheck = "await pool.execute('SELECT user_id, version, accepted_at FROM user_legal_consents LIMIT 0');\n";

const auth = `app.use(async (req, _res, next) => {
  try {
    if (req.path.startsWith('/api/profiles/')) {
      next();
      return;
    }
    req.userId = await resolveUserId(req);
    if (!req.userId) {
      _res.status(401).json({ error: 'authentication_required' });
      return;
    }
    next();
  } catch (error) {
    next(error);
  }
});

`;
const me = "app.get('/api/me', async (req, res, next) => {";
const importAnchor = "import { createPool } from './db.js';\n";
const startup = 'await ensureAuthIdentities(pool);\n';
const listen = 'app.listen(port, () => {';

function patchLegalServer(source) {
  if (typeof source !== 'string') throw new TypeError('Expected server source string');
  if (/legal-consent|createLegalService|registerLegalRoutes|user_legal_consents/.test(source)) {
    throw new Error('Server already contains legal code');
  }
  for (const [name, anchor] of Object.entries({importAnchor, auth, me, startup, listen})) {
    if (source.split(anchor).length !== 2) throw new Error(`Missing or ambiguous ${name} anchor`);
  }
  if (!source.includes(auth + me) || source.indexOf(importAnchor) > source.indexOf(auth) ||
      source.indexOf(me) > source.indexOf(startup) || source.indexOf(startup) > source.indexOf(listen)) {
    throw new Error('Unexpected auth or startup boundary');
  }
  return source.replace(importAnchor, importAnchor + legalImport)
    .replace(auth + me, auth + legalMount + me)
    .replace(startup, legalCheck + startup);
}
// END standalone transform
const expected = Buffer.from(patchLegalServer(readFileSync(process.argv[2], 'utf8')));
if (!expected.equals(readFileSync(process.argv[3]))) throw new Error('Overlay server is not the exact legal-only patch');
JS
node --input-type=module --check < "$STAGE/src/server.js"
node --input-type=module --check < "$STAGE/src/legal-consent.js"
printf '%s\n' "$OLD_API" > "$BACKUP/api-path"
printf '%s\n' "$SOURCE_HASH" > "$BACKUP/server-before.sha256"
timeout 600 mysqldump --single-transaction --routines --triggers --events --hex-blob --no-tablespaces coscircle | gzip > "$BACKUP/coscircle.sql.gz"
gzip -t "$BACKUP/coscircle.sql.gz"
timeout 600 tar -czf "$BACKUP/uploads.tar.gz" -C "$UPLOADS" .
gzip -t "$BACKUP/uploads.tar.gz"
tar -tzf "$BACKUP/uploads.tar.gz" >/dev/null
timeout 60 tar -czf "$BACKUP/config.tar.gz" -C / etc/coscircle
gzip -t "$BACKUP/config.tar.gz"
timeout 20 systemctl cat coscircle-api > "$BACKUP/coscircle-api.unit"
chmod 0600 "$BACKUP/"*.gz "$BACKUP/coscircle-api.unit"
API="$(mktemp -d /opt/coscircle/api/releases/legal-XXXXXXXX)"
cp -a "$OLD_API/." "$API/"
[[ -L $API/uploads && $(readlink -f -- "$API/uploads") == "$UPLOADS" ]] || die 'Clone changed shared uploads target.'
for name in src/server.js src/legal-consent.js db/migrate_legal_consent.sql; do
  [[ ! -L $API/$name ]] || die "Unexpected symlink $name"
done
cp -- "$STAGE/src/server.js" "$API/src/server.js"
for name in src/legal-consent.js db/migrate_legal_consent.sql; do
  [[ ! -e $API/$name ]] || die "Refusing to overwrite $name"
  install -m 0644 -o "$(stat -c %u "$OLD_API/src/server.js")" -g "$(stat -c %g "$OLD_API/src/server.js")" "$STAGE/$name" "$API/$name"
done
node --check "$API/src/server.js"
node --check "$API/src/legal-consent.js"
[[ $(readlink -f -- "$CURRENT") == "$OLD_API" ]] || die 'current changed during staging.'
LATEST_HASH="$(sha256sum "$OLD_API/src/server.js")"
[[ ${LATEST_HASH%% *} == "$SOURCE_HASH" ]] || die 'Source changed during staging.'
timeout 60 mysql coscircle < "$API/db/migrate_legal_consent.sql"
timeout 20 mysql coscircle -e 'SELECT user_id, version, accepted_at FROM user_legal_consents LIMIT 0'
SWITCH_LINK="$API.current-link"
rollback() {
  local status=$?
  trap - ERR INT TERM
  set +e
  rm -f -- "$SWITCH_LINK"
  ln -s -- "$OLD_API" "$SWITCH_LINK" && mv -Tf -- "$SWITCH_LINK" "$CURRENT"
  local restored=$?
  timeout 60 systemctl restart coscircle-api
  local restarted=$?
  printf 'Deployment failed (%s). Rollback symlink=%s restart=%s. Additive table retained. Backup: %s\n' "$status" "$restored" "$restarted" "$BACKUP" >&2
  exit 1
}
trap rollback ERR INT TERM
ln -s -- "$API" "$SWITCH_LINK"
mv -Tf -- "$SWITCH_LINK" "$CURRENT"
timeout 60 systemctl restart coscircle-api
healthy=false
for ((attempt=0; attempt<30; attempt++)); do
  if curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:8080/api/health > "$BACKUP/health.json" 2>/dev/null; then
    if python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); sys.exit(not (v.get("ok") is True and v.get("name") == "CosCircle API"))' "$BACKUP/health.json"; then
      healthy=true
      break
    fi
  fi
  sleep 1
done
[[ $healthy == true ]] || rollback
for method in GET POST; do
  code="$(curl --noproxy '*' -sS --connect-timeout 1 --max-time 3 -X "$method" -o "$BACKUP/legal-$method.json" -w '%{http_code}' http://127.0.0.1:8080/api/me/legal)"
  [[ $code == 401 ]] || rollback
  python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("error") != "authentication_required")' "$BACKUP/legal-$method.json"
done
timeout 10 systemctl is-active --quiet coscircle-api
[[ $(readlink -f -- "$CURRENT") == "$API" ]] || rollback
trap - ERR INT TERM
printf 'Legal-only release: %s\nPrevious release: %s\nRoot-only backup: %s\n' "$API" "$OLD_API" "$BACKUP"
