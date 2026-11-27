#!/usr/bin/env python3
"""Display only the Apple review login in the owner's interactive terminal."""
import json
import shlex
import subprocess
import sys

if not sys.stdout.isatty():
    raise SystemExit("Run this directly in your Terminal. Credentials are not written to logs or files.")
remote = "import json; s=json.load(open('/etc/coscircle/apple-review-accounts.json')); a=next(a for a in s['accounts'] if a['key']=='main'); print(json.dumps({'email':a['email'],'password':a['password']}))"
result = subprocess.run([
    'gcloud', 'compute', 'ssh', 'coscircle-free-vm', '--zone=us-west1-b',
    '--project=cos-circle', '--account=idick7069@gmail.com',
    '--command=sudo python3 -c ' + shlex.quote(remote),
], capture_output=True, text=True)
if result.returncode:
    raise SystemExit("Could not retrieve Apple review login. Check your GCP login and connection.")
try:
    account = json.loads(result.stdout)
    print("Apple Beta Review — CosCircle App login (not your Apple ID)")
    print("Username:", account['email'])
    print("Password:", account['password'])
    print("Paste these into App Store Connect review login fields only. Do not share in chat.")
except (ValueError, KeyError):
    raise SystemExit("Unexpected response; no credentials displayed.")
