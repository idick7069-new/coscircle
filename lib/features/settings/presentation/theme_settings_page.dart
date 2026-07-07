import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/theme_mode_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';

class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMode = ref.watch(appThemeModeProvider);
    return AppPage(
      appBar: AppBar(title: const Text('介面主題')),
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CosPageHeader(
            title: '介面主題',
            subtitle: '選擇活動現場和日常瀏覽都舒服的視覺模式',
            leading: CosIconBubble(icon: Icons.palette_outlined),
          ),
          const SizedBox(height: 8),
          CosCard(
            child: Text(
              '設定會保存在這台裝置，下次開啟 App 時自動套用。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          CosReveal(
            child: _ThemeOptionCard(
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
          ),
          const SizedBox(height: 12),
          CosReveal(
            delay: const Duration(milliseconds: 60),
            child: _ThemeOptionCard(
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
          ),
        ],
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
    return CosCard(
      padding: EdgeInsets.zero,
      selected: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _ThemePreviewScene(
                  colors: colors,
                  selected: selected,
                  dark: mode == CosCircleThemeMode.neonDark,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CosBadge(
                        label: selected ? '使用中' : '可切換',
                        icon: selected
                            ? Icons.check_circle_outline
                            : Icons.swap_horiz,
                        highlighted: selected,
                        color: selected ? scheme.secondary : scheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mode.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mode.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 14),
            Row(
              children: [
                for (final color in colors.indexed) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 8,
                      decoration: BoxDecoration(
                        color: color.$2,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.42),
                        ),
                      ),
                    ),
                  ),
                  if (color.$1 != colors.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreviewScene extends StatelessWidget {
  const _ThemePreviewScene({
    required this.colors,
    required this.selected,
    required this.dark,
  });

  final List<Color> colors;
  final bool selected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = colors.first;
    final accent = colors.length > 1 ? colors[1] : scheme.primary;
    final secondary = colors.length > 2 ? colors[2] : scheme.secondary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 86,
      height: 78,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: base,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected ? [CosUi.softShadow(scheme.primary)] : null,
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 31,
              height: 13,
              decoration: BoxDecoration(
                color: secondary.withValues(alpha: dark ? 0.82 : 0.72),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              width: 44,
              height: 8,
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: 0.18,
                ),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(
              selected ? Icons.auto_awesome : Icons.diversity_3_outlined,
              size: 20,
              color: colors.last,
            ),
          ),
        ],
      ),
    );
  }
}
