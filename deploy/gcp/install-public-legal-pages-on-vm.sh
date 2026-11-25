#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
archive="${1:?Pass legal-pages archive}"
expected="${2:?Pass expected active web release basename}"
[[ $EUID == 0 && "$archive" =~ ^/tmp/coscircle-public-legal-[0-9]+\.tar\.gz$ && "$expected" =~ ^[A-Za-z0-9_-]+$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
current=/var/www/coscircle/current
previous="$(readlink -f "$current")"
[[ -L "$current" && "$previous" == "/var/www/coscircle/releases/$expected" ]]
api="$(readlink -f /opt/coscircle/api/current)"
config=/etc/nginx/coscircle-extra/coscircle.app.conf
backup="$(mktemp -d /var/backups/coscircle/public-legal-XXXXXXXX)"
stage="$(mktemp -d /tmp/coscircle-public-legal-stage-XXXXXXXX)"
release="$(mktemp -d /var/www/coscircle/releases/public-legal-XXXXXXXX)"
cp "$config" "$backup/nginx-before.conf"
printf '%s\n' "$previous" > "$backup/web-before.txt"
switched=false
config_changed=false
recover() {
  result=$?
  if [[ "$result" != 0 ]]; then
    if [[ "$switched" == true ]]; then
      ln -s "$previous" "${current}.legal-rollback"
      mv -Tf "${current}.legal-rollback" "$current"
    fi
    if [[ "$config_changed" == true ]]; then
      cp "$backup/nginx-before.conf" "$config"
      nginx -t && systemctl reload nginx
    fi
  fi
  rm -rf "$stage"
  exit "$result"
}
trap recover EXIT

tar -xzf "$archive" -C "$stage" --no-same-owner
files=(privacy.html terms.html child-safety.html delete-account.html delete-account.js legal.css)
for file in "${files[@]}"; do test -s "$stage/$file"; done
node --check "$stage/delete-account.js"
cp -a "$previous/." "$release/"
for file in "${files[@]}"; do
  install -m 0644 "$stage/$file" "$release/$file"
  install -m 0644 "$stage/$file" "$release/official/$file"
done
chmod a+rx "$release"
config_changed=true
python3 - "$config" "$stage/legal-public-pages.nginx" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);text=p.read_text();block=Path(sys.argv[2]).read_text()
start='  # BEGIN PUBLIC LEGAL PAGES\n';end='  # END PUBLIC LEGAL PAGES\n'
if start in text:
    assert text.count(start)==text.count(end)==1
    a=text.index(start);b=text.index(end)+len(end)
    text=text[:a]+block.rstrip()+'\n'+text[b:]
else:
    assert 'location = /privacy.html' not in text
    anchor='  location /api/ {'
    assert text.count(anchor)==1
    text=text.replace(anchor,block+anchor,1)
p.write_text(text)
PY
nginx -t
[[ "$(readlink -f "$current")" == "$previous" ]]
ln -s "$release" "${current}.legal-next"
mv -Tf "${current}.legal-next" "$current"
switched=true
systemctl reload nginx
for file in "${files[@]}"; do
  curl -fsS --max-time 20 --resolve coscircle.app:443:127.0.0.1 "https://coscircle.app/$file" -o "$stage/served-$file"
  cmp "$stage/$file" "$stage/served-$file"
done
for file in index.html app/main.dart.js admin/main.dart.js; do
  cmp "$previous/$file" "$release/$file"
done
[[ "$(readlink -f /opt/coscircle/api/current)" == "$api" ]]
curl -fsS --max-time 10 http://127.0.0.1:8080/api/health
printf '\nPublished legal pages: %s\nPrevious web release: %s\nConfiguration backup: %s\n' "$release" "$previous" "$backup"
