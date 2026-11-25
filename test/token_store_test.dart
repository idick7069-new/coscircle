import 'package:coscircle/core/services/token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'upgrade preserves the existing login while removing its plain preference',
    () async {
      SharedPreferences.setMockInitialValues({'auth_token': 'legacy-session'});
      final store = TokenStore();
      expect(await store.read(), 'legacy-session');
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        isNull,
      );
      expect(await store.read(), 'legacy-session');
      expect(
        await const FlutterSecureStorage().read(key: 'coscircle_session_v2'),
        'legacy-session',
      );
    },
  );
  test(
    'login and logout never persist a reusable token in plain preferences',
    () async {
      final store = TokenStore();
      await store.write('new-session');
      expect(await store.read(), 'new-session');
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        isNull,
      );
      await store.write(null);
      expect(await store.read(), isNull);
    },
  );
}
