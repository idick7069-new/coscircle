import 'package:flutter/material.dart';
import '../../../core/services/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/profile_repository.dart';
import '../../../core/services/oobe_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';

class OnboardingProfilePage extends ConsumerStatefulWidget {
  const OnboardingProfilePage({super.key});

  @override
  ConsumerState<OnboardingProfilePage> createState() =>
      _OnboardingProfilePageState();
}

class _OnboardingProfilePageState extends ConsumerState<OnboardingProfilePage> {
  final _pageController = PageController();
  final _nicknameController = TextEditingController();
  final Set<String> _roles = {'coser'};
  final Set<String> _regions = {};
  int _page = 0;
  bool _saving = false;
  String? _errorText;

  static const _regionOptions = ['北部', '中部', '南部', '離島', '海外'];
  static const _roleOptions = ['coser', 'photographer', 'manager', 'self'];

  @override
  void initState() {
    super.initState();
    _loadInitialProfile();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _GuideStep(
        icon: Icons.event_available,
        title: '加入活動，公開今天會去哪',
        message: '在活動清單找到場次，發布「出席預訂」讓同好知道你會在哪一天出現。',
        cues: const ['場次預定', '同日認親', '快速加入'],
      ),
      _GuideStep(
        icon: Icons.map_outlined,
        title: '現場找人更容易',
        message: '當前活動可以分享位置、看小圈圈集合點，也能通知朋友你要過去認親。',
        cues: const ['集合訊號', '小圈圈', '現場交流'],
      ),
      _GuideStep(
        icon: Icons.qr_code_2,
        title: '掃 QR 快速認識新朋友',
        message: '個人資料與小圈圈都能用 QRCode 分享，活動現場不用再慢慢搜尋帳號。',
        cues: const ['Cos 名片', '掃碼交換', '坑單比對'],
      ),
      _ProfileSetupStep(
        nicknameController: _nicknameController,
        roleOptions: _roleOptions,
        roles: _roles,
        regionOptions: _regionOptions,
        regions: _regions,
        onChanged: () => setState(() {}),
      ),
    ];

    return AppPage(
      appBar: AppBar(
        title: const Text('第一次使用 CosCircle'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _finish,
            child: const Text('略過'),
          ),
        ],
      ),
      child: Column(
        children: [
          _OnboardingProgressCard(
            current: _page + 1,
            total: pages.length,
            finalStep: _page == pages.length - 1,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (value) => setState(() => _page = value),
              children: pages
                  .map(
                    (page) => page is _GuideStep
                        ? SingleChildScrollView(child: page)
                        : page,
                  )
                  .toList(),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            _OnboardingErrorBanner(message: _errorText!),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_page > 0)
                OutlinedButton(
                  onPressed: _saving ? null : _previous,
                  child: const Text('上一步'),
                ),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : _page == pages.length - 1
                    ? _finish
                    : _next,
                icon: _saving
                    ? CosLoadingPulse(
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 20,
                      )
                    : Icon(
                        _page == pages.length - 1
                            ? Icons.check
                            : Icons.arrow_forward,
                      ),
                label: Text(_page == pages.length - 1 ? '開始使用' : '下一步'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _previous() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadInitialProfile() async {
    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .currentProfile();
      if (!mounted || profile == null) return;
      setState(() {
        if (_nicknameController.text.trim().isEmpty &&
            profile.nickname.trim().isNotEmpty) {
          _nicknameController.text = profile.nickname.trim();
        }
        if (_regions.isEmpty && profile.regions.isNotEmpty) {
          _regions.addAll(profile.regions);
        }
        if (profile.profileRoles.isNotEmpty) {
          _roles
            ..clear()
            ..addAll(
              profile.profileRoles.where((role) => _roleOptions.contains(role)),
            );
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = '個人資料載入失敗：${userFacingError(error)}');
      }
    }
  }

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final current = await ref
          .read(profileRepositoryProvider)
          .currentProfile();
      if (current == null) throw Exception('無法取得個人資料，請重新登入');
      final nickname = _nicknameController.text.trim().isEmpty
          ? current.nickname
          : _nicknameController.text.trim();
      await ref
          .read(profileRepositoryProvider)
          .saveProfile(
            current.copyWith(
              nickname: nickname.isEmpty ? '圈圈新朋友' : nickname,
              bio: current.bio.isEmpty ? '剛加入 CosCircle，活動現場歡迎認親！' : null,
              profileRoles: _roles.toList(),
              onboardingCompleted: true,
              regions: _regions.isEmpty ? current.regions : _regions.toList(),
            ),
          );
      await ref
          .read(oobeServiceProvider)
          .markCompleted(current.id.isEmpty ? 'me' : current.id);
      if (mounted) {
        context.go(
          safeReturnPath(GoRouterState.of(context).uri.queryParameters['next']),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorText = '新手設定儲存失敗：${userFacingError(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.icon,
    required this.title,
    required this.message,
    required this.cues,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> cues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: CosGradientPanel(
        icon: icon,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CosIconBubble(icon: icon, color: scheme.primary, size: 68),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CosBadge(
                        label: '新手任務',
                        icon: Icons.auto_awesome,
                        color: scheme.primary,
                        highlighted: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '先把現場交流變簡單',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cue in cues)
                  CosBadge(
                    label: cue,
                    icon: Icons.check_circle_outline,
                    color: scheme.secondary,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingProgressCard extends StatelessWidget {
  const _OnboardingProgressCard({
    required this.current,
    required this.total,
    required this.finalStep,
  });

  final int current;
  final int total;
  final bool finalStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = current / total;
    return CosCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const CosLogoMark(size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        finalStep ? '建立你的 Cos 名片' : '熟悉活動交流流程',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$current/$total',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(minHeight: 8, value: progress),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSetupStep extends StatelessWidget {
  const _ProfileSetupStep({
    required this.nicknameController,
    required this.roleOptions,
    required this.roles,
    required this.regionOptions,
    required this.regions,
    required this.onChanged,
  });

  final TextEditingController nicknameController;
  final List<String> roleOptions;
  final Set<String> roles;
  final List<String> regionOptions;
  final Set<String> regions;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        CosCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '先建立你的活動名片',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text('這些資料之後都能在個人資訊頁修改。'),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(CosUi.radiusMd),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.diversity_3_outlined, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '暱稱、身份與常跑地區會幫同好更快判斷是否能現場認親。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nicknameController,
                decoration: const InputDecoration(labelText: '暱稱 / CN'),
              ),
              const SizedBox(height: 18),
              Text('你通常的身份', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in roleOptions)
                    CosChoicePill(
                      label: participantRoleLabel(role),
                      selected: roles.contains(role),
                      icon: participantRoleIcon(role),
                      color: participantRoleColorForScheme(role, scheme),
                      onTap: () {
                        roles.contains(role)
                            ? roles.remove(role)
                            : roles.add(role);
                        onChanged();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('常跑地區', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final region in regionOptions)
                    CosChoicePill(
                      label: region,
                      selected: regions.contains(region),
                      icon: Icons.place_outlined,
                      onTap: () {
                        regions.contains(region)
                            ? regions.remove(region)
                            : regions.add(region);
                        onChanged();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OnboardingErrorBanner extends StatelessWidget {
  const _OnboardingErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: scheme.error.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
