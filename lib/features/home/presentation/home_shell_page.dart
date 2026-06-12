import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/providers/event_providers.dart';
import '../../current_event/presentation/current_event_page.dart';
import '../../events/presentation/event_list_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../social/presentation/social_page.dart';

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
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '個人',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_outlined),
                selectedIcon: Icon(Icons.event),
                label: '活動',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: '當前',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: '社交',
              ),
              NavigationDestination(icon: Icon(Icons.menu), label: '其他'),
            ],
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
