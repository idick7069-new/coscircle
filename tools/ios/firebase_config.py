"""Validate Firebase iOS configuration before it is included in any build."""
import plistlib
import re
from pathlib import Path

BUNDLE = 'com.hikakineame.coscircle'
PROJECT = 'coscircle'
FIELDS = {'API_KEY': 'API_KEY', 'APP_ID': 'GOOGLE_APP_ID', 'SENDER_ID': 'GCM_SENDER_ID',
          'PROJECT_ID': 'PROJECT_ID', 'STORAGE_BUCKET': 'STORAGE_BUCKET'}

def load_firebase_ios(path: Path):
    try:
        with path.open('rb') as stream:
            config = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException):
        raise ValueError('Download the Firebase iOS plist first: python3 tools/ios/fetch_firebase_config.py') from None
    if config.get('BUNDLE_ID') != BUNDLE or config.get('PROJECT_ID') != PROJECT:
        raise ValueError('Firebase configuration belongs to a different app or project.')
    values = {'FIREBASE_IOS_' + name: config.get(source) for name, source in FIELDS.items()}
    if any(not isinstance(value, str) or not value for value in values.values()):
        raise ValueError('Firebase iOS plist is missing required fields.')
    match = re.fullmatch(r'1:(\d+):ios:[a-fA-F0-9]+', values['FIREBASE_IOS_APP_ID'])
    if not match or match[1] != values['FIREBASE_IOS_SENDER_ID']:
        raise ValueError('Firebase iOS app ID and sender ID must match; Android IDs are not accepted.')
    if not values['FIREBASE_IOS_API_KEY'].startswith('AIza'):
        raise ValueError('Invalid Firebase iOS API key.')
    return values
