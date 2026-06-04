import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/profile.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/app_page.dart';

final publicProfileProvider = FutureProvider.autoDispose
    .family<UserProfile?, String>((ref, publicCode) {
      return ref.watch(profileRepositoryProvider).fetchProfile(publicCode);
    });

class PublicProfilePage extends ConsumerWidget {
  const PublicProfilePage({super.key, required this.publicCode});

  final String publicCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(publicCode));
    return AppPage(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
          icon: const BackButtonIcon(),
        ),
        title: const Text('個人資訊'),
      ),
      child: profile.when(
        data: (value) {
          if (value == null) return const Center(child: Text('找不到使用者'));
          return ListView(
            children: [
              Center(
                child: CircleAvatar(
                  radius: 54,
                  backgroundImage: pickedImageProvider(value.avatarUrl),
                  child: value.avatarUrl.isEmpty
                      ? const Icon(Icons.person, size: 48)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                value.nickname,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (value.id.isNotEmpty)
                FilledButton.icon(
                  onPressed: () async {
                    if (value.isFollowed) {
                      await ref
                          .read(profileRepositoryProvider)
                          .unfollowUser(value.id);
                    } else {
                      await ref
                          .read(profileRepositoryProvider)
                          .followUser(value.id);
                    }
                    ref.invalidate(publicProfileProvider(publicCode));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(value.isFollowed ? '已取消關注' : '已加入關注'),
                      ),
                    );
                  },
                  icon: Icon(
                    value.isFollowed
                        ? Icons.person_remove_outlined
                        : Icons.person_add_outlined,
                  ),
                  label: Text(value.isFollowed ? '取消關注' : '加入關注'),
                ),
              if (value.bio.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(value.bio),
              ],
              if (value.facebookUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.facebook),
                  title: const Text('Facebook'),
                  subtitle: Text(value.facebookUrl),
                ),
              ],
              const SizedBox(height: 16),
              Text('坑單', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (value.pitWorks.isEmpty)
                const Text('尚未新增坑單')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final work in value.pitWorks)
                      Chip(label: Text(work.name)),
                  ],
                ),
            ],
          );
        },
        error: (error, stack) => Center(child: Text('個人資訊載入失敗：$error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
