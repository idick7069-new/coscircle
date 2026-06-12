import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/repositories/submission_repository.dart';
import '../../../core/services/oobe_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../admin/presentation/admin_dashboard_page.dart';
import 'theme_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CosIconBubble(icon: icon, size: 42),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
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
            Text('投稿活動', style: Theme.of(context).textTheme.titleLarge),
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
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('送出審核'),
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

class ConnectionStatusPage extends ConsumerWidget {
  const ConnectionStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiClient = ref.watch(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('連線狀態')),
      body: FutureBuilder<_ConnectionStatus>(
        future: _check(apiClient),
        builder: (context, snapshot) {
          final status = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    status?.ok == true
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: status?.ok == true
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(status?.ok == true ? '後端連線正常' : '正在檢查後端'),
                  subtitle: Text(apiClient.baseUrl),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                _ConnectionHelp(message: userFacingError(snapshot.error!))
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(status?.message ?? 'CosCircle API 可正常連線'),
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

class _ConnectionHelp extends StatelessWidget {
  const _ConnectionHelp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '連線失敗',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            const Text('請確認後端已啟動，且手機與電腦位於同一個 Wi-Fi。'),
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://docs.google.com/forms/'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BUG回報')),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}
