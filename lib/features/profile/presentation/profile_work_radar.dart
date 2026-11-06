import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/work.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../shared/widgets/cos_ui.dart';

final radarViewerProfileProvider = FutureProvider.autoDispose
    .family<UserProfile?, int>((ref, version) async {
      final client = ref.watch(apiClientProvider);
      final token = await client.restoreAuthToken();
      if (!ref.mounted || client.sessionVersion != version || token == null) {
        return null;
      }
      final operation = ref.watch(profileRepositoryProvider).beginOperation();
      ref.onDispose(operation.cancel);
      return operation.currentProfile();
    });

class _RadarViewer extends ConsumerWidget {
  const _RadarViewer({required this.builder});
  final Widget Function(BuildContext, AsyncValue<UserProfile?>) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<int>(
      valueListenable: ref.watch(apiClientProvider).sessionChanges,
      builder: (context, version, _) => Consumer(
        builder: (context, ref, _) =>
            builder(context, ref.watch(radarViewerProfileProvider(version))),
      ),
    );
  }
}

Set<String> commonProfileWorkIds(UserProfile? viewer, UserProfile profile) {
  if (viewer == null || viewer.id == profile.id || profile.isMe) return {};
  final own = {
    ...viewer.pitWorks.map((work) => work.id),
    ...viewer.deepPitWorks.map((work) => work.id),
    ...viewer.shallowPitWorks.map((work) => work.id),
  };
  return {
        ...profile.pitWorks,
        ...profile.deepPitWorks,
        ...profile.shallowPitWorks,
      }
      .map((work) => work.id)
      .where((id) => id.isNotEmpty && own.contains(id))
      .toSet();
}

class ProfileCommonWorkNotice extends ConsumerWidget {
  const ProfileCommonWorkNotice({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _RadarViewer(
      builder: (context, viewer) {
        final ids = commonProfileWorkIds(
          viewer.isLoading || viewer.hasError ? null : viewer.asData?.value,
          profile,
        );
        if (ids.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Semantics(
            liveRegion: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(CosUi.radiusMd),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.radar, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '同坑雷達！你們有 ${ids.length} 部共同作品',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProfileWorkRadar extends ConsumerWidget {
  const ProfileWorkRadar({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _RadarViewer(
      builder: (context, viewer) {
        final common = commonProfileWorkIds(
          viewer.isLoading || viewer.hasError ? null : viewer.asData?.value,
          profile,
        );
        final scheme = Theme.of(context).colorScheme;
        return CosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CosSectionHeader(
                title: '坑單',
                icon: Icons.label_important_outline,
              ),
              if (viewer.hasError && !profile.isMe)
                TextButton.icon(
                  onPressed: () => ref.invalidate(radarViewerProfileProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新讀取同坑雷達'),
                ),
              const SizedBox(height: 12),
              _RadarWorkTags(
                title: '深坑',
                works: profile.deepPitWorks,
                common: common,
                emptyText: '尚未新增深坑',
                color: scheme.primary,
              ),
              const SizedBox(height: 12),
              _RadarWorkTags(
                title: '淺坑',
                works: profile.shallowPitWorks,
                common: common,
                emptyText: '尚未新增淺坑',
                color: scheme.secondary,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RadarWorkTags extends StatelessWidget {
  const _RadarWorkTags({
    required this.title,
    required this.works,
    required this.common,
    required this.emptyText,
    required this.color,
  });

  final String title;
  final List<WorkTag> works;
  final Set<String> common;
  final String emptyText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (works.isEmpty)
          Text(emptyText, style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final work in works)
                Semantics(
                  label: common.contains(work.id)
                      ? '${work.name}，與我同坑'
                      : work.name,
                  child: CosBadge(
                    label: work.name,
                    color: common.contains(work.id) ? scheme.tertiary : color,
                    icon: common.contains(work.id) ? Icons.radar : null,
                    highlighted: common.contains(work.id),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
