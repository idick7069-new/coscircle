import io
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parent
SCRIPT = (ROOT / 'deploy-partner-discovery-on-vm.sh').read_text()
VALIDATOR = SCRIPT.split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]


class ArchiveTests(unittest.TestCase):
    def validate(self, kind='feature', extra=(), omit=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            stage = root / 'stage'
            stage.mkdir()
            source = root / 'source.tar.gz'
            names = ['src/same-works.js', 'src/partner-discovery.js'] if kind == 'feature' else ['app', 'app/assets', 'app/index.html', 'app/main.dart.js', 'app/assets/a.png']
            with tarfile.open(source, 'w:gz') as archive:
                entries = [(name, tarfile.DIRTYPE if name in ('app', 'app/assets') else tarfile.REGTYPE, 1) for name in names if name != omit]
                for name, entry_type, size in entries + list(extra):
                    member = tarfile.TarInfo(name)
                    member.type = entry_type
                    member.size = size if entry_type == tarfile.REGTYPE else 0
                    member.linkname = '/etc/coscircle/api.env' if entry_type in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ''
                    archive.addfile(member, io.BytesIO(b'x' * member.size) if entry_type == tarfile.REGTYPE else None)
            result = subprocess.run([sys.executable, '-c', VALIDATOR, kind, str(source), str(stage)], capture_output=True, text=True)
            written = {str(path.relative_to(stage)) for path in stage.rglob('*')}
            return result, written

    def test_valid_archives(self):
        for kind in ('feature', 'web'):
            with self.subTest(kind=kind):
                result, written = self.validate(kind)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('src/same-works.js' if kind == 'feature' else 'app/main.dart.js', written)

    def test_rejected_members_write_nothing(self):
        for kind in ('feature', 'web'):
            base = 'src/same-works.js' if kind == 'feature' else 'app/main.dart.js'
            for extra in (
                ('../escape', tarfile.REGTYPE, 1),
                ('/etc/escape', tarfile.REGTYPE, 1),
                ('app/../escape', tarfile.REGTYPE, 1),
                ('app//escape', tarfile.REGTYPE, 1),
                ('./' + base, tarfile.REGTYPE, 1),
                (base, tarfile.REGTYPE, 1),
                (base, tarfile.SYMTYPE, 0),
                (base, tarfile.LNKTYPE, 0),
                ('app/linked', tarfile.SYMTYPE, 0),
                ('app/fifo', tarfile.FIFOTYPE, 0),
                ('app/device', tarfile.CHRTYPE, 0),
                ('src/server.js', tarfile.REGTYPE, 1),
                ('admin/index.html', tarfile.REGTYPE, 1),
                ('index.html', tarfile.REGTYPE, 1),
                ('app/bad\\path', tarfile.REGTYPE, 1),
                ('app/bad\npath', tarfile.REGTYPE, 1),
            ):
                with self.subTest(kind=kind, extra=extra):
                    result, written = self.validate(kind, extra=[extra])
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(written, set())

    def test_missing_empty_oversized_and_conflicting_members(self):
        for kind in ('feature', 'web'):
            required = 'src/same-works.js' if kind == 'feature' else 'app/main.dart.js'
            maximum = 4 * 1024 * 1024 if kind == 'feature' else 64 * 1024 * 1024
            for extra in ([], [(required, tarfile.REGTYPE, 0)], [(required, tarfile.REGTYPE, maximum + 1)]):
                with self.subTest(kind=kind, extra=extra):
                    result, written = self.validate(kind, extra=extra, omit=required)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(written, set())
        result, written = self.validate('web', extra=[('app/file', tarfile.REGTYPE, 1), ('app/file/child', tarfile.REGTYPE, 1)])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(written, set())


class SwitchTests(unittest.TestCase):
    def test_embedded_javascript_syntax(self):
        javascript = SCRIPT.split("<<'JS'\n", 1)[1].split('\nJS\n', 1)[0]
        result = subprocess.run(['node', '--input-type=module', '--check'], input=javascript, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_active_release_and_source_drift_abort(self):
        functions = SCRIPT.split('verify_active() {\n', 1)[1].split('\nverify_active\n', 1)[0]
        functions = 'verify_active() {\n' + functions
        prelude = r'''
set -Eeuo pipefail
die() { printf '%s\n' "$*" >&2; exit 1; }
hash() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
readlink() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${!#}"; }
SERVER_SHA=$(hash "$EXPECTED_API/src/server.js")
SAME_WORK_SHA=$(hash "$EXPECTED_API/src/same-works.js")
case $CASE in
  api-drift) rm "$CURRENT"; ln -s "$EXPECTED_WEB" "$CURRENT" ;;
  web-drift) rm "$WEB_CURRENT"; ln -s "$EXPECTED_API" "$WEB_CURRENT" ;;
  server-drift) printf changed >> "$EXPECTED_API/src/server.js" ;;
  module-drift) printf changed >> "$EXPECTED_API/src/same-works.js" ;;
  module-link) rm "$EXPECTED_API/src/same-works.js"; ln -s server.js "$EXPECTED_API/src/same-works.js" ;;
  partner-exists) touch "$EXPECTED_API/src/partner-discovery.js" ;;
  uploads-missing) rm "$EXPECTED_API/uploads" ;;
esac
'''
        for case in ('success', 'api-drift', 'web-drift', 'server-drift', 'module-drift', 'module-link', 'partner-exists', 'uploads-missing'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary).resolve()
                for name in ('api/src', 'api/node_modules', 'api/.crawler-venv', 'web/app', 'uploads'):
                    (root / name).mkdir(parents=True)
                for name in ('server.js', 'same-works.js'):
                    (root / 'api/src' / name).write_text('original')
                (root / 'api/uploads').symlink_to(root / 'uploads')
                (root / 'api-current').symlink_to(root / 'api')
                (root / 'web-current').symlink_to(root / 'web')
                env = dict(os.environ, CASE=case, EXPECTED_API=str(root / 'api'), EXPECTED_WEB=str(root / 'web'), CURRENT=str(root / 'api-current'), WEB_CURRENT=str(root / 'web-current'))
                result = subprocess.run(['bash', '-c', prelude + functions + '\nverify_active\n'], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if case == 'success' else 1, result.stderr)

    def test_success_and_rollback_both_releases(self):
        switch = 'SWITCH_LINK="$API.current-link"\n' + SCRIPT.split('SWITCH_LINK="$API.current-link"\n', 1)[1]
        mocks = r'''
set -Eeuo pipefail
die() { printf '%s\n' "$*" >&2; exit 1; }
timeout() { [[ $1 =~ ^[0-9]+$ && $1 -le 60 ]] || return 99; shift; "$@"; }
sleep() { :; }
hash() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
sha256sum() { printf '%s  %s\n' "$(hash "${!#}")" "${!#}"; }
mv() {
  [[ $1 == -Tf && $2 == -- ]] || return 99
  if [[ $CASE == second-switch && $4 == "$WEB_CURRENT" && ! -f $BACKUP/move-failed ]]; then
    touch "$BACKUP/move-failed"
    return 1
  fi
  if [[ $CASE == recovery-api-link && $4 == "$CURRENT" && -f $BACKUP/recovering ]] ||
     [[ $CASE == recovery-web-link && $4 == "$WEB_CURRENT" && -f $BACKUP/recovering ]]; then
    return 1
  fi
  python3 -c 'import os,sys; os.replace(sys.argv[1], sys.argv[2])' "$3" "$4"
}
readlink() {
  [[ $1 == -f && $2 == -- ]] || return 99
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$3"
}
systemctl() {
  printf '%s\n' "$*" >> "$BACKUP/service-calls"
  if [[ $1 == restart && $(readlink -f -- "$CURRENT") == "$OLD_API" ]]; then
    touch "$BACKUP/recovering"
    [[ $CASE != recovery-restart ]] || return 1
  fi
  if [[ $CASE == restart && ! -f $BACKUP/restart-failed ]]; then
    touch "$BACKUP/restart-failed"
    return 1
  fi
  if [[ $1 == is-active ]]; then
    [[ $CASE != inactive || -f $BACKUP/recovering ]] || return 1
    [[ $CASE != recovery-inactive || ! -f $BACKUP/recovering ]] || return 1
  fi
}
curl() {
  local url='' output='' maximum=''
  while (($#)); do
    case $1 in
      -o) output=$2; shift ;;
      --max-time) maximum=$2; shift ;;
      http*) url=$1 ;;
    esac
    shift
  done
  [[ $maximum =~ ^[0-9]+$ && $maximum -le 15 ]] || return 99
  if [[ -f $BACKUP/recovering ]]; then printf '%s\n' "$url" >> "$BACKUP/recovery-probes"; fi
  if [[ $url == */api/health ]]; then
    if [[ -f $BACKUP/recovering ]]; then
      [[ $CASE != recovery-health ]] || return 1
      if [[ $CASE == recovery-transient && ! -f $BACKUP/health-retried ]]; then
        touch "$BACKUP/health-retried"
        return 1
      fi
      if [[ $CASE == recovery-health-body ]]; then
        printf '{"ok":true,"name":"CosCircle API"}'
      else
        cat "$BACKUP/old-health.json"
      fi
      return
    fi
    [[ $CASE != health ]] || return 1
    if [[ $CASE == health-body ]]; then printf '{"ok":true,"name":"other"}'; else printf '{"ok":true,"name":"CosCircle API"}'; fi
  elif [[ $url == */app/main.dart.js ]]; then
    if [[ -f $BACKUP/recovering ]]; then
      [[ $CASE != recovery-web-http ]] || return 1
      if [[ $CASE == recovery-web-body ]]; then cp "$WEB/app/main.dart.js" "$output"; else cp "$WEB_CURRENT/app/main.dart.js" "$output"; fi
    elif [[ $CASE == web-body ]]; then printf wrong > "$output"; else cp "$WEB_CURRENT/app/main.dart.js" "$output"; fi
  else
    [[ $CASE != signal ]] || kill -TERM $$
    if [[ $CASE == auth-body ]]; then printf '{}' > "$output"; else printf '{"error":"authentication_required"}' > "$output"; fi
    if [[ ( $CASE == route || $CASE == recovery-* ) && $url == */1/users ]]; then
      [[ $CASE != recovery-* ]] || touch "$BACKUP/recovering"
      printf 404
    else
      printf 401
    fi
  fi
}
printf '{"ok":true,"name":"CosCircle API","release":"old"}' > "$BACKUP/old-health.json"
OLD_WEB_SHA256=$(hash "$OLD_WEB/app/main.dart.js")
'''
        failed_recovery = ('recovery-restart', 'recovery-inactive', 'recovery-health', 'recovery-health-body', 'recovery-web-http', 'recovery-web-body', 'recovery-api-link', 'recovery-web-link')
        for case in ('success', 'second-switch', 'restart', 'health', 'health-body', 'route', 'auth-body', 'web-body', 'inactive', 'signal', 'recovery-transient', *failed_recovery):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary).resolve()
                for name in ('old-api', 'new-api', 'old-web/app', 'new-web/app', 'backup'):
                    (root / name).mkdir(parents=True)
                (root / 'old-web/app/main.dart.js').write_text('previous')
                (root / 'new-web/app/main.dart.js').write_text('candidate')
                (root / 'api-current').symlink_to(root / 'old-api')
                (root / 'web-current').symlink_to(root / 'old-web')
                env = dict(os.environ, CASE=case, API=str(root / 'new-api'), WEB=str(root / 'new-web'), OLD_API=str(root / 'old-api'), OLD_WEB=str(root / 'old-web'), CURRENT=str(root / 'api-current'), WEB_CURRENT=str(root / 'web-current'), BACKUP=str(root / 'backup'))
                result = subprocess.run(['bash', '-c', mocks + switch], env=env, capture_output=True, text=True, timeout=30)
                success = case == 'success'
                self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
                for name in ('api', 'web'):
                    failed_link = case == f'recovery-{name}-link'
                    self.assertEqual((root / f'{name}-current').resolve(), root / f'{"new" if success or failed_link else "old"}-{name}')
                    self.assertEqual((root / f'new-{name}.current-link').is_symlink(), failed_link)
                self.assertEqual('RECOVERY FAILED' in result.stderr, case in failed_recovery, result.stderr)
                self.assertEqual('Recovery verified:' in result.stderr, not success and case not in failed_recovery, result.stderr)
                probes = root / 'backup/recovery-probes'
                if case in ('recovery-health', 'recovery-health-body', 'recovery-web-http', 'recovery-web-body', 'recovery-transient'):
                    health_probes = [url for url in probes.read_text().splitlines() if url.endswith('/api/health')]
                    self.assertEqual(len(health_probes), 2 if case == 'recovery-transient' else 10)
                if not success and case not in failed_recovery:
                    self.assertEqual((root / 'backup/restored-health.json').read_text(), (root / 'backup/old-health.json').read_text())
                    self.assertEqual((root / 'backup/restored-main.dart.js').read_text(), 'previous')
                calls = (root / 'backup/service-calls').read_text().splitlines()
                expected_restarts = 1 if success or case == 'second-switch' else 2
                self.assertEqual(calls.count('restart coscircle-api'), expected_restarts)

    def test_old_release_baseline_before_switch(self):
        baseline = '[[ -f $OLD_WEB/app/main.dart.js' + SCRIPT.split('[[ -f $OLD_WEB/app/main.dart.js', 1)[1].split('SWITCH_LINK=', 1)[0]
        mocks = r'''
set -Eeuo pipefail
die() { printf '%s\n' "$*" >&2; exit 1; }
hash() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
timeout() { shift; "$@"; }
systemctl() { [[ $CASE != inactive ]]; }
curl() {
  [[ $CASE != http-failure ]] || return 1
  if [[ $CASE == invalid-body ]]; then printf '{"ok":false}'; else printf '{"ok":true,"name":"CosCircle API","release":"old"}'; fi
}
'''
        for case in ('success', 'inactive', 'http-failure', 'invalid-body', 'missing-web', 'linked-web'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                root = pathlib.Path(temporary)
                (root / 'app').mkdir()
                (root / 'backup').mkdir()
                entrypoint = root / 'app/main.dart.js'
                if case == 'linked-web':
                    (root / 'outside.js').write_text('previous')
                    entrypoint.symlink_to(root / 'outside.js')
                elif case != 'missing-web':
                    entrypoint.write_text('previous')
                env = dict(os.environ, CASE=case, OLD_WEB=str(root), BACKUP=str(root / 'backup'))
                result = subprocess.run(['bash', '-c', mocks + baseline + '\nprintf "%s" "$OLD_WEB_SHA256"'], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if case == 'success' else 1, result.stderr)
                if case == 'success':
                    import hashlib
                    self.assertEqual(result.stdout, hashlib.sha256(b'previous').hexdigest())
                    self.assertEqual((root / 'backup/old-health.json').read_text(), '{"ok":true,"name":"CosCircle API","release":"old"}')

    def test_protected_environment_permissions(self):
        gate = '[[ $(stat -c %u' + SCRIPT.split('[[ $(stat -c %u', 1)[1].split('[[ ! -L /var/backups/coscircle', 1)[0]
        mocks = r'''
set -Eeuo pipefail
die() { printf '%s\n' "$*" >&2; exit 1; }
stat() {
  case $2 in
    %u) printf '%s' "$OWNER" ;;
    %a) printf '%s' "$MODE" ;;
    %G) printf '%s' "$GROUP" ;;
    *) return 99 ;;
  esac
}
'''
        for owner, group, mode, allowed in (
            ('0', 'coscircle', '640', True),
            ('0', 'root', '600', True),
            ('0', 'coscircle', '400', True),
            ('0', 'coscircle', '440', True),
            ('0', 'root', '640', False),
            ('1000', 'coscircle', '640', False),
            ('0', 'coscircle', '660', False),
            ('0', 'coscircle', '646', False),
            ('0', 'coscircle', '604', False),
            ('0', 'coscircle', '650', False),
            ('0', 'coscircle', '740', False),
            ('0', 'coscircle', '4640', False),
        ):
            with self.subTest(owner=owner, group=group, mode=mode):
                result = subprocess.run(['bash', '-c', mocks + gate], env=dict(os.environ, OWNER=owner, GROUP=group, MODE=mode), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if allowed else 1, result.stderr)
        self.assertNotIn('chmod', gate)

    def test_pre_switch_gates_and_narrow_scope(self):
        self.assertLess(SCRIPT.index('EXPECTED_FEATURE_SHA256'), SCRIPT.index('cp -a -- "$OLD_API/."'))
        self.assertLess(SCRIPT.index('SET SESSION TRANSACTION READ ONLY'), SCRIPT.index('trap rollback EXIT'))
        self.assertLess(SCRIPT.index('mysqldump --single-transaction'), SCRIPT.index('trap rollback EXIT'))
        self.assertIn("u.id = 17 AND u.account_status = 'active'", SCRIPT)
        self.assertIn("LOWER(u.email) LIKE '%@example.invalid'", SCRIPT)
        self.assertIn('BINARY a.provider_user_id = BINARY u.email', SCRIPT)
        self.assertNotIn('verified_at', SCRIPT)
        self.assertEqual(SCRIPT.count("LIKE '%@example.invalid'"), 1)
        self.assertNotIn('npm ', SCRIPT)
        self.assertNotIn('mysql coscircle <', SCRIPT)
        self.assertNotIn('systemctl reload', SCRIPT)


if __name__ == '__main__':
    unittest.main(verbosity=2)
