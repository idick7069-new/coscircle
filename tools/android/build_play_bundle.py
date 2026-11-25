#!/usr/bin/env python3
"""Build the production Play bundle without putting credentials on the command line."""
import os
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
flutter = os.environ.get('FLUTTER_BIN', str(root.parent / 'flutter/bin/flutter'))
if not (root / 'android/key.properties').is_file():
    sys.exit('Missing android/key.properties; configure the upload signing key first.')
# Reuse the Android Maps key already configured for this project.
source = (root / 'android/app/build.gradle.kts').read_text()
package = re.search(r'applicationId = "([^"]+)"', source).group(1)
config = json.loads((root / 'android/app/google-services.json').read_text())
clients = [client for client in config.get('client', [])
           if client.get('client_info', {}).get('android_client_info', {}).get('package_name') == package]
if len(clients) != 1:
    sys.exit(f'Firebase Android registration for {package} is missing; obtain its real google-services.json before building.')
app_id = clients[0]['client_info']['mobilesdk_app_id']
options = (root / 'lib/firebase_options.dart').read_text()
if f"appId: '{app_id}'" not in options:
    sys.exit('Firebase Dart options do not match the Android registration; update both configurations.')
match = re.search(r'googleMapsApiKey \?: "(AIza[\w-]+)"', source)
key = os.environ.get('ORG_GRADLE_PROJECT_GOOGLE_MAPS_API_KEY') or (match.group(1) if match else '')
if not key:
    sys.exit('Set ORG_GRADLE_PROJECT_GOOGLE_MAPS_API_KEY.')
env = os.environ.copy()
env['ORG_GRADLE_PROJECT_GOOGLE_MAPS_API_KEY'] = key
env['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
target = 'apk' if sys.argv[1:] == ['--apk'] else 'appbundle'
if sys.argv[1:] not in ([], ['--apk']):
    sys.exit('Usage: build_play_bundle.py [--apk]')
subprocess.run([
    flutter, 'build', target, '--release', '--no-pub',
    *(['--target-platform=android-arm64'] if target == 'apk' else []),
    '--dart-define=API_BASE_URL=https://coscircle.app/api',
    '--dart-define=PUBLIC_APP_URL=https://coscircle.app/app',
    '--dart-define=ENABLE_LINE_LOGIN=true',
    '--dart-define=ENABLE_ACCOUNT_SAFETY=true',
], cwd=root, env=env, check=True)
