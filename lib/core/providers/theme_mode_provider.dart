import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CosCircleThemeMode {
  neonDark('neon_dark', '午夜像素', '深夜藍底，薄荷綠與淡紫像素'),
  morandiLight('morandi_light', '冷調微光', '冷藍面板，淡紫主色與冰藍重點色'),
  whitePixel('white_pixel', '白晝像素', '白色底、淺灰面板，青綠與紫色重點色');

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
  static const _storageKey = 'coscircle_pixel_theme_mode_v1';
  int _revision = 0;

  @override
  CosCircleThemeMode build() {
    final revision = ++_revision;
    ref.onDispose(() => _revision++);
    _restore(revision);
    return CosCircleThemeMode.neonDark;
  }

  Future<void> setMode(CosCircleThemeMode mode) async {
    final revision = ++_revision;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    if (_revision != revision) return;
    await prefs.setString(_storageKey, mode.storageValue);
  }

  Future<void> _restore(int revision) async {
    final prefs = await SharedPreferences.getInstance();
    if (_revision != revision) return;
    final stored = prefs.getString(_storageKey);
    state = CosCircleThemeMode.fromStorage(stored);
    if (stored == null) {
      await prefs.setString(
        _storageKey,
        CosCircleThemeMode.neonDark.storageValue,
      );
    }
  }
}
