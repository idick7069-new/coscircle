#!/usr/bin/env bash
# Root VM contract: EXPECTED_FEATURE_SHA256=<sha> EXPECTED_WEB_SHA256=<sha>
# bash deploy-partner-discovery-on-vm.sh feature.tar.gz user-web.tar.gz
# Feature members must be exactly src/same-works.js and src/partner-discovery.js.
# Web members must be app/ files and directories, including index.html and main.dart.js.
set +x
set -Eeuo pipefail
umask 077
die() { printf '%s\n' "$*" >&2; exit 1; }
[[ $EUID == 0 ]] || die 'Run as root on the VM.'
[[ $# == 2 ]] || die 'Pass feature.tar.gz and user-web.tar.gz with both expected SHA256 variables.'
[[ ${EXPECTED_FEATURE_SHA256:-} =~ ^[a-f0-9]{64}$ ]] || die 'EXPECTED_FEATURE_SHA256 is required.'
[[ ${EXPECTED_WEB_SHA256:-} =~ ^[a-f0-9]{64}$ ]] || die 'EXPECTED_WEB_SHA256 is required.'
for tool in flock readlink sha256sum python3 node mysql mysqldump gzip tar timeout curl systemctl cp mv install stat mktemp chmod mkdir ln rm sleep; do
  command -v "$tool" >/dev/null || die "Missing $tool"
done
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9 || die 'Another API deployment holds the lock.'
CURRENT=/opt/coscircle/api/current
WEB_CURRENT=/var/www/coscircle/current
EXPECTED_API=/opt/coscircle/api/releases/legal-igJDhIwJ
EXPECTED_WEB=/var/www/coscircle/releases/20261028095204
SERVER_SHA=b793f8bbea65fc4e1b2be3518dc0c2cc498e6eeb500f29f1bdab5b2e0b2dc1d4
SAME_WORK_SHA=aa6bf9761a43cd55389923762a274dba938acd54b2c703bed64c2c4e1d867bd7
hash() { local value; value=$(sha256sum -- "$1"); printf '%s' "${value%% *}"; }
verify_active() {
  [[ -L $CURRENT && -L $WEB_CURRENT ]] || die 'Both current paths must be symlinks.'
  [[ $(readlink -f -- "$CURRENT") == "$EXPECTED_API" && $(readlink -f -- "$WEB_CURRENT") == "$EXPECTED_WEB" ]] || die 'Active release drift.'
  [[ -d $EXPECTED_API && -d $EXPECTED_WEB && ! -L $EXPECTED_API && ! -L $EXPECTED_WEB ]] || die 'Unexpected release directory.'
  [[ -d $EXPECTED_API/src && ! -L $EXPECTED_API/src ]] || die 'Unexpected API src directory.'
  for name in server.js same-works.js; do
    [[ -f $EXPECTED_API/src/$name && ! -L $EXPECTED_API/src/$name ]] || die 'Unexpected source path.'
  done
  [[ $(hash "$EXPECTED_API/src/server.js") == "$SERVER_SHA" ]] || die 'Server source drift.'
  [[ $(hash "$EXPECTED_API/src/same-works.js") == "$SAME_WORK_SHA" ]] || die 'Same-work source drift.'
  [[ ! -e $EXPECTED_API/src/partner-discovery.js && ! -L $EXPECTED_API/src/partner-discovery.js ]] || die 'Partner module already exists.'
  [[ -L $EXPECTED_API/uploads && -d $EXPECTED_API/uploads ]] || die 'Expected shared uploads symlink.'
  [[ -d $EXPECTED_API/node_modules && -d $EXPECTED_API/.crawler-venv ]] || die 'Existing runtime dependencies are required.'
  [[ -d $EXPECTED_WEB/app && ! -L $EXPECTED_WEB/app ]] || die 'Unexpected active app directory.'
}
verify_active
OLD_API=$(readlink -f -- "$CURRENT")
OLD_WEB=$(readlink -f -- "$WEB_CURRENT")
UPLOADS=$(readlink -f -- "$OLD_API/uploads")
[[ -f /etc/coscircle/api.env && ! -L /etc/coscircle/api.env ]] || die 'Missing protected API environment.'
[[ $(stat -c %u /etc/coscircle/api.env) == 0 ]] || die 'API environment must be root-owned.'
ENV_MODE=$(stat -c %a /etc/coscircle/api.env)
(( (8#$ENV_MODE & 07137) == 0 )) || die 'API environment has unsafe permissions.'
if (( (8#$ENV_MODE & 040) != 0 )); then
  [[ $(stat -c %G /etc/coscircle/api.env) == coscircle ]] || die 'Only group coscircle may read the API environment.'
fi
[[ ! -L /var/backups/coscircle ]] || die 'Backup root must not be a symlink.'
install -d -o root -g root -m 0700 /var/backups/coscircle
BACKUP=$(mktemp -d /var/backups/coscircle/partner-XXXXXXXX)
mkdir -m 0700 "$BACKUP/feature" "$BACKUP/web"
for archive in "$1" "$2"; do
  [[ -f $archive && ! -L $archive ]] || die 'Archives must be regular non-symlink files.'
  (( $(stat -c %s -- "$archive") <= 268435456 )) || die 'Compressed archive exceeds 256 MiB.'
done
install -m 0600 -- "$1" "$BACKUP/feature.tar.gz"
install -m 0600 -- "$2" "$BACKUP/web.tar.gz"
[[ $(hash "$BACKUP/feature.tar.gz") == "$EXPECTED_FEATURE_SHA256" ]] || die 'Feature archive SHA256 mismatch.'
[[ $(hash "$BACKUP/web.tar.gz") == "$EXPECTED_WEB_SHA256" ]] || die 'Web archive SHA256 mismatch.'
for kind in feature web; do
  timeout 60 gzip -t -- "$BACKUP/$kind.tar.gz"
  timeout 120 python3 - "$kind" "$BACKUP/$kind.tar.gz" "$BACKUP/$kind" <<'PY'
import pathlib, sys, tarfile
kind, source, destination = sys.argv[1:]
allowed = {'src/same-works.js', 'src/partner-discovery.js'}
seen, files, members, total = set(), set(), [], 0
with tarfile.open(source, 'r:gz') as archive:
    for member in archive:
        name = member.name.rstrip('/') if member.isdir() else member.name
        path = pathlib.PurePosixPath(name)
        if (not name or name != str(path) or path.is_absolute()
                or any(part in ('.', '..') for part in path.parts)
                or '\\' in name or any(ord(c) < 32 or ord(c) == 127 for c in name)
                or name in seen or member.issparse()
                or not (member.isfile() or (kind == 'web' and member.isdir()))):
            raise SystemExit('Unsafe, duplicate, or linked archive member')
        if kind == 'feature' and name not in allowed:
            raise SystemExit('Feature archive exceeds exact JS whitelist')
        if kind == 'web' and (path.parts[0] != 'app' or (len(path.parts) == 1 and not member.isdir())):
            raise SystemExit('Web archive may contain only app/ files and directories')
        maximum = 4 * 1024 * 1024 if kind == 'feature' else 64 * 1024 * 1024
        total += member.size
        if member.size < 0 or member.size > maximum or total > 512 * 1024 * 1024 or len(seen) >= 20000:
            raise SystemExit('Archive size or member limit exceeded')
        seen.add(name)
        if member.isfile():
            files.add(name)
        members.append((name, member))
    if kind == 'feature' and files != allowed:
        raise SystemExit('Feature archive must contain exactly both JS files')
    if kind == 'web' and not {'app/index.html', 'app/main.dart.js'} <= files:
        raise SystemExit('Web archive lacks required Flutter entrypoints')
    for name, member in members:
        if any(str(parent) in files for parent in pathlib.PurePosixPath(name).parents):
            raise SystemExit('Archive file/directory conflict')
        if member.isfile() and name in {'src/same-works.js', 'src/partner-discovery.js', 'app/index.html', 'app/main.dart.js'} and member.size == 0:
            raise SystemExit('Required file is empty')
    for name, member in members:
        target = pathlib.Path(destination) / name
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if member.isdir():
            target.mkdir(mode=0o700, exist_ok=True)
        else:
            with archive.extractfile(member) as incoming, target.open('xb') as output:
                remaining = member.size
                while remaining:
                    block = incoming.read(min(remaining, 1024 * 1024))
                    if not block:
                        raise SystemExit('Truncated archive member')
                    output.write(block)
                    remaining -= len(block)
PY
done
printf '%s\n' "$OLD_API" > "$BACKUP/api-path"
printf '%s\n' "$OLD_WEB" > "$BACKUP/web-path"
printf '%s\n' "$SERVER_SHA" "$SAME_WORK_SHA" > "$BACKUP/source-before.sha256"
# Refuse nontransactional tables rather than claim a consistent partial snapshot.
MYSQL_SERVER_UUID=$(timeout 20 mysql --protocol=SOCKET --batch --skip-column-names coscircle -e 'SELECT @@server_uuid')
[[ $MYSQL_SERVER_UUID =~ ^[a-fA-F0-9-]{36}$ ]] || die 'Cannot identify backup MySQL server.'
ENGINES=$(timeout 20 mysql --protocol=SOCKET --batch --skip-column-names coscircle -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'coscircle' AND table_type = 'BASE TABLE' AND engine <> 'InnoDB'")
[[ $ENGINES == 0 ]] || die 'Full database snapshot requires only InnoDB tables.'
timeout 600 mysqldump --single-transaction --protocol=SOCKET --routines --triggers --events --hex-blob --no-tablespaces coscircle 2> "$BACKUP/dump.stderr" | gzip > "$BACKUP/coscircle.sql.gz"
gzip -t "$BACKUP/coscircle.sql.gz"
timeout 60 tar -czf "$BACKUP/config.tar.gz" -C / etc/coscircle etc/nginx
gzip -t "$BACKUP/config.tar.gz"
timeout 20 systemctl cat coscircle-api > "$BACKUP/coscircle-api.unit"
API=$(mktemp -d /opt/coscircle/api/releases/partner-XXXXXXXX)
WEB=$(mktemp -d /var/www/coscircle/releases/partner-XXXXXXXX)
cp -a -- "$OLD_API/." "$API/"
cp -a -- "$OLD_WEB/." "$WEB/"
chmod --reference="$OLD_API" "$API"
chmod --reference="$OLD_WEB" "$WEB"
[[ -L $API/uploads && $(readlink -f -- "$API/uploads") == "$UPLOADS" ]] || die 'Clone changed uploads target.'
for name in same-works.js partner-discovery.js; do
  [[ ! -L $API/src/$name ]] || die 'Refusing linked overlay target.'
  rm -f -- "$API/src/$name"
  install -m 0644 -o "$(stat -c %u "$OLD_API/src/same-works.js")" -g "$(stat -c %g "$OLD_API/src/same-works.js")" "$BACKUP/feature/src/$name" "$API/src/$name"
  node --check "$API/src/$name"
done
[[ $(hash "$API/src/server.js") == "$SERVER_SHA" ]] || die 'Candidate server changed.'
rm -rf -- "$WEB/app"
cp -a -- "$BACKUP/web/app" "$WEB/app"
python3 - "$WEB/app" <<'PY'
import os, pathlib, sys
root = pathlib.Path(sys.argv[1])
os.chmod(root, 0o755)
for path in root.rglob('*'):
    os.chmod(path, 0o755 if path.is_dir() else 0o644)
PY
if ! timeout 90 node --input-type=module - "$API" "$MYSQL_SERVER_UUID" > "$BACKUP/compatibility.log" 2>&1 <<'JS'
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const api = process.argv[2];
const require = createRequire(`${api}/package.json`);
let pool, connection;
try {
  const loaded = require('dotenv').config({path: '/etc/coscircle/api.env', override: true});
  if (loaded.error) throw new Error('environment');
  if ((process.env.MYSQL_DATABASE ?? 'coscircle') !== 'coscircle' || !['127.0.0.1', 'localhost'].includes(process.env.MYSQL_HOST ?? '127.0.0.1') || Number(process.env.MYSQL_PORT ?? 3306) !== 3306) throw new Error('backup database mismatch');
  const {createPool} = await import(pathToFileURL(`${api}/src/db.js`));
  const {listPartnerWorks, listWorkPartners} = await import(pathToFileURL(`${api}/src/partner-discovery.js`));
  pool = createPool();
  connection = await pool.getConnection();
  await connection.query('SET SESSION TRANSACTION READ ONLY');
  await connection.beginTransaction();
  const [[identity]] = await connection.execute('SELECT @@server_uuid AS serverUuid, DATABASE() AS databaseName');
  if (identity.serverUuid !== process.argv[3] || identity.databaseName !== 'coscircle') throw new Error('backup server mismatch');
  const [fixtures] = await connection.execute(`SELECT u.id FROM users u
    INNER JOIN user_auth_identities a ON a.user_id = u.id
    WHERE u.id = 17 AND u.account_status = 'active' AND a.provider = 'email'
      AND LOWER(u.email) LIKE '%@example.invalid'
      AND BINARY a.provider_user_id = BINARY u.email`);
  if (fixtures.length !== 1) throw new Error('exact QA17 email identity required');
  const viewer = fixtures[0].id;
  const readonly = {execute(sql, params) {
    if (!/^\s*SELECT\b/i.test(sql) || sql.includes(';')) throw new Error('SELECT only');
    return connection.execute(sql, params);
  }};
  const check = value => {
    if (!value || !Array.isArray(value.items) || typeof value.hasMore !== 'boolean') throw new Error('page contract');
    return value;
  };
  check(await listPartnerWorks(readonly, viewer, {scope: 'mine', limit: '1', offset: '0'}));
  check(await listPartnerWorks(readonly, viewer, {scope: 'all', q: '%_!', limit: '1', offset: '0'}));
  const all = check(await listPartnerWorks(readonly, viewer, {scope: 'all', limit: '1', offset: '0'}));
  if (!all.items.length) throw new Error('partner fixture required to exercise join branch');
  const [works] = await readonly.execute('SELECT id FROM works ORDER BY id LIMIT 1');
  if (!works.length) throw new Error('work fixture required');
  const partners = check(await listWorkPartners(readonly, viewer, String(all.items[0]?.id ?? works[0].id), {limit: '1', offset: '0'}));
  if (all.items.length && !partners.items.length) throw new Error('partner join branch not exercised');
  await connection.rollback();
  console.log('Candidate SELECT compatibility passed. No result rows or credentials logged.');
} catch {
  console.error('Candidate read-only compatibility failed. Parent must verify fixture, schema and candidate queries before deployment.');
  process.exitCode = 1;
} finally {
  if (connection) { try { await connection.rollback(); } catch {} connection.release(); }
  if (pool) await pool.end();
}
JS
then
  die "Candidate DB compatibility failed before switch. Parent must verify. Root-only details: $BACKUP/compatibility.log"
fi
verify_active
[[ -f $OLD_WEB/app/main.dart.js && ! -L $OLD_WEB/app/main.dart.js ]] || die 'Missing old Web entrypoint.'
OLD_WEB_SHA256=$(hash "$OLD_WEB/app/main.dart.js")
timeout 10 systemctl is-active --quiet coscircle-api
curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:8080/api/health > "$BACKUP/old-health.json"
python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); sys.exit(not (v.get("ok") is True and v.get("name") == "CosCircle API"))' "$BACKUP/old-health.json"
SWITCH_LINK="$API.current-link"
WEB_SWITCH_LINK="$WEB.current-link"
rollback() {
  local status=$?
  trap - EXIT ERR INT TERM HUP
  set +e
  timeout 5 rm -f -- "$SWITCH_LINK" "$WEB_SWITCH_LINK"
  timeout 5 ln -s -- "$OLD_API" "$SWITCH_LINK" && timeout 5 mv -Tf -- "$SWITCH_LINK" "$CURRENT"
  local api_restored=$?
  timeout 5 ln -s -- "$OLD_WEB" "$WEB_SWITCH_LINK" && timeout 5 mv -Tf -- "$WEB_SWITCH_LINK" "$WEB_CURRENT"
  local web_restored=$?
  timeout 60 systemctl restart coscircle-api
  local restarted=$?
  local recovered=false attempt served_hash
  for ((attempt=0; attempt<10; attempt++)); do
    if (( api_restored == 0 && web_restored == 0 && restarted == 0 )) &&
      [[ -L $CURRENT && -L $WEB_CURRENT ]] &&
      [[ $(timeout 5 readlink -f -- "$CURRENT") == "$OLD_API" && $(timeout 5 readlink -f -- "$WEB_CURRENT") == "$OLD_WEB" ]] &&
      timeout 10 systemctl is-active --quiet coscircle-api &&
      curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:8080/api/health > "$BACKUP/restored-health.json" 2>/dev/null &&
      timeout 5 python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])))' "$BACKUP/old-health.json" "$BACKUP/restored-health.json" &&
      curl --noproxy '*' -fsS --connect-timeout 2 --max-time 15 --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/main.dart.js -o "$BACKUP/restored-main.dart.js" &&
      served_hash=$(timeout 5 sha256sum -- "$BACKUP/restored-main.dart.js") &&
      [[ ${served_hash%% *} == "$OLD_WEB_SHA256" ]] &&
      timeout 10 systemctl is-active --quiet coscircle-api &&
      [[ -L $CURRENT && -L $WEB_CURRENT ]] &&
      [[ $(timeout 5 readlink -f -- "$CURRENT") == "$OLD_API" && $(timeout 5 readlink -f -- "$WEB_CURRENT") == "$OLD_WEB" ]]; then
      recovered=true
      break
    fi
    sleep 1
  done
  printf 'Deployment failed (%s). Rollback API=%s Web=%s restart=%s. Root-only backup: %s\n' "$status" "$api_restored" "$web_restored" "$restarted" "$BACKUP" >&2
  if [[ $recovered == true ]]; then
    printf '%s\n' 'Recovery verified: old API health, active service, served Web hash and both symlinks restored.' >&2
  else
    printf 'RECOVERY FAILED. Inspect service, health, served Web and both symlinks. Root-only backup: %s\n' "$BACKUP" >&2
  fi
  exit 1
}
trap rollback EXIT
trap 'exit 1' ERR INT TERM HUP
ln -s -- "$API" "$SWITCH_LINK"
mv -Tf -- "$SWITCH_LINK" "$CURRENT"
ln -s -- "$WEB" "$WEB_SWITCH_LINK"
mv -Tf -- "$WEB_SWITCH_LINK" "$WEB_CURRENT"
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
[[ $healthy == true ]] || die 'Health check failed.'
for route in partner-works partner-works/1/users; do
  code=$(curl --noproxy '*' -sS --connect-timeout 1 --max-time 3 -o "$BACKUP/unauth.json" -w '%{http_code}' "http://127.0.0.1:8080/api/social/$route")
  [[ $code == 401 ]] || die 'New route must reject unauthenticated GET.'
  python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("error") != "authentication_required")' "$BACKUP/unauth.json"
done
curl --noproxy '*' -fsS --connect-timeout 2 --max-time 15 --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/main.dart.js -o "$BACKUP/served-main.dart.js"
[[ $(hash "$BACKUP/served-main.dart.js") == "$(hash "$WEB/app/main.dart.js")" ]] || die 'Served app hash mismatch.'
timeout 10 systemctl is-active --quiet coscircle-api
[[ $(readlink -f -- "$CURRENT") == "$API" && $(readlink -f -- "$WEB_CURRENT") == "$WEB" ]] || die 'Post-switch release drift.'
trap - EXIT ERR INT TERM HUP
printf 'Partner-only API: %s\nUser app release: %s\nPrevious API: %s\nPrevious Web: %s\nRoot-only backup: %s\nParent must run authenticated smoke separately.\n' "$API" "$WEB" "$OLD_API" "$OLD_WEB" "$BACKUP"
