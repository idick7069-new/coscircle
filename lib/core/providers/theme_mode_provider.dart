import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CosCircleThemeMode {
  neonDark('neon_dark', '星夜暗色', '深色舞台、照片聚焦、活動現場辨識清楚'),
  morandiLight('morandi_light', '社群亮色', '明亮友善、作品標籤清楚、日常瀏覽舒服');

  const CosCircleThemeMode(this.storageValue, this.label, this.description);

  final String storageValue;
  final String label;
  final String description;

  static CosCircleThemeMode fromStorage(String? value) {
    return CosCircleThemeMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => CosCircleThemeMode.neonDark,
    );
  }
}

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, CosCircleThemeMode>(
      AppThemeModeController.new,
    );

class AppThemeModeController extends Notifier<CosCircleThemeMode> {
  static const _storageKey = 'coscircle_theme_mode';

  @override
  CosCircleThemeMode build() {
    _restore();
    return CosCircleThemeMode.neonDark;
  }

  Future<void> setMode(CosCircleThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mode.storageValue);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = CosCircleThemeMode.fromStorage(prefs.getString(_storageKey));
  }
}
