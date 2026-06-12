import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/work.dart';
import '../../../core/models/profile.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';

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
              CosCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                          ],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 54,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CosBadge(
                          label: value.regions.isEmpty
                              ? '尚未設定座標'
                              : value.regions.join('、'),
                          icon: Icons.explore_outlined,
                        ),
                        CosBadge(
                          label: value.deepPitWorks.isEmpty
                              ? '深坑待補'
                              : '${value.deepPitWorks.length} 個深坑',
                          icon: Icons.label_important_outline,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        CosBadge(
                          label: _publicGenderLabel(value.gender),
                          icon: Icons.person_outline,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ],
                    ),
                    if (value.id.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
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
                                content: Text(
                                  value.isFollowed ? '已取消關注' : '已加入關注',
                                ),
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
                      ),
                    ],
                  ],
                ),
              ),
              if (value.bio.isNotEmpty) ...[
                const SizedBox(height: 14),
                CosCard(child: Text(value.bio)),
              ],
              const SizedBox(height: 14),
              CosCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '交流資訊',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _PublicInfoTile(
                      icon: Icons.cake_outlined,
                      label: '年齡',
                      value: value.age.isEmpty ? '尚未設定' : value.age,
                    ),
                    _PublicInfoTile(
                      icon: Icons.wc_outlined,
                      label: '性別',
                      value: _publicGenderLabel(value.gender),
                    ),
                    _PublicInfoTile(
                      icon: Icons.explore_outlined,
                      label: '座標',
                      value: value.regions.isEmpty
                          ? '尚未設定'
                          : value.regions.join('、'),
                    ),
                    _PublicInfoTile(
                      icon: Icons.directions_run_outlined,
                      label: '跑場範圍',
                      value: value.travelRegions.isEmpty
                          ? '尚未設定'
                          : value.travelRegions.join('、'),
                    ),
                    if (value.facebookUrl.isNotEmpty)
                      _PublicInfoTile(
                        icon: Icons.facebook,
                        label: 'Facebook',
                        value: value.facebookUrl,
                      ),
                    if (value.landmine.isNotEmpty)
                      _PublicInfoTile(
                        icon: Icons.warning_amber_outlined,
                        label: '雷點',
                        value: value.landmine,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              CosCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('坑單', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    _PublicWorkTags(
                      title: '深坑',
                      works: value.deepPitWorks,
                      emptyText: '尚未新增深坑',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    _PublicWorkTags(
                      title: '淺坑',
                      works: value.shallowPitWorks,
                      emptyText: '尚未新增淺坑',
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              CosCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('照片牆', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (value.otherPhotoUrls.isEmpty)
                      const Text('尚未新增其他照片')
                    else
                      _PublicOtherPhotoGrid(photoUrls: value.otherPhotoUrls),
                  ],
                ),
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

String _publicGenderLabel(String value) {
  return switch (value) {
    'male' => '生理男',
    'female' => '生理女',
    _ => '不公開',
  };
}

class _PublicInfoTile extends StatelessWidget {
  const _PublicInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class _PublicWorkTags extends StatelessWidget {
  const _PublicWorkTags({
    required this.title,
    required this.works,
    required this.emptyText,
    required this.color,
  });

  final String title;
  final List<WorkTag> works;
  final String emptyText;
  final Color color;

  @override
  Widget build(BuildContext context) {
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
                CosBadge(label: work.name, color: color),
            ],
          ),
      ],
    );
  }
}

class _PublicOtherPhotoGrid extends StatelessWidget {
  const _PublicOtherPhotoGrid({required this.photoUrls});

  final List<String> photoUrls;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photoUrls.length.clamp(0, 3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image(
            image: pickedImageProvider(photoUrls[index])!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }
}
