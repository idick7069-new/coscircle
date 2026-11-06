import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CosCircleThemeMode {
  neonDark('neon_dark', '夜間撞色', '柔和深色，保留鮮明色彩'),
  morandiLight('morandi_light', '活力亮色', '清爽明亮，珊瑚紅與墨綠撞色');

  const CosCircleThemeMode(this.storageValue, this.label, this.description);

  final String storageValue;
  final String label;
  final String description;

  static CosCircleThemeMode fromStorage(String? value) {
    return CosCircleThemeMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => CosCircleThemeMode.morandiLight,
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
    return CosCircleThemeMode.morandiLight;
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
