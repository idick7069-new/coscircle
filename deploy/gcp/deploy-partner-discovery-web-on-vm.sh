#!/usr/bin/env bash
set +x
set -Eeuo pipefail
umask 077
[[ $EUID == 0 && $# == 1 && ${EXPECTED_WEB_SHA256:-} =~ ^[a-f0-9]{64}$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
CURRENT=/var/www/coscircle/current
OLD=/var/www/coscircle/releases/partner-m4JWqyIo
API=/opt/coscircle/api/releases/partner-XnNVruDQ
[[ $(readlink -f "$CURRENT") == "$OLD" && $(readlink -f /opt/coscircle/api/current) == "$API" ]]
hash() { local value; value=$(sha256sum -- "$1"); printf '%s' "${value%% *}"; }
OLD_HASH=$(hash "$OLD/app/main.dart.js")
BACKUP=$(mktemp -d /var/backups/coscircle/partner-ui-XXXXXXXX)
install -m 0600 "$1" "$BACKUP/web.tar.gz"
[[ $(hash "$BACKUP/web.tar.gz") == "$EXPECTED_WEB_SHA256" ]]
NEW=$(mktemp -d /var/www/coscircle/releases/partner-ui-XXXXXXXX)
cp -a "$OLD/." "$NEW/"
chmod --reference="$OLD" "$NEW"
rm -rf -- "$NEW/app"
timeout 120 python3 - "$BACKUP/web.tar.gz" "$NEW" <<'PY'
import pathlib, sys, tarfile
seen, total = set(), 0
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    members = archive.getmembers()
    for item in members:
        path = pathlib.PurePosixPath(item.name)
        total += item.size
        if (not item.isfile() or item.issparse() or item.name != str(path)
                or path.is_absolute() or len(path.parts) < 2 or path.parts[0] != 'app'
                or '..' in path.parts or '\\' in item.name or item.name in seen
                or item.size < 0 or item.size > 64*1024*1024 or total > 512*1024*1024):
            raise SystemExit('Invalid Web archive')
        seen.add(item.name)
    if len(members) > 20000 or not {'app/index.html', 'app/main.dart.js'} <= seen:
        raise SystemExit('Missing Web entrypoint')
    for item in members:
        target = pathlib.Path(sys.argv[2]) / item.name
        target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        with archive.extractfile(item) as incoming, target.open('xb') as output:
            while chunk := incoming.read(1024*1024):
                output.write(chunk)
        target.chmod(0o644)
    for directory in (pathlib.Path(sys.argv[2]) / 'app').rglob('*'):
        if directory.is_dir():
            directory.chmod(0o755)
    (pathlib.Path(sys.argv[2]) / 'app').chmod(0o755)
PY
served_matches() {
  curl --noproxy '*' -fsS --connect-timeout 2 --max-time 15 --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/main.dart.js -o "$BACKUP/served-main.dart.js" &&
  [[ $(hash "$BACKUP/served-main.dart.js") == "$1" ]]
}
[[ $(readlink -f "$CURRENT") == "$OLD" && $(readlink -f /opt/coscircle/api/current) == "$API" ]]
LINK="$NEW.current-link"
rollback() {
  trap - EXIT ERR INT TERM HUP
  set +e
  rm -f "$LINK"
  ln -s "$OLD" "$LINK" && mv -Tf "$LINK" "$CURRENT"
  if [[ $(readlink -f "$CURRENT") == "$OLD" ]] && served_matches "$OLD_HASH"; then
    printf 'Web rollback verified. Backup: %s\n' "$BACKUP" >&2
  else
    printf 'RECOVERY FAILED. Restore Web: %s Backup: %s\n' "$OLD" "$BACKUP" >&2
  fi
  exit 1
}
trap rollback EXIT
trap 'exit 1' ERR INT TERM HUP
ln -s "$NEW" "$LINK"
mv -Tf "$LINK" "$CURRENT"
served_matches "$(hash "$NEW/app/main.dart.js")"
timeout 10 systemctl is-active --quiet coscircle-api
curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/api/health > "$BACKUP/health.json"
python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); assert v.get("ok") is True and v.get("name") == "CosCircle API"' "$BACKUP/health.json"
[[ $(readlink -f /opt/coscircle/api/current) == "$API" && $(readlink -f "$CURRENT") == "$NEW" ]]
trap - EXIT ERR INT TERM HUP
printf 'Web release: %s\nPrevious Web: %s\nAPI unchanged: %s\nRoot-only evidence: %s\n' "$NEW" "$OLD" "$API" "$BACKUP"
