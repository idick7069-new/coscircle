import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/theme_mode_provider.dart';
import '../../../core/theme/app_theme.dart';

class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMode = ref.watch(appThemeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('介面主題')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '選擇 CosCircle 的視覺風格',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '設定會保存在這台裝置，下次開啟 App 時自動套用。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _ThemeOptionCard(
              mode: CosCircleThemeMode.neonDark,
              selected: selectedMode == CosCircleThemeMode.neonDark,
              colors: const [
                AppTheme.ink,
                AppTheme.coral,
                AppTheme.cyan,
                AppTheme.sun,
              ],
              onTap: () => ref
                  .read(appThemeModeProvider.notifier)
                  .setMode(CosCircleThemeMode.neonDark),
            ),
            const SizedBox(height: 12),
            _ThemeOptionCard(
              mode: CosCircleThemeMode.morandiLight,
              selected: selectedMode == CosCircleThemeMode.morandiLight,
              colors: const [
                AppTheme.paper,
                AppTheme.blush,
                AppTheme.coral,
                AppTheme.cyan,
              ],
              onTap: () => ref
                  .read(appThemeModeProvider.notifier)
                  .setMode(CosCircleThemeMode.morandiLight),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.mode,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final CosCircleThemeMode mode;
  final bool selected;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    for (final color in colors)
                      Expanded(child: ColoredBox(color: color)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mode.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? Icon(
                        Icons.check_circle,
                        key: const ValueKey('selected'),
                        color: scheme.secondary,
                      )
                    : Icon(
                        Icons.radio_button_unchecked,
                        key: const ValueKey('unselected'),
                        color: scheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
