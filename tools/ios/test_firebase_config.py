import copy
from pathlib import Path
import plistlib
import tempfile
import unittest
from firebase_config import load_firebase_ios

class FirebaseIOSConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'GoogleService-Info.plist'
        self.config = {'BUNDLE_ID': 'com.hikakineame.coscircle', 'PROJECT_ID': 'coscircle',
                       'GOOGLE_APP_ID': '1:123456:ios:abcdef', 'GCM_SENDER_ID': '123456',
                       'API_KEY': 'AIzaFAKE_UNIT_TEST_VALUE', 'STORAGE_BUCKET': 'coscircle.firebasestorage.app'}
    def write(self, config):
        self.path.write_bytes(plistlib.dumps(config))
    def test_valid_ios_config_maps_every_required_field(self):
        self.write(self.config)
        result = load_firebase_ios(self.path)
        self.assertEqual(result['FIREBASE_IOS_APP_ID'], self.config['GOOGLE_APP_ID'])
        self.assertEqual(result['FIREBASE_IOS_PROJECT_ID'], 'coscircle')
        self.assertEqual(len(result), 5)
    def test_wrong_app_project_and_android_app_ids_are_rejected(self):
        for field, value in [('BUNDLE_ID','com.coscircle.coscircle'), ('PROJECT_ID','another-project'),
                             ('GOOGLE_APP_ID','1:123456:android:abcdef'), ('GCM_SENDER_ID','654321')]:
            with self.subTest(field=field):
                config = copy.copy(self.config);config[field] = value;self.write(config)
                with self.assertRaises(ValueError):load_firebase_ios(self.path)
    def test_missing_required_fields_and_invalid_keys_are_rejected(self):
        for field in ['GOOGLE_APP_ID','GCM_SENDER_ID','API_KEY','STORAGE_BUCKET']:
            config = copy.copy(self.config);config.pop(field);self.write(config)
            with self.assertRaises(ValueError):load_firebase_ios(self.path)
        config = copy.copy(self.config);config['API_KEY']='not-a-key';self.write(config)
        with self.assertRaises(ValueError):load_firebase_ios(self.path)
    def test_missing_and_malformed_files_do_not_build_silently(self):
        with self.assertRaises(ValueError):load_firebase_ios(self.path)
        self.path.write_text('not a plist')
        with self.assertRaises(ValueError):load_firebase_ios(self.path)

if __name__ == '__main__':unittest.main()
