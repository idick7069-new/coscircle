#!/usr/bin/env python3
"""Provision the explicitly authorized, message-send-only Firebase service account."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PROJECT = 'coscircle'
ACCOUNT = 'idick7069@gmail.com'
EMAIL = 'coscircle-push-sender@coscircle.iam.gserviceaccount.com'
ROLE = 'projects/coscircle/roles/coscirclePushSender'
private = ROOT / 'build/private/ios'
private.mkdir(parents=True, exist_ok=True)
private.chmod(0o700)

def gcloud(args, missing=False):
    process = subprocess.run(['gcloud', *args, '--project=' + PROJECT, '--account=' + ACCOUNT, '--quiet'], capture_output=True, text=True)
    if process.returncode:
        if missing and ('NOT_FOUND' in process.stderr or 'does not exist' in process.stderr):
            return None
        log = private / 'fcm-provision-error.log'
        log.write_text(process.stderr);log.chmod(0o600)
        raise SystemExit('GCP operation failed; details kept in the private provisioning log.')
    return json.loads(process.stdout) if process.stdout.strip() else {}

role = gcloud(['iam','roles','describe','coscirclePushSender','--format=json'], missing=True)
if role is None:
    role = gcloud(['iam','roles','create','coscirclePushSender','--title=CosCircle Push Sender',
                   '--description=Only send Firebase Cloud Messaging messages for CosCircle',
                   '--permissions=cloudmessaging.messages.create','--stage=GA','--format=json'])
if set(role.get('includedPermissions',[])) != {'cloudmessaging.messages.create'}:
    raise SystemExit('Existing role has unexpected permissions; refusing to broaden or repurpose it.')
service = gcloud(['iam','service-accounts','describe',EMAIL,'--format=json'], missing=True)
if service is None:
    service = gcloud(['iam','service-accounts','create','coscircle-push-sender','--display-name=CosCircle Push Sender','--format=json'])
policy = gcloud(['projects','get-iam-policy',PROJECT,'--format=json'])
member = 'serviceAccount:' + EMAIL
if not any(binding.get('role') == ROLE and member in binding.get('members',[]) for binding in policy.get('bindings',[])):
    gcloud(['projects','add-iam-policy-binding',PROJECT,'--member='+member,'--role='+ROLE,'--condition=None','--format=json'])
credential = private / 'firebase-push-sender.json'
if not credential.exists():
    old = os.umask(0o077)
    try:
        gcloud(['iam','service-accounts','keys','create',str(credential),'--iam-account='+EMAIL,'--format=json'])
    finally:
        os.umask(old)
credential.chmod(0o600)
values = json.loads(credential.read_text())
if values.get('client_email') != EMAIL or values.get('project_id') != PROJECT:
    raise SystemExit('Credential does not match the intended sender account.')
report = {'project':PROJECT,'principal':EMAIL,'role':ROLE,'permissions':role['includedPermissions'],
          'keyId':values.get('private_key_id'),'credentialFileMode':'0600'}
(private/'fcm-provision-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('Prepared dedicated Firebase sender with message-send-only permission; private credential stored mode 0600.')
