import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/profile.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/services/oobe_service.dart';
import '../../../core/utils/error_message.dart';
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
  final Set<String> _roles = {'Coser'};
  final Set<String> _regions = {};
  int _page = 0;
  bool _saving = false;
  String? _errorText;

  static const _regionOptions = ['北部', '中部', '南部', '離島', '海外'];
  static const _roleOptions = ['Coser', '攝影', '馬內', '路人'];

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
      ),
      _GuideStep(
        icon: Icons.map_outlined,
        title: '現場找人更容易',
        message: '當前活動可以分享位置、看小圈圈集合點，也能通知朋友你要過去認親。',
      ),
      _GuideStep(
        icon: Icons.qr_code_2,
        title: '掃 QR 快速認識新朋友',
        message: '個人資料與小圈圈都能用 QRCode 分享，活動現場不用再慢慢搜尋帳號。',
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
          CosCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const CosLogoMark(size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: (_page + 1) / pages.length,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_page + 1}/${pages.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (value) => setState(() => _page = value),
              children: pages,
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (_page > 0)
                OutlinedButton(
                  onPressed: _saving ? null : _previous,
                  child: const Text('上一步'),
                )
              else
                const SizedBox(width: 88),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : _page == pages.length - 1
                    ? _finish
                    : _next,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
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

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final current =
          await ref.read(profileRepositoryProvider).currentProfile() ??
          const UserProfile(id: 'me', nickname: '圈圈新朋友');
      final nickname = _nicknameController.text.trim().isEmpty
          ? current.nickname
          : _nicknameController.text.trim();
      await ref
          .read(profileRepositoryProvider)
          .saveProfile(
            current.copyWith(
              nickname: nickname.isEmpty ? '圈圈新朋友' : nickname,
              bio: current.bio.isEmpty ? '剛加入 CosCircle，活動現場歡迎認親！' : null,
              regions: _regions.isEmpty ? current.regions : _regions.toList(),
            ),
          );
      await ref
          .read(oobeServiceProvider)
          .markCompleted(current.id.isEmpty ? 'me' : current.id);
      if (mounted) context.go('/');
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
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: CosCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CosIconBubble(icon: icon, color: scheme.primary, size: 68),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
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
                    FilterChip(
                      label: Text(role),
                      selected: roles.contains(role),
                      onSelected: (selected) {
                        selected ? roles.add(role) : roles.remove(role);
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
                    FilterChip(
                      label: Text(region),
                      selected: regions.contains(region),
                      onSelected: (selected) {
                        selected ? regions.add(region) : regions.remove(region);
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
