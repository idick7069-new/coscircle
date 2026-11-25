#!/usr/bin/env python3
"""Upload the verified archive using the account already authorized in Xcode."""
import argparse, json, plistlib, shlex, subprocess
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--build-number',default='8');args=parser.parse_args()
root=Path(__file__).resolve().parents[2];p=root/'build/private/ios'
subprocess.run(['python3',str(root/'tools/ios/verify_store_artifact.py'),'--build-number',args.build_number],check=True)
v=plistlib.loads((p/'ExportOptions.plist').read_bytes());v['destination']='upload'
options=p/'UploadOptions.plist';options.write_bytes(plistlib.dumps(v))
keychain=p/'coscircle-distribution.keychain-db'
previous=shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))
password=(p/'signing-keychain-password').read_text()
unlock = subprocess.run(['security','unlock-keychain','-p',password,str(keychain)],capture_output=True)
if unlock.returncode: raise SystemExit('Unlock the dedicated distribution keychain before uploading.')
if str(keychain) not in previous:subprocess.run(['security','list-keychains','-d','user','-s',*previous,str(keychain)],check=True)
try:
 subprocess.run(['xcodebuild','-exportArchive','-archivePath',str(root/'build/ios/archive/Runner.xcarchive'),'-exportOptionsPlist',str(options),'-exportPath',str(p/'upload')],check=True,cwd=root)
finally:
 if str(keychain) not in previous:
  current=shlex.split(subprocess.check_output(['security','list-keychains','-d','user'],text=True))
  subprocess.run(['security','list-keychains','-d','user','-s',*[x for x in current if x!=str(keychain)]],check=True)
print('Upload command completed. Confirm build processing and availability in App Store Connect.')
