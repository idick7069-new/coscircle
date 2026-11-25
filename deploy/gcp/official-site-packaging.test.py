#!/usr/bin/env python3
"""Exercise the real site packager with transport isolated from production."""
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
class LegalPackagingTest(unittest.TestCase):
    def test_official_archive_contains_root_legal_pages_and_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp);binary=tmp/'gcloud'
            binary.write_text('''#!/usr/bin/env python3
import os,shutil,sys
if sys.argv[1:3]==['compute','scp']:
 shutil.copyfile(sys.argv[3],os.environ['CAPTURE_ARCHIVE'])
elif sys.argv[1:3]!=['compute','ssh']:
 raise SystemExit('Unexpected command')
''');binary.chmod(0o755)
            archive=tmp/'site.tar.gz'
            env={**os.environ,'PATH':str(tmp)+os.pathsep+os.environ['PATH'],
                 'GCP_PROJECT':'packaging-test','GCP_ACCOUNT':'packaging-test@example.invalid','CAPTURE_ARCHIVE':str(archive)}
            subprocess.run(['bash',str(ROOT/'deploy/gcp/deploy-official-site.sh')],env=env,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            with tarfile.open(archive) as package:
                members={m.name.removeprefix('./'):m for m in package if m.isfile()}
                for name in ['privacy.html','terms.html','child-safety.html','delete-account.html','delete-account.js','legal.css']:
                    with self.subTest(file=name):
                        expected=(ROOT/'web/official'/name).read_bytes()
                        self.assertEqual(package.extractfile(members[name]).read(),expected)
                        self.assertEqual(package.extractfile(members['official/'+name]).read(),expected)
                self.assertNotEqual(package.extractfile(members['privacy.html']).read(),package.extractfile(members['index.html']).read())
if __name__=='__main__':unittest.main()
