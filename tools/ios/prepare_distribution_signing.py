#!/usr/bin/env python3
"""Install an app-scoped provisioning profile and isolated distribution keychain."""
import json, os, plistlib, secrets, shutil, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'build/private/ios'
def run(args):
    r=subprocess.run(args,capture_output=True)
    if r.returncode: raise SystemExit('Signing setup failed: '+r.stderr.decode(errors='replace')[-500:])
    return r.stdout
v=json.loads((p/'profile-metadata.json').read_text())
cert=p/'distribution.pem'
cert.write_bytes(run(['openssl','x509','-inform','DER','-in',str(p/'distribution.cer')]))
a=run(['openssl','x509','-in',str(cert),'-pubkey','-noout'])
b=run(['openssl','pkey','-in',str(p/'distribution.key'),'-pubout'])
assert a==b,'Certificate does not match the local private key'
password_file=p/'signing-keychain-password'
if not password_file.exists(): password_file.write_text(secrets.token_urlsafe(32));password_file.chmod(0o600)
password=password_file.read_text()
keychain=p/'coscircle-distribution.keychain-db'
if not keychain.exists():run(['security','create-keychain','-p',password,str(keychain)])
run(['security','unlock-keychain','-p',password,str(keychain)])
run(['security','set-keychain-settings','-lut','21600',str(keychain)])
p12=p/'distribution.p12'
env=dict(os.environ,COSCIRCLE_P12_PASSWORD=password)
r=subprocess.run(['openssl','pkcs12','-export','-legacy','-inkey',str(p/'distribution.key'),'-in',str(cert),'-out',str(p12),'-passout','env:COSCIRCLE_P12_PASSWORD'],env=env,capture_output=True)
assert r.returncode==0,'Could not prepare signing identity'
p12.chmod(0o600)
identities=run(['security','find-identity','-v','-p','codesigning',str(keychain)]).decode()
if 'Apple Distribution:' not in identities:
 run(['security','import',str(p12),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign','-T','/usr/bin/security'])
 run(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain)])
for folder in [Path.home()/'Library/MobileDevice/Provisioning Profiles',Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles']:
 folder.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(p/'CosCircle_App_Store_2026.mobileprovision',folder/(v['uuid']+'.mobileprovision'))
print(run(['security','find-identity','-v','-p','codesigning',str(keychain)]).decode().strip())
print('Installed app-specific profile and isolated distribution signing keychain.')
