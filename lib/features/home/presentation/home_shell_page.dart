import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  int _index = 2;

  @override
  Widget build(BuildContext context) {
    final selectedCurrentEventId = ref.watch(selectedCurrentEventIdProvider);
    final pages = [
      const ProfilePage(),
      EventListPage(
        onOpenCurrentEvent: (event) {
          ref.read(selectedCurrentEventIdProvider.notifier).select(event.id);
          setState(() => _index = 2);
        },
      ),
      CurrentEventPage(eventId: selectedCurrentEventId),
      const SocialPage(),
      const SettingsPage(),
    ];

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
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
    );
  }
}
