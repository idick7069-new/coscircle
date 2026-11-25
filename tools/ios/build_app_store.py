#!/usr/bin/env python3
"""Build an iOS App Store archive only after required production services are ready."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import shlex
import urllib.request
from firebase_config import load_firebase_ios

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = 'com.hikakineame.coscircle'
API = 'https://coscircle.app/api'
parser = argparse.ArgumentParser()
parser.add_argument('--unsigned', action='store_true', help='Compile only; cannot upload or install this artifact.')
parser.add_argument('--prepare-config', action='store_true', help='Validate Firebase and write private Dart configuration without building.')
parser.add_argument('--build-number', type=int, default=8)
args = parser.parse_args()
if args.build_number < 1:
    parser.error('build number must be positive')
flutter = Path(os.environ.get('FLUTTER_BIN', ROOT.parent / 'flutter/bin/flutter'))
private = ROOT / 'build/private/ios'
private.mkdir(parents=True, exist_ok=True)
private.chmod(0o700)
config = ROOT / 'ios/Flutter/StoreSecrets.xcconfig'
try:
    firebase_defines = load_firebase_ios(ROOT / 'ios/Runner/GoogleService-Info.plist')
except ValueError as error:
    raise SystemExit(str(error)) from None
defines = private / 'firebase-defines.json'
defines.write_text(json.dumps(firebase_defines))
defines.chmod(0o600)
if args.prepare_config:
    print('Verified Firebase iOS configuration; private build definitions prepared.')
    raise SystemExit(0)
if not args.unsigned:
    team = os.environ.get('APPLE_TEAM_ID', '')
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise SystemExit('Set APPLE_TEAM_ID to the active paid team shown by Apple Developer; do not assume the old Personal Team.')
    settings = config.read_text() if config.exists() else ''
    if not re.search(r'^GOOGLE_MAPS_IOS_API_KEY\s*=\s*AIza[\w-]+\s*$', settings, re.M):
        raise SystemExit('Missing bundle-restricted iOS Maps configuration.')
    try:
        with urllib.request.urlopen(API + '/auth/apple/config', timeout=15) as response:
            enabled = json.load(response).get('enabled') is True
    except Exception:
        enabled = False
    if not enabled:
        raise SystemExit('Production Apple login is not enabled and verified; keep LINE and finish Apple setup before uploading.')
    # This file is excluded from Git and is read by the existing Debug/Release xcconfig files.
    settings = re.sub(r'^DEVELOPMENT_TEAM\s*=.*\n?', '', settings, flags=re.M)
    config.write_text(settings.rstrip() + '\nDEVELOPMENT_TEAM=' + team + '\n')
    config.chmod(0o600)
    options = private / 'ExportOptions.plist'
    profile_file = private / 'profile-metadata.json'
    if not profile_file.is_file() or not (ROOT / 'ios/Flutter/StoreSigning.xcconfig').is_file():
        raise SystemExit('Prepare the app-specific distribution signing identity and provisioning profile first.')
    profile = json.loads(profile_file.read_text())
    if profile.get('team') != team:
        raise SystemExit('Distribution profile team does not match the selected Apple team.')
    with options.open('wb') as f:
        plistlib.dump({'method': 'app-store-connect', 'teamID': team, 'signingStyle': 'manual',
                       'signingCertificate': 'Apple Distribution',
                       'provisioningProfiles': {BUNDLE: profile['name']},
                       'uploadSymbols': True, 'manageAppVersionAndBuildNumber': False}, f)
    command = [str(flutter), 'build', 'ipa', '--release', '--export-options-plist=' + str(options)]
else:
    command = [str(flutter), 'build', 'ios', '--release', '--no-codesign']
command += ['--target=lib/main.dart', '--build-name=1.0.1', '--build-number=' + str(args.build_number),
            '--dart-define=API_BASE_URL=' + API, '--dart-define=PUBLIC_APP_URL=https://coscircle.app/app',
            '--dart-define=ENABLE_ACCOUNT_SAFETY=true', '--dart-define=ENABLE_LINE_LOGIN=true',
            '--dart-define=ENABLE_APPLE_LOGIN=true']
command.append('--dart-define-from-file=' + str(defines))
keychain = private / 'coscircle-distribution.keychain-db'
previous_search = None
if not args.unsigned:
    previous_search = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
    password = (private / 'signing-keychain-password').read_text()
    unlock = subprocess.run(['security', 'unlock-keychain', '-p', password, str(keychain)], capture_output=True)
    if unlock.returncode:
        raise SystemExit('Unlock the dedicated distribution keychain before building.')
    if str(keychain) not in previous_search:
        subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *previous_search, str(keychain)], check=True)
try:
    subprocess.run(command, cwd=ROOT, check=True)
finally:
    if previous_search is not None and str(keychain) not in previous_search:
        current_search = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
        subprocess.run(['security', 'list-keychains', '-d', 'user', '-s',
                        *[item for item in current_search if item != str(keychain)]], check=True)
if not args.unsigned:
    subprocess.run(['python3', str(ROOT / 'tools/ios/verify_store_artifact.py'), '--build-number', str(args.build_number)], check=True)
print('Unsigned compile complete; this is not an uploadable IPA.' if args.unsigned else 'Archive/export complete. Validate the signed IPA and native services before upload.')
