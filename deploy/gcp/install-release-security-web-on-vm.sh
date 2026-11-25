#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $EUID == 0 && "$1" =~ ^/tmp/coscircle-security-web-[0-9]+\.tar\.gz$ ]]
exec 9>/run/lock/coscircle-api-deploy.lock;flock -n 9
old="$(readlink -f /var/www/coscircle/current)"
release="$(mktemp -d /var/www/coscircle/releases/release-security-XXXXXXXX)"
stage="$(mktemp -d /tmp/coscircle-security-web-XXXXXXXX)"
trap 'rm -rf "$stage"' EXIT
cp -a "$old/." "$release/"
tar -xzf "$1" -C "$stage" --no-same-owner
for part in app admin;do
 test -f "$stage/$part/index.html"
 rm -rf "$release/$part";cp -a "$stage/$part" "$release/$part"
 rm -f "$release/$part/flutter_service_worker.js"
done
# Preserve any existing admin-root host entry with the same authenticated client.
if [[ -d "$release/admin-root" ]];then
 rm -rf "$release/admin-root";cp -a "$stage/admin" "$release/admin-root"
 sed -i 's|<base href="/admin/">|<base href="/">|' "$release/admin-root/index.html"
fi
install -m0644 "$stage/privacy.html" "$release/privacy.html"
chmod -R a+rX "$release"
ln -s "$release" /var/www/coscircle/current.security-next;mv -Tf /var/www/coscircle/current.security-next /var/www/coscircle/current
for path in / /app/ /admin/ /privacy.html;do
 if ! curl -fsS --max-time 20 --resolve coscircle.app:443:127.0.0.1 "https://coscircle.app$path" >/dev/null;then
  ln -s "$old" /var/www/coscircle/current.security-rollback;mv -Tf /var/www/coscircle/current.security-rollback /var/www/coscircle/current;exit 1
 fi
done
printf 'Published user/admin Web and privacy policy: %s\nPrevious site retained: %s\n' "$release" "$old"
