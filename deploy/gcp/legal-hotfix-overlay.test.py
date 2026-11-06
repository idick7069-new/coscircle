import io
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
VALIDATOR = (ROOT / 'deploy-legal-on-vm.sh').read_text().split("<<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
SQL = '''CREATE TABLE IF NOT EXISTS user_legal_consents (
  user_id BIGINT UNSIGNED NOT NULL,
  version VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  accepted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, version),
  CONSTRAINT fk_legal_consent_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);'''


class OverlayTests(unittest.TestCase):
    def validate(self, extra=None, sql=SQL, omit=None):
        with tempfile.TemporaryDirectory(dir=ROOT) as temporary:
            root = pathlib.Path(temporary)
            stage = root / 'stage'
            stage.mkdir()
            archive_path = root / 'overlay.tar.gz'
            files = {'src/server.js': 'server', 'src/legal-consent.js': 'module', 'db/migrate_legal_consent.sql': sql}
            with tarfile.open(archive_path, 'w:gz') as archive:
                for name, value in files.items():
                    if name == omit:
                        continue
                    data = value.encode()
                    member = tarfile.TarInfo(name)
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
                if extra:
                    name, kind, size = extra
                    member = tarfile.TarInfo(name)
                    member.type = kind
                    member.linkname = '/etc/coscircle/api.env' if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ''
                    member.size = size
                    archive.addfile(member, io.BytesIO(b'x' * size) if kind == tarfile.REGTYPE else None)
            result = subprocess.run([sys.executable, '-c', VALIDATOR, str(archive_path), str(stage)], capture_output=True, text=True)
            written = {str(p.relative_to(stage)) for p in stage.rglob('*') if p.is_file()}
            return result, written

    def test_exact_whitelist_is_written(self):
        result, written = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(written, {'src/server.js', 'src/legal-consent.js', 'db/migrate_legal_consent.sql'})

    def test_archive_attacks_abort_before_writing(self):
        for extra in [
            ('../escape', tarfile.REGTYPE, 1), ('/etc/escape', tarfile.REGTYPE, 1),
            ('src/server.js', tarfile.REGTYPE, 1), ('src/legal-consent.js', tarfile.SYMTYPE, 0),
            ('src/legal-consent.js', tarfile.LNKTYPE, 0), ('src', tarfile.DIRTYPE, 0),
            ('api.env', tarfile.REGTYPE, 1), ('src/other.js', tarfile.REGTYPE, 1),
            ('db/migrate_legal_consent.sql', tarfile.REGTYPE, 4 * 1024 * 1024 + 1),
        ]:
            with self.subTest(extra=extra):
                result, written = self.validate(extra=extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Unexpected, duplicate, linked, or oversized', result.stderr)
                self.assertEqual(written, set())

    def test_missing_member_aborts_before_writing(self):
        result, written = self.validate(omit='src/server.js')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exactly the three whitelist files', result.stderr)
        self.assertEqual(written, set())

    def test_extra_sql_aborts_before_writing(self):
        for sql in [SQL + '\nDROP TABLE users;', SQL.replace('IF NOT EXISTS ', ''), SQL.replace('user_legal_consents', 'users')]:
            with self.subTest(sql=sql):
                result, written = self.validate(sql=sql)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Only the reviewed additive', result.stderr)
                self.assertEqual(written, set())


class SwitchTests(unittest.TestCase):
    def test_success_and_failed_checks(self):
        switch = (ROOT / 'deploy-legal-on-vm.sh').read_text().split('SWITCH_LINK="$API.current-link"\n', 1)[1]
        mocks = r'''
set -Eeuo pipefail
timeout() { shift; "$@"; }
sleep() { :; }
mv() {
  [[ $1 == -Tf && $2 == -- ]] || return 99
  python3 -c 'import os,sys; os.replace(sys.argv[1], sys.argv[2])' "$3" "$4"
}
readlink() {
  [[ $1 == -f && $2 == -- ]] || return 99
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$3"
}
systemctl() {
  printf '%s\n' "$*" >> "$BACKUP/service-calls"
  if [[ $CASE == restart-fails && ! -f $BACKUP/restart-failed ]]; then
    touch "$BACKUP/restart-failed"
    return 1
  fi
}
curl() {
  if [[ ${!#} == */api/health ]]; then
    [[ $CASE != health-fails ]] || return 1
    printf '%s' '{"ok":true,"name":"CosCircle API"}'
    return
  fi
  local output=''
  while (($#)); do
    if [[ $1 == -o ]]; then output=$2; shift; fi
    shift
  done
  printf '%s' '{"error":"authentication_required"}' > "$output"
  if [[ $CASE == legal-fails ]]; then printf 404; else printf 401; fi
}
SWITCH_LINK="$API.current-link"
'''
        for case in ['success', 'health-fails', 'legal-fails', 'restart-fails']:
            with self.subTest(case=case), tempfile.TemporaryDirectory(dir=ROOT) as temporary:
                root = pathlib.Path(temporary)
                for name in ['old', 'new', 'backup']:
                    (root / name).mkdir()
                current = root / 'current'
                current.symlink_to(root / 'old')
                env = dict(os.environ, CASE=case, API=str(root / 'new'), OLD_API=str(root / 'old'), CURRENT=str(current), BACKUP=str(root / 'backup'))
                result = subprocess.run(['bash', '-c', mocks + switch], env=env, capture_output=True, text=True)
                success = case == 'success'
                self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
                self.assertEqual(current.resolve(), root / ('new' if success else 'old'))
                calls = (root / 'backup/service-calls').read_text().splitlines()
                self.assertEqual(calls.count('restart coscircle-api'), 1 if success else 2)
                self.assertFalse((root / 'new.current-link').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
