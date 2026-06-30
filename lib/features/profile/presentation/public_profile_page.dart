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
          if (value == null) {
            return _PublicProfileMessageState(
              icon: Icons.person_search_outlined,
              title: '找不到這張名片',
              message: '這個分享碼可能已失效，或對方尚未完成公開名片。',
              actionLabel: '回到首頁',
              onAction: () => context.go('/'),
            );
          }
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
                  onBlock: value.id.isEmpty
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) {
                              final scheme = Theme.of(context).colorScheme;
                              return AlertDialog(
                                title: Text('封鎖 ${value.nickname}？'),
                                content: const Text(
                                  '封鎖後對方將看不到你的個人資訊、場次預定與現場訊號，也不能再關注你。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('返回'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: scheme.error,
                                      foregroundColor: scheme.onError,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('封鎖'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (confirmed != true) return;
                          await ref
                              .read(profileRepositoryProvider)
                              .blockUser(value.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已封鎖使用者')),
                          );
                          context.go('/');
                        },
                ),
              ),
              const SizedBox(height: 14),
              CosReveal(
                delay: const Duration(milliseconds: 45),
                child: _PublicProfileConversationCard(profile: value),
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
        error: (error, stack) => _PublicProfileMessageState(
          icon: Icons.wifi_off_outlined,
          title: '個人資訊載入失敗',
          message: '$error',
          actionLabel: '重新整理',
          onAction: () => ref.invalidate(publicProfileProvider(publicCode)),
        ),
        loading: () => const _PublicProfileLoadingState(),
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

class _PublicProfileLoadingState extends StatelessWidget {
  const _PublicProfileLoadingState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        CosGradientPanel(
          icon: Icons.diversity_3_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest.withValues(
                        alpha: 0.56,
                      ),
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PublicSkeletonLine(widthFactor: 0.46),
                        SizedBox(height: 10),
                        _PublicSkeletonLine(widthFactor: 0.86, height: 22),
                        SizedBox(height: 10),
                        _PublicSkeletonLine(widthFactor: 0.62),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(child: _PublicSkeletonMetric()),
                  SizedBox(width: 8),
                  Expanded(child: _PublicSkeletonMetric()),
                  SizedBox(width: 8),
                  Expanded(child: _PublicSkeletonMetric()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const CosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PublicSkeletonLine(widthFactor: 0.5, height: 18),
              SizedBox(height: 12),
              _PublicSkeletonLine(widthFactor: 0.92),
              SizedBox(height: 8),
              _PublicSkeletonLine(widthFactor: 0.68),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicProfileMessageState extends StatelessWidget {
  const _PublicProfileMessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        CosGradientPanel(
          icon: icon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CosIconBubble(icon: icon, color: scheme.primary, size: 52),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(
                  actionLabel == '重新整理' ? Icons.refresh : Icons.home_outlined,
                ),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicSkeletonMetric extends StatelessWidget {
  const _PublicSkeletonMetric();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PublicSkeletonLine(widthFactor: 0.58, height: 16),
            SizedBox(height: 8),
            _PublicSkeletonLine(widthFactor: 0.82, height: 10),
          ],
        ),
      ),
    );
  }
}

class _PublicSkeletonLine extends StatelessWidget {
  const _PublicSkeletonLine({required this.widthFactor, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: SizedBox(height: height),
      ),
    );
  }
}

class _PublicProfileHero extends StatelessWidget {
  const _PublicProfileHero({
    required this.profile,
    required this.onFollowToggle,
    required this.onBlock,
  });

  final UserProfile profile;
  final Future<void> Function()? onFollowToggle;
  final Future<void> Function()? onBlock;

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
            Row(
              children: [
                Expanded(
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
                if (onBlock != null) ...[
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: '封鎖',
                    onPressed: onBlock,
                    icon: const Icon(Icons.block_outlined),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PublicProfileConversationCard extends StatelessWidget {
  const _PublicProfileConversationCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final starter = _starterText(profile);
    final travelText = profile.travelRegions.isEmpty
        ? '尚未公開跑場範圍'
        : '常跑 ${profile.travelRegions.join('、')}';
    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CosIconBubble(
                icon: Icons.record_voice_over_outlined,
                color: scheme.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '現場打招呼提示',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      starter,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CosBadge(
                label: travelText,
                icon: Icons.directions_run_outlined,
                color: scheme.primary,
              ),
              CosBadge(
                label: profile.isFollowed ? '已建立同好訊號' : '可先加入關注',
                icon: profile.isFollowed
                    ? Icons.person_pin_circle_outlined
                    : Icons.person_add_alt_1_outlined,
                color: scheme.secondary,
              ),
              if (profile.landmine.isNotEmpty)
                CosBadge(
                  label: '有公開雷點',
                  icon: Icons.warning_amber_outlined,
                  color: scheme.tertiary,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _starterText(UserProfile profile) {
    if (profile.deepPitWorks.isNotEmpty) {
      return '可以從「${profile.deepPitWorks.first.name}」開話題，先確認對方今天想聊的作品。';
    }
    if (profile.bio.isNotEmpty) {
      return profile.bio;
    }
    if (profile.regions.isNotEmpty) {
      return '可以從同地區或活動場次開話題，先輕鬆確認是不是同好圈。';
    }
    return '可以先掃名片、加入關注，再從活動現場或照片牆找話題。';
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
