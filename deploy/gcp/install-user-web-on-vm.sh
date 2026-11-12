#!/usr/bin/env bash
set -Eeuo pipefail
archive="${1:?Pass uploaded Web archive}"
expected="${2:?Pass expected main.dart.js SHA256}"
[[ "$archive" =~ ^/tmp/coscircle-user-web-[0-9]+\.tar\.gz$ && "$expected" =~ ^[a-f0-9]{64}$ ]] || exit 1
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
current=/var/www/coscircle/current
previous="$(readlink -f "$current")"
api="$(readlink -f /opt/coscircle/api/current)"
[[ -L "$current" && "$previous" == /var/www/coscircle/releases/* && -f "$previous/app/main.dart.js" ]] || exit 1
release="$(mktemp -d /var/www/coscircle/releases/user-web-XXXXXXXX)"
staging="$(mktemp -d /tmp/coscircle-user-web-stage-XXXXXXXX)"
switched=false
recover() {
  result=$?
  if [[ "$result" != 0 && "$switched" == true ]]; then
    ln -s "$previous" "${current}.user-web-rollback"
    mv -Tf "${current}.user-web-rollback" "$current"
    echo "Restored previous Web App: $previous" >&2
  fi
  rm -rf "$staging"
  exit "$result"
}
trap recover EXIT

tar -xzf "$archive" -C "$staging" --no-same-owner
[[ "$(sha256sum "$staging/app/main.dart.js" | cut -d ' ' -f 1)" == "$expected" ]]
test -f "$staging/app/assets/assets/mimi/cute-v1/portrait.png"
grep -q '<base href="/app/">' "$staging/app/index.html"
cp -a "$previous/." "$release/"
rm -rf "$release/app"
cp -a "$staging/app" "$release/app"
chmod -R a+rX "$release"
[[ "$(readlink -f "$current")" == "$previous" && "$(readlink -f /opt/coscircle/api/current)" == "$api" ]] || exit 1
ln -s "$release" "${current}.user-web-next"
mv -Tf "${current}.user-web-next" "$current"
switched=true
curl -fsS --max-time 20 --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/app/main.dart.js -o "$staging/served-main.dart.js"
[[ "$(sha256sum "$staging/served-main.dart.js" | cut -d ' ' -f 1)" == "$expected" ]]
for page in /app/ /app/flutter_bootstrap.js /app/assets/assets/mimi/cute-v1/portrait.png /app/assets/assets/brand/coscircle-mark.png /android-testing.html; do
  curl -fsS --max-time 15 --resolve coscircle.app:443:127.0.0.1 "https://coscircle.app$page" -o /dev/null
done
curl -fsS --max-time 10 http://127.0.0.1:8080/api/health
[[ "$(readlink -f /opt/coscircle/api/current)" == "$api" ]]
printf '\nPublished Web App: %s\nPrevious release retained: %s\n' "$release" "$previous"
