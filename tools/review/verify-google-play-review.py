#!/usr/bin/env python3
"""Verify only provisioned review fixtures through the production HTTPS API."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import urllib.error

root = Path(__file__).resolve().parents[2]
result = subprocess.run([
    'gcloud', 'compute', 'ssh', 'coscircle-free-vm', '--project=cos-circle',
    '--zone=us-west1-b', '--account=idick7069@gmail.com',
    '--command=sudo cat /etc/coscircle/google-play-review-accounts.json',
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
state = json.loads(result.stdout)
assert state['namespace'] == 'coscircle-google-play-review-v1'
assert state['event']['id'] and state['circleId']
base = 'https://coscircle.app/api'

def api(path, token=None, body=None, method='GET', expected=200):
    data = None if body is None else json.dumps(body).encode()
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(base+path, data=data, method=method, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    assert response.status == expected, f'{method} {path}: {response.status} != {expected}'
    raw = response.read()
    return json.loads(raw) if raw else None

verified = []
for account in [a for a in state['accounts'] if a['key'] in ['main', 'backup']]:
    login = {'email': account['email'], 'password': account['password']}
    first = api('/auth/login', body=login, method='POST')
    session = api('/auth/login', body=login, method='POST')
    assert str(first['user']['id']) == account['id'] == str(session['user']['id'])
    token = session['token']
    try:
        profile = api('/me', token)
        assert not profile['isAdmin'] and profile['onboardingCompleted']
        assert profile['nickname'] == account['nickname']
        assert profile['bookingVisibility'] == 'circle' and profile['agePublic'] in (False, 0)
        assert profile['bio'] and profile['avatarUrl'] and profile['profileRoles'] and len(profile['pitWorks']) >= 2
        assert api('/me/legal', token)['accepted']
        identities = api('/me/auth-identities', token)
        assert [row['provider'] for row in identities] == ['email']
        friends = api('/friends', token)
        assert {'accepted', 'incoming'} <= {row['status'] for row in friends}
        circles = api('/circles', token)
        circle = next(row for row in circles if str(row['id']) == state['circleId'])
        assert circle['memberCount'] == 4
        bookings = api('/me/bookings', token)
        own = [b for b in bookings if str(b['eventId']) == state['event']['id']]
        assert len(own) == 30
        events = api('/events', token)
        event = next(e for e in events if str(e['id']) == state['event']['id'])
        assert event['isJoined'] and event['startDate'] == state['event']['startDate']
        participants = api('/events/'+state['event']['id']+'/participants', token)
        assert {str(p['userId']) for p in participants} == {a['id'] for a in state['accounts']}
        partners = api('/social/same-works', token)
        assert any(str(p['userId']) in {a['id'] for a in state['accounts'] if a['id'] != account['id']} for p in partners['items'])
        meetup = api('/events/'+state['event']['id']+'/meetups', token)
        assert any(str(m['circleId']) == state['circleId'] for m in meetup)
        api('/admin/stats', token, expected=403)
        if account['key'] == 'backup':
            api('/circles/'+state['circleId']+'/members/me', token, method='DELETE', expected=204)
            try:
                hidden = api('/events/'+state['event']['id']+'/participants', token)
                assert hidden and all(str(p['userId']) == account['id'] for p in hidden)
            finally:
                api('/circles/join', token, {'invite':state['inviteCode']}, 'POST', expected=204)
        with urllib.request.urlopen(profile['avatarUrl'], timeout=30) as image:
            assert image.status == 200 and image.headers.get('Content-Type', '').startswith('image/')
        verified.append({'key':account['key'],'userId':account['id'],'nonAdmin':True,'profileCompleted':True,
                         'repeatedLogin':True,'bookings':len(own),'circleMembers':4,'friendStates':['accepted','incoming'],
                         'sameWorks':True,'mapMeetup':True})
    finally:
        api('/auth/logout', token, {}, 'POST', expected=204)

private = root / 'build/private'
private.mkdir(parents=True, exist_ok=True)
os.chmod(private, 0o700)
text = 'CosCircle Google Play review credentials — app login only\n\n'
for account in [a for a in state['accounts'] if a['key'] in ['main', 'backup']]:
    text += f"{account['key']}\nEmail: {account['email']}\nPassword: {account['password']}\n\n"
text += 'Web app: https://coscircle.app/app/#/login\n'
text += f"Demo event: {state['event']['startDate']} through {state['event']['endDate']} (Taipei time)\n"
text += 'Companion accounts are demo-only. These emails are app identifiers, not provisioned mailboxes.\n'
credential_file = private / 'google-play-review-access.txt'
credential_file.write_text(text)
os.chmod(credential_file, 0o600)
report = {'verified':verified,'event':state['event'],'circleId':state['circleId'],
          'circleOnlyVisibilityTest':'passed','credentialFile':str(credential_file),
          'noOtpForEmailLogin':True,'loginEndpoint':base+'/auth/login'}
(private / 'google-play-review-verification.json').write_text(json.dumps(report, indent=2)+'\n')
os.chmod(private / 'google-play-review-verification.json',0o600)
print(json.dumps(report,indent=2))
