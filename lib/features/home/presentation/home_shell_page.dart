import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/providers/event_providers.dart';
import '../../current_event/presentation/current_event_page.dart';
import '../../events/presentation/event_list_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../social/presentation/social_page.dart';
import '../../../shared/widgets/cos_ui.dart';

class HomeShellPage extends ConsumerStatefulWidget {
  const HomeShellPage({super.key});

  @override
  ConsumerState<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends ConsumerState<HomeShellPage> {
  int _index = 1;
  bool _showingExitConfirm = false;
  static const _destinations = [
    _HomeNavDestination(
      icon: Icons.badge_outlined,
      selectedIcon: Icons.badge,
      label: '名片',
    ),
    _HomeNavDestination(
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      label: '活動',
    ),
    _HomeNavDestination(
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on,
      label: '現場',
    ),
    _HomeNavDestination(
      icon: Icons.diversity_3_outlined,
      selectedIcon: Icons.diversity_3,
      label: '同好',
    ),
    _HomeNavDestination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      label: '設定',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedCurrentEventTarget = ref.watch(
      selectedCurrentEventTargetProvider,
    );
    final pages = [
      const ProfilePage(),
      EventListPage(
        onOpenCurrentEvent: (item) {
          ref
              .read(selectedCurrentEventTargetProvider.notifier)
              .select(item.event.id, dayIndex: item.dayIndex);
          setState(() => _index = 2);
        },
      ),
      CurrentEventPage(
        eventId: selectedCurrentEventTarget?.eventId,
        dayIndex: selectedCurrentEventTarget?.dayIndex ?? 1,
        onOpenEvents: () => setState(() => _index = 1),
      ),
      const SocialPage(),
      const SettingsPage(),
    ];

    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        body: SafeArea(child: pages[_index]),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(CosUi.radiusXl),
                border: Border.all(color: scheme.outlineVariant),
                boxShadow: [CosUi.softShadow(scheme.shadow)],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    for (final entry in _destinations.indexed)
                      Expanded(
                        child: _HomeNavButton(
                          destination: entry.$2,
                          selected: _index == entry.$1,
                          onTap: () {
                            if (_index == entry.$1) return;
                            HapticFeedback.selectionClick();
                            setState(() => _index = entry.$1);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleBackPressed() async {
    if (_index != 1) {
      setState(() => _index = 1);
      return;
    }
    if (_showingExitConfirm) return;
    _showingExitConfirm = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => const CosSafetyConfirmDialog(
        title: '離開 CosCircle？',
        message: '確定要關閉 App 嗎？',
        actionLabel: '離開',
        cancelLabel: '取消',
        icon: Icons.logout_outlined,
      ),
    );
    _showingExitConfirm = false;
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }
}

class _HomeNavDestination {
  const _HomeNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _HomeNavButton extends StatefulWidget {
  const _HomeNavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _HomeNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HomeNavButton> createState() => _HomeNavButtonState();
}

class _HomeNavButtonState extends State<_HomeNavButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final selected = widget.selected;
    final destination = widget.destination;
    final accent = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: AnimatedScale(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.96 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(CosUi.radiusLg),
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer.withValues(alpha: 0.88)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(CosUi.radiusLg),
                border: Border.all(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.24)
                      : Colors.transparent,
                ),
              ),
              child: SizedBox(
                height: 54,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedPositioned(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      top: selected ? 0 : -8,
                      child: AnimatedOpacity(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        opacity: selected ? 1 : 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const SizedBox(width: 22, height: 3),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          scale: selected ? 1.08 : 1,
                          child: Icon(
                            selected
                                ? destination.selectedIcon
                                : destination.icon,
                            color: accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          destination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : accent,
                                fontWeight: selected
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
