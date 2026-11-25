#!/usr/bin/env python3
"""Run interactively: safely configure LINE credentials on the production VM."""
import getpass
import json
import re
import shlex
import subprocess
import sys

channel = (sys.argv[1] if len(sys.argv) == 2 else input('New LINE Login Channel ID: ')).strip()
if not re.fullmatch(r'\d{6,20}', channel):
    raise SystemExit('Invalid Channel ID')
secret = getpass.getpass('New LINE Channel secret (hidden): ').strip()
if not re.fullmatch(r'[a-fA-F0-9]{32}', secret):
    raise SystemExit('Expected the 32-character Channel secret from LINE Developers.')
remote = r'''
import json,sys,os,re,subprocess,datetime
from pathlib import Path
payload=json.load(sys.stdin)
channel=payload['channel'];secret=payload['secret']
assert re.fullmatch(r'\d{6,20}',channel) and re.fullmatch(r'[a-fA-F0-9]{32}',secret)
p=Path('/etc/coscircle/api.env');before=p.read_bytes()
# Provider changes can change LINE subjects; do not strand any existing LINE identities.
result=subprocess.check_output(['mysql','--batch','--skip-column-names','coscircle','-e',"SELECT COUNT(*) FROM user_auth_identities WHERE provider='line'"]).decode().strip()
text=before.decode();old=re.search(r'^LINE_LOGIN_CHANNEL_ID=[\"\']?(\d+)',text,re.M)
if int(result)>0 and (not old or old[1]!=channel):raise SystemExit('Existing LINE identities require migration review before changing Channel.')
release=Path('/opt/coscircle/api/current')
assert (release/'src/line-web-login.js').is_file(), 'Deploy the LINE Web routes first.'
backup=Path('/var/backups/coscircle')/('line-config-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')+'.env')
fd=os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'wb') as f:f.write(before)
values={'LINE_LOGIN_CHANNEL_ID':channel,'LINE_LOGIN_CHANNEL_SECRET':secret,'LINE_LOGIN_ENABLED':'true'}
lines=[line for line in text.splitlines() if not any(line.startswith(key+'=') for key in values)]
lines += [key+'='+json.dumps(value) for key,value in values.items()]
tmp=p.with_name('api.env.line-next');fd=os.open(tmp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:f.write('\n'.join(lines)+'\n')
os.chown(tmp,p.stat().st_uid,p.stat().st_gid);os.replace(tmp,p)
subprocess.run(['systemctl','restart','coscircle-api'],check=True)
import time,urllib.request
healthy=False
for attempt in range(20):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/api/auth/line/config',timeout=3) as response:
            config=json.load(response)
        if config.get('channelId')==channel and config.get('webEnabled') is True:
            healthy=True;break
    except Exception:pass
    time.sleep(1)
if not healthy:
    p.write_bytes(before)
    subprocess.run(['systemctl','restart','coscircle-api'],check=True)
    raise SystemExit('API configuration check failed; previous environment restored.')
print('LINE configuration updated; secret was not printed. Root-only previous configuration: '+str(backup))
'''
command = 'sudo python3 -c ' + shlex.quote(remote)
subprocess.run(['gcloud','compute','ssh','coscircle-free-vm','--zone=us-west1-b',
    '--project=cos-circle','--account=idick7069@gmail.com','--command='+command],
    input=json.dumps({'channel':channel,'secret':secret}),text=True,check=True)
