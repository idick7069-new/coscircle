import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/account_safety_repository.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/services/line_login_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/error_message.dart';

class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  ApiSession? _session;
  late final ApiClient _api;
  String? _accountLabel;
  List<String>? _methods;
  String? _error;
  bool _busy = false;
  bool _understood = false;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    _api.sessionChanges.addListener(_onSessionChanged);
    _loadMethods();
  }

  void _onSessionChanged() {
    if (!mounted || _session == null || _session!.isActive) return;
    _password.clear();
    _confirmation.clear();
    setState(() {
      _accountLabel = null;
      _methods = null;
      _understood = false;
      _error = '登入狀態已變更，請關閉此頁再重新操作';
    });
  }

  Future<void> _loadMethods() async {
    setState(() => _error = null);
    try {
      if (_session == null) {
        final api = ref.read(apiClientProvider);
        await api.restoreAuthToken();
        if (!mounted) return;
        _session = api.captureSession();
      }
      final session = _session!;
      final repository = ref.read(accountSafetyRepositoryProvider);
      final methods = await repository.loginMethods(session);
      final label = await repository.accountLabel(session);
      if (mounted && session.isActive) {
        setState(() {
          _methods = methods;
          _accountLabel = label;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    }
  }

  @override
  void dispose() {
    _api.sessionChanges.removeListener(_onSessionChanged);
    _session?.cancel();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _delete({required bool useLine}) async {
    final session = _session;
    if (session == null) return;
    if (_busy || !_understood || _confirmation.text.trim() != 'DELETE') return;
    if (!useLine && _password.text.isEmpty) {
      setState(() => _error = '請輸入目前帳號的登入密碼');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      session.checkActive();
      String? lineToken;
      if (useLine) {
        lineToken = await ref.read(lineLoginServiceProvider).authorize();
        if (lineToken == null) return;
        session.checkActive();
      }
      await ref
          .read(accountSafetyRepositoryProvider)
          .deleteAccount(
            session: session,
            password: useLine ? null : _password.text,
            lineAccessToken: lineToken,
          );
      if (!mounted || !session.isActive) return;
      try {
        await ref.read(pushNotificationServiceProvider).dispose();
      } catch (_) {
        // Deletion succeeded. Plugin cleanup must not leave a local session.
      }
      if (!mounted || !session.isActive) return;
      final api = ref.read(apiClientProvider);
      final version = api.sessionVersion;
      await api.persistAuthToken(null);
      if (!mounted || api.sessionVersion != version + 1) return;
      ref.invalidate(profileRepositoryProvider);
      ref.invalidate(eventRepositoryProvider);
      ref.invalidate(socialRepositoryProvider);
      ref.invalidate(selectedCurrentEventTargetProvider);
      context.go('/login');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('帳號已刪除')));
    } catch (error) {
      if (mounted) setState(() => _error = userFacingError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = _methods;
    final lineAvailable =
        methods?.contains('line') == true &&
        ref.watch(lineLoginEnabledProvider) &&
        ref.watch(lineLoginServiceProvider).supported;
    final canDelete =
        !_busy &&
        _understood &&
        _confirmation.text.trim() == 'DELETE' &&
        methods != null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('刪除帳號')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Icon(
                Icons.person_remove_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('刪除後無法復原', style: Theme.of(context).textTheme.titleLarge),
              if (_accountLabel != null) ...[
                const SizedBox(height: 12),
                Text(
                  '刪除帳號：$_accountLabel',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '你的名片、登入方式、預定、照片、關注、戳友、位置與認親資料將被刪除。你建立的小圈圈會解散，成員與集合點一併移除。',
              ),
              const SizedBox(height: 12),
              const Text(
                '他人已儲存的分享圖不會自動消失。備份與依法必須保存的紀錄依隱私政策處理。刪除 CosCircle 帳號不會刪除你的 LINE 帳號。',
              ),
              const SizedBox(height: 12),
              const Text('舊版未記錄上傳歸屬的照片，會交由營運團隊核實後清理。'),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy ? null : () => context.push('/privacy'),
                icon: const Icon(Icons.privacy_tip_outlined),
                label: const Text('查看隱私政策'),
              ),
              if (methods == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (methods == null)
                  TextButton.icon(
                    onPressed: _loadMethods,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新載入'),
                  ),
              ],
              if (methods?.contains('email') == true) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  maxLength: 1024,
                  decoration: const InputDecoration(
                    labelText: '目前帳號的登入密碼',
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _confirmation,
                enabled: !_busy && methods != null,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: '輸入 DELETE 確認刪除'),
              ),
              CheckboxListTile(
                value: _understood,
                onChanged: _busy || methods == null
                    ? null
                    : (value) => setState(() => _understood = value == true),
                title: const Text('我了解帳號與資料將永久刪除'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (methods != null &&
                  !methods.contains('email') &&
                  !lineAvailable)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://coscircle.app/delete-account.html'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('開啟帳號刪除協助'),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (methods?.contains('email') == true)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: canDelete ? () => _delete(useLine: false) : null,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('永久刪除帳號'),
                  ),
                if (lineAvailable)
                  OutlinedButton.icon(
                    onPressed: canDelete ? () => _delete(useLine: true) : null,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('使用 LINE 驗證並刪除'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
