#!/usr/bin/env python3
"""Inspect the actual archived App, signed entitlements, and credential boundaries."""
import argparse, json, plistlib, subprocess
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--build-number',default='8');args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
archive=root/'build/ios/archive/Runner.xcarchive'
apps=list((archive/'Products/Applications').glob('*.app'))
assert len(apps)==1,'Expected one archived application'
app=apps[0]
def run(args):return subprocess.check_output(args,stderr=subprocess.DEVNULL)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
i=plistlib.loads((app/'Info.plist').read_bytes())
e=plistlib.loads(run(['codesign','-d','--entitlements',':-',str(app)]))
f=plistlib.loads((app/'GoogleService-Info.plist').read_bytes())
assert i['CFBundleIdentifier']=='com.hikakineame.coscircle'
assert i['CFBundleShortVersionString']=='1.0.1' and i['CFBundleVersion']==args.build_number
assert i['ITSAppUsesNonExemptEncryption'] is False
assert e['application-identifier']=='UF6P9B6PBV.com.hikakineame.coscircle'
assert e['com.apple.developer.team-identifier']=='UF6P9B6PBV'
assert e['aps-environment']=='production' and e['com.apple.developer.applesignin']==['Default']
assert not e.get('get-task-allow',False)
assert f['PROJECT_ID']=='coscircle' and f['GOOGLE_APP_ID']=='1:659745646640:ios:a84bca0915d81b178965f5'
for p in app.rglob('*'):
 if not p.is_file():continue
 assert p.suffix not in ['.p8','.p12','.key','.keychain-db'],f'Private credential in application: {p.name}'
 assert p.name not in ['firebase-push-sender.json','api.env','signing-keychain-password']
geolocator=app/'Frameworks/geolocator_apple.framework/geolocator_apple'
assert geolocator.is_file(),'Expected the compiled location plugin'
binaries = [app / i['CFBundleExecutable']] + [f / f.stem for f in (app / 'Frameworks').glob('*.framework')]
for binary in binaries:
    if binary.is_file():
        assert b'requestAlwaysAuthorization' not in run(['strings',str(binary)]), 'Unused Always location permission API in ' + binary.name
assert 'location' not in i.get('UIBackgroundModes',[]),'Background location must remain disabled'
result={'bundle':i['CFBundleIdentifier'],'version':i['CFBundleShortVersionString'],'build':i['CFBundleVersion'],'team':e['com.apple.developer.team-identifier'],'apsEnvironment':e['aps-environment'],'appleLogin':True,'signatureVerified':True,'firebaseProject':f['PROJECT_ID'],'serverCredentialsAbsent':True,'pushDeliveryTested':False,'nativeAppleAuthorizationTested':False,'alwaysLocationApiAbsent':True}
(root/'build/private/ios/artifact-verification.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
