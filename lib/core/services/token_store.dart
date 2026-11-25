import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native secrets live in Keychain/Keystore. Web authentication uses HttpOnly cookies.
class TokenStore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _key = 'coscircle_session_v2';

  Future<String?> read() async {
    if (kIsWeb) return null;
    final preferences = await SharedPreferences.getInstance();
    var value = await _storage.read(key: _key);
    final legacy = preferences.getString('auth_token');
    if (value == null && legacy != null && legacy.isNotEmpty) {
      await _storage.write(key: _key, value: legacy);
      value = legacy;
    }
    if (legacy != null) await preferences.remove('auth_token');
    return value;
  }

  Future<void> write(String? value) async {
    if (!kIsWeb) {
      if (value == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: value);
      }
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('auth_token');
    if (kIsWeb) await preferences.setBool('web_signed_out', value == null);
  }
}
