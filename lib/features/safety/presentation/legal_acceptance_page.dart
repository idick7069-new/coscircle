import 'package:flutter/material.dart';
import '../../../core/config/app_environment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/repositories/legal_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/services/push_notification_service.dart';
import 'legal_page.dart';

enum _LegalPhase {
  loading,
  consent,
  submitting,
  accepted,
  refreshingAccepted,
  acceptedRefreshFailed,
  failed,
  loggingOut,
}

class LegalAcceptanceGate extends ConsumerStatefulWidget {
  const LegalAcceptanceGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LegalAcceptanceGate> createState() =>
      _LegalAcceptanceGateState();
}

class _LegalAcceptanceGateState extends ConsumerState<LegalAcceptanceGate>
    with WidgetsBindingObserver {
  late final ApiClient _api;
  late final LegalRepository _repository;
  late final AuthRepository _auth;
  late final int _initialVersion;
  late int _sessionVersion;
  ApiSession? _session;
  _LegalPhase _phase = _LegalPhase.loading;
  bool _checked = false;
  String? _error;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    _repository = ref.read(legalRepositoryProvider);
    _auth = ref.read(authRepositoryProvider);
    _initialVersion = _api.sessionVersion;
    _sessionVersion = _initialVersion;
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final operation = ++_operation;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted || operation != _operation) return;
      if (_api.sessionVersion != _initialVersion) {
        throw StateError('Session changed before restoration');
      }
      final expectedToken = preferences.getString(AuthRepository.tokenKey);
      final token = await _api.restoreAuthToken();
      if (!mounted || operation != _operation) return;
      // Initial restoration may advance the version once; a login must not rebind this gate.
      if (token == null ||
          token.isEmpty ||
          token != expectedToken ||
          (_api.sessionVersion != _initialVersion &&
              _api.sessionVersion != _initialVersion + 1)) {
        throw StateError('Session changed during restoration');
      }
      _sessionVersion = _api.sessionVersion;
      _session = _api.captureSession();
      _session!.checkActive();
      await _load();
    } catch (error) {
      _failed(operation, error);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operation += 1;
    _session?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _session != null &&
        _phase != _LegalPhase.submitting &&
        _phase != _LegalPhase.loggingOut) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_phase == _LegalPhase.submitting ||
        _phase == _LegalPhase.loggingOut ||
        _phase == _LegalPhase.refreshingAccepted) {
      return;
    }
    final preserveAccepted =
        (_phase == _LegalPhase.accepted ||
            _phase == _LegalPhase.acceptedRefreshFailed) &&
        _session?.isActive == true;
    final operation = ++_operation;
    setState(() {
      _phase = preserveAccepted
          ? _LegalPhase.refreshingAccepted
          : _LegalPhase.loading;
      _checked = false;
      _error = null;
    });
    try {
      final session = _session;
      if (session == null) throw StateError('Missing original session');
      session.checkActive();
      final status = await _repository.status(session);
      if (!mounted || operation != _operation) return;
      session.checkActive();
      setState(() {
        _phase = status.accepted ? _LegalPhase.accepted : _LegalPhase.consent;
      });
    } catch (error) {
      _failed(operation, error);
    }
  }

  Future<void> _accept() async {
    if (_phase != _LegalPhase.consent || !_checked) return;
    final operation = ++_operation;
    setState(() {
      _phase = _LegalPhase.submitting;
      _error = null;
    });
    try {
      final session = _session;
      if (session == null) throw StateError('Missing original session');
      session.checkActive();
      await _repository.accept(session);
      if (!mounted || operation != _operation) return;
      session.checkActive();
      setState(() => _phase = _LegalPhase.accepted);
    } catch (error) {
      _failed(operation, error);
    }
  }

  void _failed(int operation, Object error) {
    if (!mounted || operation != _operation) return;
    final preserveAccepted =
        _phase == _LegalPhase.refreshingAccepted &&
        _session?.isActive == true &&
        error is! FormatException;
    setState(() {
      _phase = preserveAccepted
          ? _LegalPhase.acceptedRefreshFailed
          : _LegalPhase.failed;
      _checked = false;
      _error = _session?.isActive != true
          ? '登入狀態已變更，請離開此帳號後重新登入。'
          : error is FormatException
          ? '法律文件版本或回應不符，請更新 App 或重新確認。'
          : '無法確認同意狀態，請檢查連線後重試。';
    });
    if (preserveAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('暫時無法重新確認使用規則，請連線後重試'),
          action: SnackBarAction(label: '重試', onPressed: _load),
        ),
      );
    }
  }

  Future<void> _logout() async {
    if (_phase == _LegalPhase.loggingOut) return;
    final operation = ++_operation;
    if (_api.sessionVersion != _sessionVersion || _session?.isActive != true) {
      if (mounted) context.go('/login');
      return;
    }
    setState(() => _phase = _LegalPhase.loggingOut);
    try {
      final version = _api.sessionVersion;
      final push = ref.read(pushNotificationServiceProvider);
      final pushToken = push.registeredToken;
      try {
        await push.dispose();
      } catch (_) {
        // Push cleanup must not prevent local logout.
      }
      if (!mounted || _api.sessionVersion != version) return;
      final loggedOut = await _auth.logout(pushToken: pushToken);
      if (!mounted || !loggedOut) return;
      ref.invalidate(profileRepositoryProvider);
      ref.invalidate(eventRepositoryProvider);
      ref.invalidate(socialRepositoryProvider);
      ref.invalidate(selectedCurrentEventTargetProvider);
      context.go('/login');
    } catch (error) {
      _failed(operation, error);
    } finally {
      if (mounted && _phase == _LegalPhase.loggingOut) {
        _failed(operation, StateError('Logout did not finish'));
      }
    }
  }

  void _viewLegal(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LegalPage(document: document)),
    );
  }

  Future<void> _contact() async {
    try {
      if (await launchUrl(
        Uri.parse('https://forms.gle/WGFe57Y1AFW1LQda8'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Document reading and account exits remain available offline.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('無法開啟聯絡表單，請連線後再試')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sessionExpired, _api.sessionChanges]),
      builder: (context, _) {
        final expired = sessionExpired.value;
        final active = _session?.isActive == true && !expired;
        final previouslyAccepted =
            _phase == _LegalPhase.accepted ||
            _phase == _LegalPhase.refreshingAccepted ||
            _phase == _LegalPhase.acceptedRefreshFailed;
        if (previouslyAccepted && active) return widget.child;
        if (_phase == _LegalPhase.loading) {
          return const Scaffold(
            body: SafeArea(
              child: Center(
                child: CircularProgressIndicator(semanticsLabel: '載入中'),
              ),
            ),
          );
        }
        final busy =
            _phase == _LegalPhase.loading ||
            _phase == _LegalPhase.submitting ||
            _phase == _LegalPhase.loggingOut;
        final canCheck = _phase == _LegalPhase.consent && active;
        final error = !active && _phase != _LegalPhase.loading
            ? '登入狀態已變更，請離開此帳號後重新登入。'
            : _error;
        return Scaffold(
          appBar: AppBar(title: const Text('CosCircle')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '閱讀並確認使用規則',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text('版本 $legalVersion。請閱讀完整文件，再決定是否同意。'),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => _viewLegal(LegalDocument.privacy),
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const Text('閱讀隱私政策'),
                    ),
                    TextButton.icon(
                      onPressed: () => _viewLegal(LegalDocument.terms),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('閱讀使用條款與社群規則'),
                    ),
                    const SizedBox(height: 12),
                    if (busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(switch (_phase) {
                        _LegalPhase.submitting => '正在確認你的同意…',
                        _LegalPhase.loggingOut => '正在登出…',
                        _ => '正在確認同意狀態…',
                      }),
                    ],
                    if (error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      if (!busy && active)
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新確認'),
                        ),
                    ],
                    CheckboxListTile(
                      value: _checked,
                      onChanged: canCheck
                          ? (value) => setState(() => _checked = value == true)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('我已閱讀並同意本版本使用條款及隱私政策'),
                    ),
                    FilledButton.icon(
                      onPressed: canCheck && _checked ? _accept : null,
                      icon: const Icon(Icons.check),
                      label: const Text('同意並繼續'),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _phase == _LegalPhase.loggingOut
                          ? null
                          : _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('不同意，登出'),
                    ),
                    if (accountSafetyEnabled)
                      TextButton.icon(
                        onPressed: _phase == _LegalPhase.loggingOut
                            ? null
                            : () => context.push('/delete-account'),
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('刪除帳號'),
                      ),
                    TextButton.icon(
                      onPressed: _contact,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('檢舉、申訴或聯絡營運團隊'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
