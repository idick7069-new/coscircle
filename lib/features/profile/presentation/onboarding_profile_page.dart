import 'package:flutter/material.dart';
import '../../../core/services/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/profile.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/services/oobe_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../../shared/widgets/mimi_mascot.dart';

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
  bool _loadingProfile = true;
  UserProfile? _initialProfile;
  ProfileOperation? _profileOperation;
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
    _profileOperation?.cancel();
    _pageController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _GuideStep(
        icon: Icons.event_available,
        scene: MimiScene.reading,
        title: '場次預定，我陪你準備',
        message: '我是希希，你的馬內！先找想去的活動，再選參加日期、填出角預定，讓同好知道哪天能遇見你。',
        cues: const ['場次預定', '同日認親', '快速加入'],
      ),
      _GuideStep(
        icon: Icons.map_outlined,
        scene: MimiScene.map,
        title: '到了現場，一起找夥伴',
        message: '在「現場」看集合點、發認親訊號。位置分享由你主動開啟，也能隨時關閉；需要找路時，我陪你看地圖。',
        cues: const ['集合訊號', '小圈圈', '現場交流'],
      ),
      _GuideStep(
        icon: Icons.qr_code_2,
        scene: MimiScene.hello,
        title: '交換名片，找到同坑朋友',
        message: '掃對方的 QRCode，可以關注或送出戳友邀請，附一句自我介紹方便認人。到「同好」還能找同坑夥伴、加入小圈圈。',
        cues: const ['Cos 名片', '戳友留話', '同坑夥伴'],
      ),
      IgnorePointer(
        ignoring: _loadingProfile || _initialProfile == null || _saving,
        child: _ProfileSetupStep(
          loading: _loadingProfile,
          saving: _saving,
          hasProfile: _initialProfile != null,
          nicknameController: _nicknameController,
          roleOptions: _roleOptions,
          roles: _roles,
          regionOptions: _regionOptions,
          regions: _regions,
          onChanged: () => setState(() {}),
        ),
      ),
    ];

    return AppPage(
      appBar: AppBar(
        title: const Text('第一次使用 CosCircle'),
        actions: [
          TextButton(
            onPressed: _saving || _loadingProfile || _initialProfile == null
                ? null
                : () => _finish(skip: true),
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
            if (!_loadingProfile && _initialProfile == null)
              TextButton.icon(
                onPressed: _loadInitialProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('重新載入個人資料'),
              ),
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
                onPressed:
                    _saving ||
                        (_page == pages.length - 1 &&
                            (_loadingProfile || _initialProfile == null))
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
    setState(() {
      _loadingProfile = true;
      _errorText = null;
    });
    try {
      _profileOperation?.cancel();
      final operation = ref.read(profileRepositoryProvider).beginOperation();
      _profileOperation = operation;
      final profile = await operation.currentProfile();
      if (!mounted) return;
      if (profile == null) throw StateError('無法取得個人資料，請重新登入');
      setState(() {
        _initialProfile = profile;
        if (_nicknameController.text.trim().isEmpty &&
            profile.nickname.trim().isNotEmpty) {
          _nicknameController.text = profile.nickname.trim();
        }
        if (_regions.isEmpty && profile.regions.isNotEmpty) {
          _regions.addAll(profile.regions);
        }
        _roles
          ..clear()
          ..addAll(profile.profileRoles);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = '個人資料載入失敗：${userFacingError(error)}');
      }
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _finish({bool skip = false}) async {
    final current = _initialProfile;
    final operation = _profileOperation;
    if (_loadingProfile || _saving || current == null || operation == null) {
      return;
    }
    final oobe = ref.read(oobeServiceProvider);
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      operation.checkActive();
      final nickname = _nicknameController.text.trim().isEmpty
          ? current.nickname
          : _nicknameController.text.trim();
      await operation.saveProfile(
        skip
            ? current.copyWith(onboardingCompleted: true)
            : current.copyWith(
                nickname: nickname.isEmpty ? '圈圈新朋友' : nickname,
                bio: current.bio.isEmpty ? '剛加入 CosCircle，活動現場歡迎認親！' : null,
                profileRoles: _roles.toList(),
                onboardingCompleted: true,
                regions: _regions.isEmpty ? current.regions : _regions.toList(),
              ),
      );
      operation.checkActive();
      await oobe.markCompleted(current.id.isEmpty ? 'me' : current.id);
      operation.checkActive();
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
    required this.scene,
    required this.title,
    required this.message,
    required this.cues,
  });

  final IconData icon;
  final MimiScene scene;
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
                        label: '希希・你的馬內',
                        icon: Icons.auto_awesome,
                        color: scheme.primary,
                        highlighted: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '陪你準備，一起出角',
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
            const SizedBox(height: 16),
            Center(child: MimiMascot(scene: scene, size: 112, animate: false)),
            const SizedBox(height: 16),
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
                  borderRadius: BorderRadius.circular(CosUi.radiusSm),
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
    required this.loading,
    required this.saving,
    required this.hasProfile,
    required this.nicknameController,
    required this.roleOptions,
    required this.roles,
    required this.regionOptions,
    required this.regions,
    required this.onChanged,
  });

  final bool loading;
  final bool saving;
  final bool hasProfile;
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
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MimiMascot(size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '希希幫你建檔',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        loading
                            ? '我先幫你讀取名片資料，稍等一下！'
                            : saving
                            ? '正在收好你的名片，馬上就能出發！'
                            : !hasProfile
                            ? '資料還沒讀取成功，按下方重新載入，我們再試一次。'
                            : '先告訴我怎麼稱呼你、平常的身份和常跑地區。身份可以複選，其他資料之後再到名片補齊就好！',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
              Text(
                '你通常的身份（可複選）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
