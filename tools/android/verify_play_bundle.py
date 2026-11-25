#!/usr/bin/env python3
"""Verify the upload signature, bundle structure, manifest and native alignment."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[2]
bundle = root / 'build/app/outputs/bundle/release/app-release.aab'
certificate = root / 'android/signing/coscircle-upload-certificate.pem'
bundletool = os.environ.get('BUNDLETOOL_JAR')
if not bundletool:
    sys.exit('Set BUNDLETOOL_JAR to the official bundletool-all jar.')
java = Path(os.environ['JAVA_HOME']) / 'bin' if os.environ.get('JAVA_HOME') else Path(shutil.which('java')).resolve().parent

def run(command):
    return subprocess.check_output(command, stderr=subprocess.STDOUT)

verified = run([str(java / 'jarsigner'), '-verify', str(bundle)]).decode()
if 'jar verified.' not in verified:
    sys.exit('JAR signature verification failed.')
# Match the actual signer certificate against our exported public upload cert.
signer_pem = run([str(java / 'keytool'), '-printcert', '-jarfile', str(bundle), '-rfc'])
signer_der = subprocess.check_output(['openssl', 'x509', '-outform', 'DER'], input=signer_pem)
expected_der = run(['openssl', 'x509', '-in', str(certificate), '-outform', 'DER'])
if signer_der != expected_der:
    sys.exit('Bundle signer does not match the upload certificate.')
run([str(java / 'java'), '-jar', bundletool, 'validate', '--bundle='+str(bundle)])
manifest = run([str(java / 'java'), '-jar', bundletool, 'dump', 'manifest', '--bundle='+str(bundle), '--module=base'])
xml = ET.fromstring(manifest)
ns = '{http://schemas.android.com/apk/res/android}'
app = xml.find('application')
sdk = xml.find('uses-sdk')
assert xml.attrib['package'] == 'com.hikakineame.coscircle'
assert app.attrib.get(ns+'debuggable', 'false') == 'false'
assert sdk.attrib[ns+'targetSdkVersion'] == '36'
unaligned = []
with zipfile.ZipFile(bundle) as archive:
    assert archive.testzip() is None
    for name in archive.namelist():
        if not name.endswith('.so') or not any('/'+abi+'/' in name for abi in ['arm64-v8a', 'x86_64']):
            continue
        data = archive.read(name)
        assert data[:4] == b'\x7fELF' and data[4] == 2
        endian = '<' if data[5] == 1 else '>'
        offset = struct.unpack_from(endian+'Q', data, 32)[0]
        entry_size, count = struct.unpack_from(endian+'HH', data, 54)
        for index in range(count):
            pos = offset + index * entry_size
            kind = struct.unpack_from(endian+'I', data, pos)[0]
            if kind == 1 and struct.unpack_from(endian+'Q', data, pos+48)[0] < 16384:
                unaligned.append(name)
if unaligned:
    sys.exit('Native libraries lack 16KB ELF alignment: '+str(sorted(set(unaligned))))
report = {
    'package': xml.attrib['package'],
    'versionName': xml.attrib[ns+'versionName'],
    'versionCode': xml.attrib[ns+'versionCode'],
    'minSdk': sdk.attrib[ns+'minSdkVersion'],
    'targetSdk': sdk.attrib[ns+'targetSdkVersion'],
    'bytes': bundle.stat().st_size,
    'sha256': hashlib.sha256(bundle.read_bytes()).hexdigest(),
    'signature': 'verified; matches upload certificate',
    'bundletool': 'validate passed',
    'debuggable': False,
    'native64BitElfAlignment': 'all load segments >= 16KB',
    'runtimeDeviceTest': 'not performed by this verifier; test the Play-delivered build separately',
    'productionSafetyApi': 'verified separately; see docs/deployment/account-safety-2026-11-15.md and line-unlink-2026-11-16.md',
}
output = bundle.parent / 'verification.json'
output.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
