import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/profile.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/app_page.dart';

final publicProfileProvider = FutureProvider.autoDispose
    .family<UserProfile?, String>((ref, userId) {
      return ref.watch(profileRepositoryProvider).fetchProfile(userId);
    });

class PublicProfilePage extends ConsumerWidget {
  const PublicProfilePage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(userId));
    return AppPage(
      appBar: AppBar(title: const Text('個人資訊')),
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
