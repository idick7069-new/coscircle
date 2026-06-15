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
              CosReveal(
                child: _PublicProfileHero(
                  profile: value,
                  onFollowToggle: value.id.isEmpty
                      ? null
                      : () async {
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
                ),
              ),
              if (value.bio.isNotEmpty) ...[
                const SizedBox(height: 14),
                CosReveal(
                  delay: const Duration(milliseconds: 60),
                  child: CosCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CosSectionHeader(
                          title: '自我介紹',
                          subtitle: '先從對方想分享的話題開始',
                          icon: Icons.article_outlined,
                        ),
                        const SizedBox(height: 10),
                        Text(value.bio),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              CosReveal(
                delay: const Duration(milliseconds: 100),
                child: CosCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CosSectionHeader(
                        title: '交流資訊',
                        subtitle: '確認適合開話題的方式與範圍',
                        icon: Icons.forum_outlined,
                      ),
                      const SizedBox(height: 12),
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
              ),
              const SizedBox(height: 14),
              CosReveal(
                delay: const Duration(milliseconds: 140),
                child: CosCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CosSectionHeader(
                        title: '坑單',
                        subtitle: '共同作品是現場認親的捷徑',
                        icon: Icons.label_important_outline,
                      ),
                      const SizedBox(height: 12),
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
              ),
              const SizedBox(height: 14),
              CosReveal(
                delay: const Duration(milliseconds: 180),
                child: CosCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CosSectionHeader(
                        title: '照片牆',
                        subtitle: '看看對方的代表作與風格',
                        icon: Icons.photo_library_outlined,
                      ),
                      const SizedBox(height: 12),
                      if (value.otherPhotoUrls.isEmpty)
                        const _PublicPhotoEmptyState()
                      else
                        _PublicOtherPhotoGrid(photoUrls: value.otherPhotoUrls),
                    ],
                  ),
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

class _PublicProfileHero extends StatelessWidget {
  const _PublicProfileHero({
    required this.profile,
    required this.onFollowToggle,
  });

  final UserProfile profile;
  final Future<void> Function()? onFollowToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosGradientPanel(
      icon: Icons.diversity_3_outlined,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                  ),
                  boxShadow: [CosUi.softShadow(scheme.primary)],
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: scheme.surfaceContainerLowest,
                  backgroundImage: pickedImageProvider(profile.avatarUrl),
                  child: profile.avatarUrl.isEmpty
                      ? Icon(Icons.person, size: 46, color: scheme.primary)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CosBadge(
                      label: profile.isFollowed ? '已在關注名單' : '可加入關注',
                      icon: profile.isFollowed
                          ? Icons.person_pin_circle_outlined
                          : Icons.person_add_alt_1_outlined,
                      highlighted: true,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.nickname.isEmpty ? '未命名使用者' : profile.nickname,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900, height: 1.02),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CosBadge(
                          label: profile.regions.isEmpty
                              ? '尚未設定座標'
                              : profile.regions.join('、'),
                          icon: Icons.explore_outlined,
                        ),
                        CosBadge(
                          label: profile.deepPitWorks.isEmpty
                              ? '深坑待補'
                              : '${profile.deepPitWorks.length} 個深坑',
                          icon: Icons.label_important_outline,
                          color: scheme.secondary,
                        ),
                        CosBadge(
                          label: _publicGenderLabel(profile.gender),
                          icon: Icons.person_outline,
                          color: scheme.tertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PublicSignalRow(profile: profile),
          if (onFollowToggle != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onFollowToggle,
                icon: Icon(
                  profile.isFollowed
                      ? Icons.person_remove_outlined
                      : Icons.person_add_outlined,
                ),
                label: Text(profile.isFollowed ? '取消關注' : '加入關注'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublicSignalRow extends StatelessWidget {
  const _PublicSignalRow({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalWorks =
        profile.deepPitWorks.length + profile.shallowPitWorks.length;
    return Row(
      children: [
        Expanded(
          child: CosMetricTile(
            icon: Icons.label_important_outline,
            label: '坑單',
            value: '$totalWorks',
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CosMetricTile(
            icon: Icons.photo_library_outlined,
            label: '照片',
            value: '${profile.otherPhotoUrls.length}',
            color: scheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CosMetricTile(
            icon: profile.isFollowed
                ? Icons.person_pin_circle_outlined
                : Icons.person_add_alt_1_outlined,
            label: '關係',
            value: profile.isFollowed ? '已關注' : '可關注',
            color: scheme.tertiary,
          ),
        ),
      ],
    );
  }
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CosInfoTile(icon: icon, label: label, value: value),
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
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      emptyText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          )
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

class _PublicPhotoEmptyState extends StatelessWidget {
  const _PublicPhotoEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CosIconBubble(
              icon: Icons.photo_library_outlined,
              color: scheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '對方還沒有放照片牆，可以先從坑單和自我介紹開話題。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
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
        return CosReveal(
          delay: Duration(milliseconds: 40 * index),
          offset: const Offset(0, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
              boxShadow: [
                CosUi.softShadow(Theme.of(context).colorScheme.shadow),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
              child: Image(
                image: pickedImageProvider(photoUrls[index])!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
