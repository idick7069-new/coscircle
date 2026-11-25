#!/usr/bin/env python3
"""Fetch this app's existing iOS Firebase config without printing tokens or keys."""
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PROJECT = 'coscircle'
BUNDLE = 'com.hikakineame.coscircle'
ACCOUNT = 'idick7069@gmail.com'
result = subprocess.run(['gcloud', 'auth', 'print-access-token', '--account=' + ACCOUNT], capture_output=True, text=True, check=True)
headers = {'Authorization': 'Bearer ' + result.stdout.strip(), 'X-Goog-User-Project': PROJECT}

def get(endpoint):
    request = urllib.request.Request('https://firebase.googleapis.com/v1beta1/' + endpoint, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise SystemExit('Firebase API request failed (HTTP ' + str(error.code) + '); check project access and quota project.') from None

apps = get('projects/' + PROJECT + '/iosApps').get('apps', [])
matches = [app for app in apps if app.get('bundleId') == BUNDLE]
if len(matches) != 1:
    raise SystemExit('Expected exactly one registered iOS app for ' + BUNDLE + '. Register it in Firebase Console first; do not create duplicates.')
app = matches[0]
config = get(app['name'] + '/config')
raw = base64.b64decode(config['configFileContents'], validate=True)
values = plistlib.loads(raw)
if values.get('BUNDLE_ID') != BUNDLE or values.get('PROJECT_ID') != PROJECT or values.get('GOOGLE_APP_ID') != app['appId']:
    raise SystemExit('Downloaded Firebase configuration does not match the intended iOS app.')
if ':ios:' not in values['GOOGLE_APP_ID'] or not values.get('API_KEY', '').startswith('AIza'):
    raise SystemExit('Invalid iOS Firebase configuration.')
output = ROOT / 'ios/Runner/GoogleService-Info.plist'
if output.exists():
    existing = plistlib.loads(output.read_bytes())
    if existing.get('BUNDLE_ID') != BUNDLE or existing.get('PROJECT_ID') != PROJECT:
        raise SystemExit('Existing Firebase configuration belongs to another app; refusing overwrite.')
fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'wb') as stream:
    stream.write(raw)
output.chmod(0o600)
private = ROOT / 'build/private/ios'
private.mkdir(parents=True, exist_ok=True)
private.chmod(0o700)
report = {'projectId': PROJECT, 'projectNumber': values['GCM_SENDER_ID'], 'bundleId': BUNDLE,
          'appId': app['appId'], 'configFile': str(output.relative_to(ROOT)), 'quotaProjectExplicit': True}
(private / 'firebase-config-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print('Fetched and verified Firebase iOS configuration for ' + BUNDLE + '; credential values not printed.')
