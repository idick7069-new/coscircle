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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CosUi.radiusXl),
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.badge_outlined),
                      selectedIcon: Icon(Icons.badge),
                      label: '名片',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.event_note_outlined),
                      selectedIcon: Icon(Icons.event_note),
                      label: '活動',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.location_on_outlined),
                      selectedIcon: Icon(Icons.location_on),
                      label: '現場',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.diversity_3_outlined),
                      selectedIcon: Icon(Icons.diversity_3),
                      label: '同好',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: '設定',
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
      builder: (context) => AlertDialog(
        title: const Text('離開 CosCircle？'),
        content: const Text('確定要關閉 App 嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('離開'),
          ),
        ],
      ),
    );
    _showingExitConfirm = false;
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }
}
