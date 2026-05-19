import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/repositories/submission_repository.dart';
import '../../admin/presentation/admin_dashboard_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '其他',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('後台管理'),
                subtitle: const Text('查看資料庫狀態、管理活動資料'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_location_alt_outlined),
                title: const Text('投稿活動'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _submitEventDialog(context, ref),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('顯示版本號'),
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
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('BUG回報'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BugReportPage()),
                ),
              ),
            ],
          ),
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
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _venue.dispose();
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
                    decoration: const InputDecoration(
                      labelText: '開始日期 yyyy-MM-dd',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endDate,
                    decoration: const InputDecoration(
                      labelText: '結束日期 yyyy-MM-dd',
                    ),
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
              controller: _description,
              decoration: const InputDecoration(labelText: '活動說明'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await ref
                    .read(submissionRepositoryProvider)
                    .submitEvent(
                      name: _name.text.trim(),
                      startDate: DateTime.parse(_startDate.text.trim()),
                      endDate: DateTime.parse(_endDate.text.trim()),
                      venue: _venue.text.trim(),
                      description: _description.text.trim(),
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已送出投稿，等待管理者審核')));
              },
              icon: const Icon(Icons.send),
              label: const Text('送出審核'),
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
