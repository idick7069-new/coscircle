#!/usr/bin/env bash
set -euo pipefail

archive="${1:?Pass the uploaded official-site archive}"
[[ "$archive" =~ ^/tmp/coscircle-official-[0-9]+\.tar\.gz$ ]] || exit 1
exec 9>/run/lock/coscircle-api-deploy.lock
flock -n 9
current=/var/www/coscircle/current
previous="$(readlink -f "$current")"
[[ -L "$current" && "$previous" == /var/www/coscircle/releases/* && -f "$previous/index.html" ]] || exit 1
release="$(mktemp -d /var/www/coscircle/releases/official-XXXXXXXX)"
staging="$(mktemp -d /tmp/coscircle-official-stage-XXXXXXXX)"
switched=false
recover() {
  result=$?
  if [[ "$result" != 0 && "$switched" == true ]]; then
    ln -s "$previous" "${current}.official-rollback"
    mv -Tf "${current}.official-rollback" "$current"
    echo "Restored previous official site: $previous" >&2
  fi
  rm -rf "$staging"
  exit "$result"
}
trap recover EXIT

tar -xzf "$archive" -C "$staging" --no-same-owner
for file in index.html android-testing.html privacy.html terms.html child-safety.html delete-account.html delete-account.js legal.css official/styles.css official/site.js official/android-testing.json official/assets/pixel-v1/logo.png; do
  test -f "$staging/$file"
done
cp -a "$previous/." "$release/"
# Remove the inherited directory before copying so no previous official files survive.
rm -rf "$release/official"
cp -a "$staging/official" "$release/official"
for file in index.html android-testing.html privacy.html terms.html child-safety.html delete-account.html delete-account.js legal.css; do
  cp "$staging/$file" "$release/$file"
done
chown -R root:root "$release/official"
chmod -R a+rX "$release"
[[ "$(readlink -f "$current")" == "$previous" ]] || { echo 'Another deployment changed the active release' >&2; exit 1; }
ln -s "$release" "${current}.official-next"
mv -Tf "${current}.official-next" "$current"
switched=true
for page in / /android-testing.html /official/styles.css?v=20261111-1 /official/site.js?v=20261111-1 /official/android-testing.json; do
  curl -fsS --resolve coscircle.app:443:127.0.0.1 "https://coscircle.app$page" -o /dev/null
done
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/ | grep -q '跟著希希'
curl -fsS --resolve coscircle.app:443:127.0.0.1 https://coscircle.app/android-testing.html | grep -q 'Android 測試加入指南'
for file in privacy.html terms.html child-safety.html delete-account.html delete-account.js legal.css; do
  curl -fsS --resolve coscircle.app:443:127.0.0.1 "https://coscircle.app/$file" -o "$staging/served-$file"
  cmp "$staging/$file" "$staging/served-$file"
done
printf 'Published official site: %s\nPrevious release retained: %s\n' "$release" "$previous"
