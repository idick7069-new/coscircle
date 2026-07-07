import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/theme_mode_provider.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/repositories/submission_repository.dart';
import '../../../core/services/oobe_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../admin/presentation/admin_dashboard_page.dart';
import 'theme_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CosPageHeader(
          title: '設定',
          subtitle: '管理主題、連線、投稿與帳號狀態',
          leading: CosIconBubble(icon: Icons.tune_outlined),
        ),
        const SizedBox(height: 8),
        FutureBuilder(
          future: ref.watch(profileRepositoryProvider).currentProfile(),
          builder: (context, snapshot) {
            final isAdmin = snapshot.data?.isAdmin == true;
            if (!isAdmin) return const SizedBox.shrink();
            return _SettingsSection(
              title: '管理者',
              children: [
                _SettingsAction(
                  icon: Icons.admin_panel_settings_outlined,
                  title: '後台管理',
                  subtitle: '查看資料庫狀態、管理活動資料',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminDashboardPage(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        _SettingsSection(
          title: 'App 體驗',
          children: [
            _SettingsAction(
              icon: Icons.palette_outlined,
              title: '介面主題',
              subtitle: '切換星夜暗色或社群亮色',
              trailing: CosBadge(
                label: themeMode.label,
                icon: themeMode == CosCircleThemeMode.neonDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                highlighted: true,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ThemeSettingsPage()),
              ),
            ),
            _SettingsAction(
              icon: Icons.wifi_tethering_outlined,
              title: '連線狀態',
              subtitle: '檢查手機是否能連到後端服務',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConnectionStatusPage()),
              ),
            ),
            _SettingsAction(
              icon: Icons.school_outlined,
              title: '重新觀看新手教學',
              subtitle: '重新跑一次第一次使用流程',
              onTap: () async {
                final profile = await ref
                    .read(profileRepositoryProvider)
                    .currentProfile();
                if (profile != null) {
                  await ref.read(oobeServiceProvider).reset(profile.id);
                }
                if (context.mounted) context.go('/onboarding');
              },
            ),
          ],
        ),
        _SettingsSection(
          title: '活動與支援',
          children: [
            _SettingsAction(
              icon: Icons.add_location_alt_outlined,
              title: '投稿活動',
              subtitle: '補充你知道的 cosplay / 同人活動',
              onTap: () => _submitEventDialog(context, ref),
            ),
            _SettingsAction(
              icon: Icons.bug_report_outlined,
              title: 'BUG回報',
              subtitle: '回報異常或提出改善建議',
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const BugReportPage())),
            ),
            _SettingsAction(
              icon: Icons.info_outline,
              title: '顯示版本號',
              subtitle: '查看目前安裝的 CosCircle 版本',
              onTap: () async {
                final info = await PackageInfo.fromPlatform();
                if (context.mounted) {
                  showAboutDialog(
                    context: context,
                    applicationName: 'CosCircle',
                    applicationVersion: '${info.version}+${info.buildNumber}',
                  );
                }
              },
            ),
          ],
        ),
        _SettingsSection(
          title: '帳號',
          children: [
            _SettingsAction(
              icon: Icons.logout,
              title: '登出',
              subtitle: '離開目前帳號',
              onTap: () async {
                await ref.read(authRepositoryProvider).logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submitEventDialog(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _SubmitEventSheet(),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          CosCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final entry in children.indexed) ...[
                  entry.$2,
                  if (entry.$1 != children.length - 1)
                    Divider(
                      height: 1,
                      indent: 70,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CosIconBubble(icon: icon, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 128),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.48,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child:
                        trailing ??
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitEventSheet extends ConsumerStatefulWidget {
  const _SubmitEventSheet();

  @override
  ConsumerState<_SubmitEventSheet> createState() => _SubmitEventSheetState();
}

class _SubmitEventSheetState extends ConsumerState<_SubmitEventSheet> {
  final _name = TextEditingController();
  final _startDate = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  final _endDate = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  final _venue = TextEditingController();
  final _detailedAddress = TextEditingController();
  final _description = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _venue.dispose();
    _detailedAddress.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const CosSectionHeader(
              title: '投稿活動',
              subtitle: '把你知道的 cosplay / 同人場次補進資料庫',
              icon: Icons.add_location_alt_outlined,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '活動名稱'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startDate,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '開始日期',
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    onTap: () => _pickDate(_startDate),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endDate,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '結束日期',
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    onTap: () => _pickDate(_endDate),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _venue,
              decoration: const InputDecoration(labelText: '活動地點'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detailedAddress,
              decoration: const InputDecoration(labelText: '詳細地址'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: '活動說明'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _SubmitEventActionBar(
              submitting: _submitting,
              onSubmit: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final current = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    controller.text = DateFormat('yyyy-MM-dd').format(picked);
  }

  Future<void> _submit() async {
    final startDate = DateTime.parse(_startDate.text.trim());
    final endDate = DateTime.parse(_endDate.text.trim());
    if (_name.text.trim().isEmpty || _venue.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填寫活動名稱與活動地點')));
      return;
    }
    if (endDate.isBefore(startDate)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('結束日期不能早於開始日期')));
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(submissionRepositoryProvider)
          .submitEvent(
            name: _name.text.trim(),
            startDate: startDate,
            endDate: endDate,
            venue: _venue.text.trim(),
            detailedAddress: _detailedAddress.text.trim().isEmpty
                ? _venue.text.trim()
                : _detailedAddress.text.trim(),
            description: _description.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已送出投稿，等待管理者審核')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('投稿失敗：${userFacingError(error)}')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _SubmitEventActionBar extends StatelessWidget {
  const _SubmitEventActionBar({
    required this.submitting,
    required this.onSubmit,
  });

  final bool submitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.52),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                submitting ? '送出活動投稿中' : '送出後會等待管理者審核',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onSubmit,
              icon: submitting
                  ? CosLoadingPulse(color: scheme.onPrimary, size: 20)
                  : const Icon(Icons.send),
              label: Text(submitting ? '送出中' : '送出審核'),
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionStatusPage extends ConsumerWidget {
  const ConnectionStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiClient = ref.watch(apiClientProvider);
    return AppPage(
      appBar: AppBar(title: const Text('連線狀態')),
      padding: EdgeInsets.zero,
      child: FutureBuilder<_ConnectionStatus>(
        future: _check(apiClient),
        builder: (context, snapshot) {
          final status = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const CosPageHeader(
                title: '連線狀態',
                subtitle: '確認 App 與後端 API 是否能互相找到',
                leading: CosIconBubble(icon: Icons.wifi_tethering_outlined),
              ),
              const SizedBox(height: 8),
              _ConnectionHeroCard(
                checking: snapshot.connectionState == ConnectionState.waiting,
                ok: status?.ok == true,
                baseUrl: apiClient.baseUrl,
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const _ConnectionCheckingCard()
              else if (snapshot.hasError)
                _ConnectionHelp(message: userFacingError(snapshot.error!))
              else
                CosCard(
                  child: Row(
                    children: [
                      CosIconBubble(
                        icon: Icons.verified_outlined,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          status?.message ?? 'CosCircle API 可正常連線',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const ConnectionStatusPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重新檢查'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_ConnectionStatus> _check(ApiClient apiClient) async {
    final response = await apiClient.health();
    final data = response.data;
    final name = data is Map ? data['name']?.toString() : null;
    return _ConnectionStatus(
      ok: response.statusCode == 200,
      message: name == null || name.isEmpty ? '後端服務可連線' : '$name 可連線',
    );
  }
}

class _ConnectionStatus {
  const _ConnectionStatus({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class _ConnectionHeroCard extends StatelessWidget {
  const _ConnectionHeroCard({
    required this.checking,
    required this.ok,
    required this.baseUrl,
  });

  final bool checking;
  final bool ok;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = checking
        ? Icons.sync_outlined
        : ok
        ? Icons.check_circle_outline
        : Icons.info_outline;
    final title = checking ? '正在檢查後端' : (ok ? '後端連線正常' : '等待檢查結果');
    final accent = ok ? scheme.secondary : scheme.primary;
    return CosGradientPanel(
      icon: Icons.wifi_tethering_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CosIconBubble(icon: icon, color: accent, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900, height: 1.05),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '目前 API 端點',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (checking) CosLoadingPulse(color: accent),
            ],
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.link, color: scheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      baseUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCheckingCard extends StatelessWidget {
  const _ConnectionCheckingCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Row(
        children: [
          CosLoadingPulse(color: scheme.secondary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '正在送出健康檢查訊號，請稍候。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionHelp extends StatelessWidget {
  const _ConnectionHelp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosSectionHeader(
              title: '連線失敗',
              subtitle: '確認本機後端與手機網路後再重新檢查',
              icon: Icons.wifi_off_outlined,
              trailing: CosBadge(
                label: 'API',
                icon: Icons.cloud_off_outlined,
                color: scheme.error,
                highlighted: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.36),
                borderRadius: BorderRadius.circular(CosUi.radiusMd),
                border: Border.all(color: scheme.error.withValues(alpha: 0.18)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('請確認後端已啟動，且手機與電腦位於同一個 Wi-Fi。'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BugReportPage extends StatefulWidget {
  const BugReportPage({super.key});

  @override
  State<BugReportPage> createState() => _BugReportPageState();
}

class _BugReportPageState extends State<BugReportPage> {
  late final WebViewController _controller;
  bool _loading = true;
  int _progress = 0;
  String? _webError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _webError = null;
            });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _webError = error.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse('https://docs.google.com/forms/'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BUG回報')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              _BugReportHero(
                loading: _loading,
                progress: _progress,
                hasError: _webError != null,
                onReload: () => _controller.reload(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _BugReportWebFrame(
                  controller: _controller,
                  loading: _loading,
                  progress: _progress,
                  errorText: _webError,
                  onReload: () => _controller.reload(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BugReportHero extends StatelessWidget {
  const _BugReportHero({
    required this.loading,
    required this.progress,
    required this.hasError,
    required this.onReload,
  });

  final bool loading;
  final int progress;
  final bool hasError;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = hasError
        ? '回報表單暫時打不開'
        : loading
        ? '正在載入回報表單'
        : '把問題交給我們';
    final subtitle = hasError
        ? '可以重新整理，或稍後再回來提交問題'
        : '描述你遇到的異常、畫面或流程，我們會用它修正下一版';
    return CosGradientPanel(
      icon: Icons.bug_report_outlined,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CosIconBubble(
                icon: hasError
                    ? Icons.wifi_off_outlined
                    : Icons.bug_report_outlined,
                color: hasError ? scheme.error : scheme.primary,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                CosBadge(
                  label: '$progress%',
                  icon: Icons.sync_outlined,
                  color: scheme.secondary,
                  highlighted: true,
                )
              else
                IconButton.filledTonal(
                  tooltip: '重新整理',
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: progress / 100),
            ),
          ],
        ],
      ),
    );
  }
}

class _BugReportWebFrame extends StatelessWidget {
  const _BugReportWebFrame({
    required this.controller,
    required this.loading,
    required this.progress,
    required this.errorText,
    required this.onReload,
  });

  final WebViewController controller;
  final bool loading;
  final int progress;
  final String? errorText;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [CosUi.softShadow(scheme.shadow)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        child: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (loading)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest.withValues(
                      alpha: 0.86,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CosLoadingPulse(color: scheme.primary, size: 34),
                        const SizedBox(height: 12),
                        Text(
                          '載入表單 $progress%',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (errorText != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest.withValues(
                      alpha: 0.94,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CosIconBubble(
                          icon: Icons.cloud_off_outlined,
                          color: scheme.error,
                          size: 52,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '無法載入回報表單',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          errorText!,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: onReload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新載入'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
