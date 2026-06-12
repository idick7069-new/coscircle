import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final oobeServiceProvider = Provider<OobeService>((ref) => OobeService());

class OobeService {
  static const _completedKeyPrefix = 'oobe_completed_v1';

  Future<bool> isCompleted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  Future<void> markCompleted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }

  Future<void> reset(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }

  String _key(String userId) => '${_completedKeyPrefix}_$userId';
}
