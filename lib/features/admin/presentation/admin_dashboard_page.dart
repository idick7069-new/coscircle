import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/admin_doujin_sync_check.dart';
import '../../../core/models/admin_stats.dart';
import '../../../core/models/admin_sync_run.dart';
import '../../../core/models/admin_user.dart';
import '../../../core/models/event.dart';
import '../../../core/models/event_submission.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/providers/admin_sync_provider.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/cos_ui.dart';

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  return ref.watch(adminRepositoryProvider).fetchStats();
});

final adminEventsProvider = FutureProvider.autoDispose<List<CosEvent>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchEvents();
});

final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchUsers();
});

final adminSubmissionsProvider =
    FutureProvider.autoDispose<List<EventSubmission>>((ref) {
      return ref.watch(adminRepositoryProvider).fetchSubmissions();
    });

final adminSyncRunsProvider = FutureProvider.autoDispose<List<AdminSyncRun>>((
  ref,
) {
  return ref.watch(adminRepositoryProvider).fetchSyncStatus();
});

final adminDoujinSyncCheckProvider =
    FutureProvider.autoDispose<AdminDoujinSyncCheck>((ref) {
      return ref.watch(adminRepositoryProvider).checkDoujinSync();
    });

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final events = ref.watch(adminEventsProvider);
    final users = ref.watch(adminUsersProvider);
    final submissions = ref.watch(adminSubmissionsProvider);
    final syncRuns = ref.watch(adminSyncRunsProvider);
    final syncCheck = ref.watch(adminDoujinSyncCheckProvider);
    final syncJob = ref.watch(adminSyncJobProvider);
    final syncing = syncJob.isLoading || syncJob.value?.isRunning == true;
    ref.listen(adminSyncJobProvider, (previous, next) {
      if ((previous?.value?.isRunning == true || previous?.isLoading == true) &&
          next.value?.isRunning == false) {
        ref.invalidate(adminStatsProvider);
        ref.invalidate(adminEventsProvider);
        ref.invalidate(adminSyncRunsProvider);
        ref.invalidate(adminDoujinSyncCheckProvider);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const BackButtonIcon(),
        ),
        title: const Text('後台管理'),
        actions: [
          IconButton(
            tooltip: 'API 位址',
            onPressed: () => _showApiInfo(context, ref),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: '同步所有活動來源',
            onPressed: syncing ? null : () => _syncDoujinEvents(context, ref),
            icon: syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            tooltip: '重新整理',
            onPressed: () async => _refresh(ref),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateEventSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新增活動'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1100;
              final horizontalPadding = wide ? 24.0 : 16.0;
              final content = _AdminDashboardLayout(
                wide: wide,
                stats: stats.when(
                  data: (value) => _StatsGrid(stats: value),
                  error: (error, stack) => _ErrorPanel(
                    message: '資料庫狀態載入失敗：${userFacingError(error)}',
                  ),
                  loading: () => const _LoadingPanel(message: '載入資料庫狀態...'),
                ),
                sync: _AdminSection(
                  title: '資料來源同步',
                  icon: Icons.cloud_sync_outlined,
                  dense: wide,
                  child: Column(
                    children: [
                      if (syncing) const LinearProgressIndicator(),
                      if (syncJob.value != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            syncJob.value!.isRunning
                                ? '同步中 · ${syncJob.value!.sources.length} 個來源已完成'
                                : syncJob.value!.status == 'success'
                                ? '最近同步完成'
                                : syncJob.value!.status == 'partial'
                                ? '部分來源同步失敗，請查看來源狀態'
                                : '最近同步失敗，請查看來源狀態',
                          ),
                        ),
                      if (syncJob.hasError)
                        _ErrorPanel(
                          message:
                              '同步進度讀取失敗：${userFacingError(syncJob.error!)}',
                        ),
                      if (syncJob.hasError)
                        TextButton.icon(
                          onPressed: () => ref.invalidate(adminSyncJobProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新讀取進度'),
                        ),
                      syncCheck.when(
                        data: (check) =>
                            _DoujinSyncCheckCard(check: check, compact: wide),
                        error: (error, stack) => _ErrorPanel(
                          message: '同步檢查載入失敗：${userFacingError(error)}',
                        ),
                        loading: () =>
                            const _LoadingPanel(message: '正在比對同人誌中心...'),
                      ),
                      const SizedBox(height: 8),
                      syncRuns.when(
                        data: (items) =>
                            _SyncRunList(runs: items, compact: wide),
                        error: (error, stack) => _ErrorPanel(
                          message: '同步狀態載入失敗：${userFacingError(error)}',
                        ),
                        loading: () =>
                            const _LoadingPanel(message: '載入同步狀態...'),
                      ),
                    ],
                  ),
                ),
                users: _AdminSection(
                  title: '使用者管理',
                  icon: Icons.people_alt_outlined,
                  dense: wide,
                  child: users.when(
                    data: (items) => _AdminUserList(
                      users: items,
                      compact: wide,
                      onStatusChanged: (user, status) =>
                          _updateUserStatus(context, ref, user, status),
                      onAdminChanged: (user, isAdmin) =>
                          _updateUserAdmin(context, ref, user, isAdmin),
                      onDelete: (user) =>
                          _confirmDeleteUser(context, ref, user),
                    ),
                    error: (error, stack) => _ErrorPanel(
                      message: '使用者載入失敗：${userFacingError(error)}',
                    ),
                    loading: () => const _LoadingPanel(message: '載入使用者資料...'),
                  ),
                ),
                submissions: _AdminSection(
                  title: '投稿審核',
                  icon: Icons.post_add_outlined,
                  dense: wide,
                  child: submissions.when(
                    data: (items) => _SubmissionList(
                      submissions: items,
                      compact: wide,
                      onApprove: (submission) => _reviewSubmission(
                        context,
                        ref,
                        submission,
                        approve: true,
                      ),
                      onReject: (submission) => _reviewSubmission(
                        context,
                        ref,
                        submission,
                        approve: false,
                      ),
                    ),
                    error: (error, stack) => _ErrorPanel(
                      message: '投稿載入失敗：${userFacingError(error)}',
                    ),
                    loading: () => const _LoadingPanel(message: '載入投稿資料...'),
                  ),
                ),
                events: _AdminSection(
                  title: '活動資料',
                  icon: Icons.event_outlined,
                  dense: wide,
                  child: events.when(
                    data: (items) => _AdminEventSections(
                      events: items,
                      compact: wide,
                      onEdit: (event) =>
                          _showEditEventSheet(context, ref, event),
                      onDelete: (event) => _confirmDelete(context, ref, event),
                    ),
                    error: (error, stack) => _ErrorPanel(
                      message: '活動載入失敗：${userFacingError(error)}',
                    ),
                    loading: () => const _LoadingPanel(message: '載入活動資料...'),
                  ),
                ),
              );
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  96,
                ),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1560),
                      child: content,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _syncDoujinEvents(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在同步各活動來源...')));
    try {
      await ref.read(adminSyncJobProvider.notifier).start();
      if (!context.mounted) return;
      final result = ref.read(adminSyncJobProvider);
      final message = result.hasError
          ? '同步任務啟動失敗：${userFacingError(result.error!)}'
          : result.value?.isRunning == true
          ? '同步任務已啟動，可在來源區查看進度'
          : '已有最近的同步結果，請查看來源狀態';
      messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
      );
    } catch (error) {
      ref.invalidate(adminSyncRunsProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('同步失敗：$error')));
    }
  }

  void _showApiInfo(BuildContext context, WidgetRef ref) {
    final apiUrl = ref.read(adminRepositoryProvider).apiBaseUrl;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        clipBehavior: Clip.antiAlias,
        child: CosGradientPanel(
          icon: Icons.link,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CosSectionHeader(
                title: '後台 API 位址',
                subtitle: '目前管理工具連線的服務端點',
                icon: Icons.link,
              ),
              const SizedBox(height: 14),
              SelectableText(apiUrl),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('關閉'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([
      ref.refresh(adminStatsProvider.future),
      ref.refresh(adminEventsProvider.future),
      ref.refresh(adminUsersProvider.future),
      ref.refresh(adminSubmissionsProvider.future),
      ref.refresh(adminSyncRunsProvider.future),
      ref.refresh(adminDoujinSyncCheckProvider.future),
    ]);
  }

  Future<void> _updateUserStatus(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
    String status,
  ) async {
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateUserStatus(userId: user.id, status: status);
      await _refresh(ref);
      if (!context.mounted) return;
      _showAdminToast(context, status == 'suspended' ? '使用者已停權' : '使用者已恢復');
    } catch (error) {
      if (!context.mounted) return;
      _showAdminToast(context, '更新帳號狀態失敗：$error');
    }
  }

  Future<void> _updateUserAdmin(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
    bool isAdmin,
  ) async {
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateUserAdmin(userId: user.id, isAdmin: isAdmin);
      await _refresh(ref);
      if (!context.mounted) return;
      _showAdminToast(context, isAdmin ? '已授權 Admin' : '已撤銷 Admin');
    } catch (error) {
      if (!context.mounted) return;
      _showAdminToast(context, '更新 Admin 權限失敗：$error');
    }
  }

  Future<void> _reviewSubmission(
    BuildContext context,
    WidgetRef ref,
    EventSubmission submission, {
    required bool approve,
  }) async {
    try {
      if (approve) {
        await ref
            .read(adminRepositoryProvider)
            .approveSubmission(submission.id);
      } else {
        await ref.read(adminRepositoryProvider).rejectSubmission(submission.id);
      }
      await _refresh(ref);
      if (!context.mounted) return;
      _showAdminToast(context, approve ? '投稿已核准並上架' : '投稿已拒絕');
    } catch (error) {
      if (!context.mounted) return;
      _showAdminToast(context, '投稿審核失敗：$error');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CosEvent event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => CosSafetyConfirmDialog(
        title: '刪除活動',
        message: '確定要刪除「${event.name}」？相關預訂與位置資料也會一併移除。',
        actionLabel: '刪除',
        cancelLabel: '取消',
        icon: Icons.delete_outline,
        destructive: true,
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminRepositoryProvider).deleteEvent(event.id);
      await _refresh(ref);
      if (!context.mounted) return;
      _showAdminToast(context, '活動已刪除');
    } catch (error) {
      if (!context.mounted) return;
      _showAdminToast(context, '刪除活動失敗：$error');
    }
  }

  Future<void> _confirmDeleteUser(
    BuildContext context,
    WidgetRef ref,
    AdminUser user,
  ) async {
    final label = user.email.isEmpty ? user.nickname : user.email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => CosSafetyConfirmDialog(
        title: '刪除使用者',
        message: '確定要刪除「$label」？相關出席、位置、關注與小圈圈資料也會一併移除。',
        actionLabel: '刪除',
        cancelLabel: '取消',
        icon: Icons.person_remove_outlined,
        destructive: true,
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminRepositoryProvider).deleteUser(user.id);
      await _refresh(ref);
      if (!context.mounted) return;
      _showAdminToast(context, '使用者已刪除');
    } catch (error) {
      if (!context.mounted) return;
      _showAdminToast(context, '刪除使用者失敗：$error');
    }
  }

  Future<void> _showEditEventSheet(
    BuildContext context,
    WidgetRef ref,
    CosEvent event,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _EventEditorSheet(
        event: event,
        onSaved: () async {
          await _refresh(ref);
          if (context.mounted) _showAdminToast(context, '活動已更新');
        },
      ),
    );
  }

  Future<void> _showCreateEventSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _EventEditorSheet(
        onSaved: () async {
          await _refresh(ref);
          if (context.mounted) _showAdminToast(context, '活動已建立');
        },
      ),
    );
  }

  void _showAdminToast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EventEditorSheet extends ConsumerStatefulWidget {
  const _EventEditorSheet({this.event, required this.onSaved});

  final CosEvent? event;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends ConsumerState<_EventEditorSheet> {
  final _name = TextEditingController();
  final _category = TextEditingController(text: '綜合');
  final _startDate = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  final _endDate = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  final _venue = TextEditingController();
  final _detailedAddress = TextEditingController();
  final _fee = TextEditingController();
  final _organizer = TextEditingController();
  final _description = TextEditingController();
  final _imageUrl = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _sourceType = TextEditingController(text: '3');
  final _sourceName = TextEditingController(text: '官方人員建立');
  String _status = 'approved';
  bool _saving = false;
  String? _errorText;

  bool get _isEditing => widget.event != null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    if (event == null) return;
    _name.text = event.name;
    _category.text = event.category;
    _startDate.text = DateFormat('yyyy-MM-dd').format(event.startDate);
    _endDate.text = DateFormat('yyyy-MM-dd').format(event.endDate);
    _venue.text = event.venue;
    _detailedAddress.text = event.detailedAddress;
    _fee.text = event.fee;
    _organizer.text = event.organizer;
    _description.text = event.description;
    _imageUrl.text = event.imageUrl;
    _sourceUrl.text = event.sourceUrl;
    _sourceType.text = event.sourceType.toString();
    _sourceName.text = event.sourceName;
    _status = _validStatuses.contains(event.reviewStatus)
        ? event.reviewStatus
        : 'approved';
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _venue.dispose();
    _detailedAddress.dispose();
    _fee.dispose();
    _organizer.dispose();
    _description.dispose();
    _imageUrl.dispose();
    _sourceUrl.dispose();
    _sourceType.dispose();
    _sourceName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: '返回',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CosSectionHeader(
                    title: _isEditing ? '編輯活動' : '新增活動',
                    subtitle: '管理活動資料、來源與前台顯示狀態',
                    icon: _isEditing
                        ? Icons.edit_outlined
                        : Icons.add_location_alt,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '活動名稱'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: '分類'),
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
              decoration: const InputDecoration(labelText: '地點'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detailedAddress,
              decoration: const InputDecoration(labelText: '詳細地址'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fee,
              decoration: const InputDecoration(labelText: '費用'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _organizer,
              decoration: const InputDecoration(labelText: '主辦單位'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: '活動描述'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _imageUrl,
              decoration: const InputDecoration(labelText: '活動圖片 URL'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sourceUrl,
              decoration: const InputDecoration(labelText: '原活動網址'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sourceType,
                    decoration: const InputDecoration(
                      labelText: '來源類型',
                      helperText:
                          '1 同人誌中心 / 2 投稿 / 3 官方人員 / 4 COSMOS / 5 acosta',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sourceName,
                    decoration: const InputDecoration(labelText: '來源名稱'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '審核狀態',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in _validStatuses)
                  CosChoicePill(
                    label: _statusLabel(status),
                    selected: _status == status,
                    icon: _statusIcon(status),
                    color: _statusColor(Theme.of(context).colorScheme, status),
                    onTap: () => setState(() => _status = status),
                  ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(CosUi.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? CosLoadingPulse(
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 20,
                    )
                  : const Icon(Icons.save),
              label: Text(_isEditing ? '儲存活動' : '建立活動'),
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

  Future<void> _save() async {
    DateTime start;
    DateTime end;
    try {
      start = DateTime.parse(_startDate.text.trim());
      end = DateTime.parse(_endDate.text.trim());
    } catch (_) {
      setState(() => _errorText = '請輸入 yyyy-MM-dd 格式的日期');
      return;
    }
    if (end.isBefore(start)) {
      setState(() => _errorText = '結束日期不能早於開始日期');
      return;
    }
    final sourceType = int.tryParse(_sourceType.text.trim());
    if (sourceType == null || sourceType <= 0) {
      setState(() => _errorText = '來源類型請輸入正整數');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      final category = _category.text.trim().isEmpty
          ? '綜合'
          : _category.text.trim();
      final venue = _venue.text.trim();
      final detailedAddress = _detailedAddress.text.trim().isEmpty
          ? venue
          : _detailedAddress.text.trim();
      final sourceName = _sourceName.text.trim().isEmpty
          ? _sourceNameForType(sourceType)
          : _sourceName.text.trim();
      final event = widget.event;
      if (event == null) {
        await repository.createEvent(
          category: category,
          name: _name.text.trim(),
          startDate: start,
          endDate: end,
          venue: venue,
          detailedAddress: detailedAddress,
          fee: _fee.text.trim(),
          organizer: _organizer.text.trim(),
          description: _description.text.trim(),
          imageUrl: _imageUrl.text.trim(),
          sourceUrl: _sourceUrl.text.trim(),
          sourceType: sourceType,
          sourceName: sourceName,
          status: _status,
        );
      } else {
        await repository.updateEvent(
          eventId: event.id,
          category: category,
          name: _name.text.trim(),
          startDate: start,
          endDate: end,
          venue: venue,
          detailedAddress: detailedAddress,
          fee: _fee.text.trim(),
          organizer: _organizer.text.trim(),
          description: _description.text.trim(),
          imageUrl: _imageUrl.text.trim(),
          sourceUrl: _sourceUrl.text.trim(),
          sourceType: sourceType,
          sourceName: sourceName,
          status: _status,
        );
      }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = '儲存失敗：$error');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('儲存活動失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _validStatuses = ['pending', 'approved', 'rejected'];

  static String _statusLabel(String status) {
    return switch (status) {
      'pending' => '待審核',
      'approved' => '已上架',
      'rejected' => '已退回',
      _ => status,
    };
  }

  static IconData _statusIcon(String status) {
    return switch (status) {
      'pending' => Icons.pending_actions_outlined,
      'approved' => Icons.verified_outlined,
      'rejected' => Icons.visibility_off_outlined,
      _ => Icons.info_outline,
    };
  }

  static Color _statusColor(ColorScheme scheme, String status) {
    return switch (status) {
      'pending' => scheme.tertiary,
      'approved' => scheme.secondary,
      'rejected' => scheme.error,
      _ => scheme.primary,
    };
  }

  static String _sourceNameForType(int sourceType) {
    return switch (sourceType) {
      1 => '同人誌中心',
      2 => '投稿活動',
      3 => '官方人員建立',
      4 => 'COSMOS 創作攝影展',
      5 => 'acosta!',
      _ => '其他來源',
    };
  }
}

class _AdminDashboardLayout extends StatelessWidget {
  const _AdminDashboardLayout({
    required this.wide,
    required this.stats,
    required this.sync,
    required this.users,
    required this.submissions,
    required this.events,
  });

  final bool wide;
  final Widget stats;
  final Widget sync;
  final Widget users;
  final Widget submissions;
  final Widget events;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stats,
          const SizedBox(height: 20),
          sync,
          const SizedBox(height: 20),
          users,
          const SizedBox(height: 20),
          submissions,
          const SizedBox(height: 20),
          events,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stats,
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [sync, const SizedBox(height: 14), submissions],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 7,
              child: Column(
                children: [users, const SizedBox(height: 14), events],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdminSection extends StatelessWidget {
  const _AdminSection({
    required this.title,
    required this.icon,
    required this.child,
    this.dense = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(dense ? 16 : CosUi.radiusLg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: EdgeInsets.all(dense ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminCompactHeader(title: title, icon: icon, dense: dense),
            SizedBox(height: dense ? 10 : 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdminCompactHeader extends StatelessWidget {
  const _AdminCompactHeader({
    required this.title,
    required this.icon,
    this.dense = false,
  });

  final String title;
  final IconData icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.primary, size: dense ? 18 : 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (dense
                        ? Theme.of(context).textTheme.titleSmall
                        : Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      ('使用者', stats.users, Icons.people_alt_outlined, scheme.primary),
      ('停權', stats.suspendedUsers, Icons.person_off_outlined, scheme.error),
      ('活動', stats.events, Icons.event_outlined, scheme.secondary),
      ('已上架', stats.approvedEvents, Icons.verified_outlined, scheme.tertiary),
      ('預訂', stats.bookings, Icons.how_to_reg_outlined, scheme.primary),
      (
        '位置',
        stats.sharedLocations,
        Icons.location_on_outlined,
        scheme.secondary,
      ),
      ('小圈圈', stats.circles, Icons.groups_outlined, scheme.tertiary),
      ('投稿', stats.eventSubmissions, Icons.post_add_outlined, scheme.primary),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1280
            ? 8
            : width >= 900
            ? 4
            : 2;
        final childAspectRatio = columns >= 8 ? 2.75 : 2.15;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: childAspectRatio,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _AdminMetricTile(
              icon: item.$3,
              label: item.$1,
              value: '${item.$2}',
              color: item.$4,
              compact: columns >= 4,
            );
          },
        );
      },
    );
  }
}

class _AdminMetricTile extends StatelessWidget {
  const _AdminMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(compact ? 14 : CosUi.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 12,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: compact ? 18 : 20),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact
                                ? Theme.of(context).textTheme.titleSmall
                                : Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.w900, height: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTableShell extends StatelessWidget {
  const _AdminTableShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: children),
      ),
    );
  }
}

class _AdminCompactRow extends StatelessWidget {
  const _AdminCompactRow({required this.children, this.highlight = false});

  final List<Widget> children;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlight
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.44)
            : scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(children: children),
      ),
    );
  }
}

class _AdminEventSections extends StatelessWidget {
  const _AdminEventSections({
    required this.events,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  final List<CosEvent> events;
  final ValueChanged<CosEvent> onEdit;
  final ValueChanged<CosEvent> onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const _AdminEmptyRow(icon: Icons.event_busy, message: '目前沒有活動資料');
    }
    final now = DateTime.now();
    final active = events
        .where((event) => event.status(now) == EventStatus.active)
        .toList();
    final upcoming = events
        .where((event) => event.status(now) == EventStatus.upcoming)
        .toList();
    final ended = events
        .where((event) => event.status(now) == EventStatus.ended)
        .toList();

    return Column(
      children: [
        _AdminEventSection(
          title: '正在進行',
          subtitle: '今天仍在日期範圍內的活動',
          icon: Icons.play_circle_outline,
          events: active,
          compact: compact,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
        _AdminEventSection(
          title: '尚未開始',
          subtitle: '未來即將舉辦的活動',
          icon: Icons.upcoming_outlined,
          events: upcoming,
          compact: compact,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
        _AdminEventSection(
          title: '已結束',
          subtitle: '結束日期早於今天的活動',
          icon: Icons.history,
          events: ended,
          compact: compact,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

class _AdminEventSection extends StatelessWidget {
  const _AdminEventSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.events,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<CosEvent> events;
  final ValueChanged<CosEvent> onEdit;
  final ValueChanged<CosEvent> onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            _AdminCompactHeader(title: '$title (${events.length})', icon: icon)
          else
            CosSectionHeader(
              title: '$title (${events.length})',
              subtitle: subtitle,
              icon: icon,
            ),
          SizedBox(height: compact ? 6 : 10),
          if (events.isEmpty)
            _AdminEmptyRow(icon: icon, message: '$title目前沒有活動')
          else if (compact)
            _AdminTableShell(
              children: [
                for (final event in events.take(8))
                  _AdminEventTile(
                    event: event,
                    compact: true,
                    onEdit: () => onEdit(event),
                    onDelete: () => onDelete(event),
                  ),
                if (events.length > 8)
                  _AdminCompactRow(
                    children: [
                      Expanded(
                        child: Text(
                          '另有 ${events.length - 8} 筆，請捲動窄版或使用後台 API 檢視完整清單',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
              ],
            )
          else
            for (final event in events)
              _AdminEventTile(
                event: event,
                onEdit: () => onEdit(event),
                onDelete: () => onDelete(event),
              ),
        ],
      ),
    );
  }
}

class _AdminEventTile extends StatelessWidget {
  const _AdminEventTile({
    required this.event,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  final CosEvent event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy/MM/dd').format(event.startDate);
    final endDate = DateFormat('yyyy/MM/dd').format(event.endDate);
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      return _AdminCompactRow(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              event.startDate == event.endDate
                  ? date.substring(5)
                  : '${date.substring(5)}-${endDate.substring(5)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              event.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              event.venue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 84,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '編輯活動',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: '刪除',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CosCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CosIconBubble(icon: Icons.event_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    event.startDate == event.endDate
                        ? '$date · ${event.venue}'
                        : '$date - $endDate · ${event.venue}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '編輯活動',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton.filledTonal(
              tooltip: '刪除',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminUserList extends StatelessWidget {
  const _AdminUserList({
    required this.users,
    required this.onStatusChanged,
    required this.onAdminChanged,
    required this.onDelete,
    this.compact = false,
  });

  final List<AdminUser> users;
  final void Function(AdminUser user, String status) onStatusChanged;
  final void Function(AdminUser user, bool isAdmin) onAdminChanged;
  final ValueChanged<AdminUser> onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const CosCard(
        child: _AdminEmptyRow(
          icon: Icons.people_alt_outlined,
          message: '目前沒有使用者',
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      return _AdminTableShell(
        children: [
          _AdminCompactRow(
            highlight: true,
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  'ID',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  '使用者',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Email',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              SizedBox(
                width: 86,
                child: Text(
                  '狀態',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: 128),
            ],
          ),
          for (final user in users.take(10))
            _AdminCompactRow(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    user.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    user.nickname.isEmpty ? '未命名使用者' : user.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SizedBox(width: 86, child: _AdminStatusText(user: user)),
                SizedBox(
                  width: 128,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: user.isAdmin ? '撤銷 Admin' : '授權 Admin',
                        visualDensity: VisualDensity.compact,
                        onPressed: user.isMe
                            ? null
                            : () => onAdminChanged(user, !user.isAdmin),
                        icon: Icon(
                          user.isAdmin
                              ? Icons.admin_panel_settings
                              : Icons.admin_panel_settings_outlined,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: user.isSuspended ? '恢復帳號' : '停權帳號',
                        visualDensity: VisualDensity.compact,
                        onPressed: user.isMe
                            ? null
                            : () => onStatusChanged(
                                user,
                                user.isSuspended ? 'active' : 'suspended',
                              ),
                        icon: Icon(
                          user.isSuspended
                              ? Icons.person_add_alt_1_outlined
                              : Icons.person_off_outlined,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: '刪除使用者（極端情況）',
                        visualDensity: VisualDensity.compact,
                        onPressed: user.isMe ? null : () => onDelete(user),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (users.length > 10)
            _AdminCompactRow(
              children: [
                Expanded(
                  child: Text(
                    '另有 ${users.length - 10} 位使用者未顯示',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
        ],
      );
    }

    return Column(
      children: [
        for (final user in users)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CosCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Text(
                      (user.nickname.isNotEmpty ? user.nickname : user.email)
                              .characters
                              .firstOrNull ??
                          '?',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.nickname.isEmpty ? '未命名使用者' : user.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (user.email.isNotEmpty) user.email,
                            if (user.isAdmin) 'Admin',
                            if (user.isSuspended) '已停權',
                            if (user.isMe) '目前登入',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: user.isAdmin ? '撤銷 Admin' : '授權 Admin',
                    onPressed: user.isMe
                        ? null
                        : () => onAdminChanged(user, !user.isAdmin),
                    icon: Icon(
                      user.isAdmin
                          ? Icons.admin_panel_settings
                          : Icons.admin_panel_settings_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: user.isSuspended ? '恢復帳號' : '停權帳號',
                    onPressed: user.isMe
                        ? null
                        : () => onStatusChanged(
                            user,
                            user.isSuspended ? 'active' : 'suspended',
                          ),
                    icon: Icon(
                      user.isSuspended
                          ? Icons.person_add_alt_1_outlined
                          : Icons.person_off_outlined,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '刪除使用者（極端情況）',
                    onPressed: user.isMe ? null : () => onDelete(user),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminStatusText extends StatelessWidget {
  const _AdminStatusText({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = user.isSuspended ? scheme.error : scheme.secondary;
    final labels = [
      user.isSuspended ? '停權' : '啟用',
      if (user.isAdmin) 'Admin',
      if (user.isMe) 'Me',
    ];
    return Text(
      labels.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _DoujinSyncCheckCard extends StatelessWidget {
  const _DoujinSyncCheckCard({required this.check, this.compact = false});

  final AdminDoujinSyncCheck check;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sourceError = check.sourceError;
    final sourceLabel = check.sourceAvailable
        ? '${check.sourceCount} 筆'
        : '無法讀取';
    final statusColor = check.isFullyMatched ? scheme.secondary : scheme.error;
    return CosCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CosIconBubble(
                icon: check.isFullyMatched
                    ? Icons.cloud_done_outlined
                    : Icons.sync_problem_outlined,
                color: statusColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !check.sourceAvailable
                          ? '尚無可比對的同步快照'
                          : check.isFullyMatched
                          ? '同步一致'
                          : '同步需要處理',
                      style:
                          (compact
                                  ? Theme.of(context).textTheme.titleSmall
                                  : Theme.of(context).textTheme.titleMedium)
                              ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      check.sourceAvailable
                          ? '最近成功快照與正式 DB 比對${check.checkedAt.isEmpty ? '' : ' · ${DateFormat('MM/dd HH:mm').format(DateTime.parse(check.checkedAt).toLocal())}'}'
                          : sourceError?.message ?? '請先執行來源同步',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              CosBadge(
                label: !check.sourceAvailable
                    ? '無法比對'
                    : check.isCountMatched
                    ? '數量一致'
                    : '數量不一致',
                icon: !check.sourceAvailable
                    ? Icons.help_outline
                    : check.isCountMatched
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                highlighted: true,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SyncMetricChip(
                label: '同人誌中心',
                value: sourceLabel,
                icon: Icons.public,
                color: scheme.primary,
              ),
              _SyncMetricChip(
                label: '正式 DB',
                value: '${check.databaseCount} 筆',
                icon: Icons.storage_outlined,
                color: scheme.secondary,
              ),
              _SyncMetricChip(
                label: '目前/未來',
                value: '${check.databaseCurrentOrFutureCount} 筆',
                icon: Icons.event_available_outlined,
                color: scheme.tertiary,
              ),
              _SyncMetricChip(
                label: '已結束',
                value: '${check.databaseEndedCount} 筆',
                icon: Icons.history,
                color: scheme.outline,
              ),
            ],
          ),
          if (sourceError != null) ...[
            const SizedBox(height: 12),
            _SyncNotice(
              icon: Icons.cloud_off_outlined,
              title: '來源讀取失敗：${sourceError.code}',
              message: sourceError.message,
              color: scheme.error,
            ),
          ],
          if (check.sourceAvailable) ...[
            const SizedBox(height: 12),
            if (compact)
              Row(
                children: [
                  Expanded(
                    child: _SyncDiffPreview(
                      title: '來源有、DB 沒有',
                      emptyMessage: '沒有漏匯活動',
                      events: check.missingInDatabase,
                      color: scheme.error,
                      icon: Icons.add_alert_outlined,
                      limit: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SyncDiffPreview(
                      title: 'DB 有、來源沒有',
                      emptyMessage: '沒有多餘活動',
                      events: check.extraInDatabase,
                      color: scheme.tertiary,
                      icon: Icons.inventory_2_outlined,
                      limit: 2,
                    ),
                  ),
                ],
              )
            else ...[
              _SyncDiffPreview(
                title: '來源有、DB 沒有',
                emptyMessage: '沒有漏匯活動',
                events: check.missingInDatabase,
                color: scheme.error,
                icon: Icons.add_alert_outlined,
              ),
              const SizedBox(height: 10),
              _SyncDiffPreview(
                title: 'DB 有、來源沒有',
                emptyMessage: '沒有多餘活動',
                events: check.extraInDatabase,
                color: scheme.tertiary,
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SyncMetricChip extends StatelessWidget {
  const _SyncMetricChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncNotice extends StatelessWidget {
  const _SyncNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncDiffPreview extends StatelessWidget {
  const _SyncDiffPreview({
    required this.title,
    required this.emptyMessage,
    required this.events,
    required this.color,
    required this.icon,
    this.limit = 5,
  });

  final String title;
  final String emptyMessage;
  final List<AdminDoujinCheckEvent> events;
  final Color color;
  final IconData icon;
  final int limit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$title (${events.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (events.isEmpty)
              Text(emptyMessage, style: Theme.of(context).textTheme.bodySmall)
            else
              for (final event in events.take(limit))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${event.startDate} · ${event.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            if (events.length > limit)
              Text(
                '另有 ${events.length - limit} 筆未顯示',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _SyncRunList extends StatelessWidget {
  const _SyncRunList({required this.runs, this.compact = false});

  final List<AdminSyncRun> runs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const CosCard(
        child: _AdminEmptyRow(
          icon: Icons.sync_problem_outlined,
          message: '尚未有同步紀錄',
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final latest = <String, AdminSyncRun>{};
    for (final run in runs) {
      latest.putIfAbsent(run.sourceGroup, () => run);
    }
    final displayedRuns = latest.values;
    if (compact) {
      return _AdminTableShell(
        children: [
          for (final run in displayedRuns.take(4))
            _AdminCompactRow(
              children: [
                Icon(
                  run.isLegacyAggregate
                      ? Icons.help_outline
                      : run.isSuccess
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: run.isLegacyAggregate
                      ? scheme.onSurfaceVariant
                      : run.isSuccess
                      ? scheme.secondary
                      : scheme.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    run.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    run.resultLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Text(
                    run.createdAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
        ],
      );
    }
    return Column(
      children: [
        for (final run in displayedRuns.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CosCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CosIconBubble(
                    icon: run.isLegacyAggregate
                        ? Icons.help_outline
                        : run.isSuccess
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: run.isLegacyAggregate
                        ? scheme.onSurfaceVariant
                        : run.isSuccess
                        ? scheme.secondary
                        : scheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          run.sourceName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${run.createdAt} · ${run.resultLabel}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (!run.isSuccess && run.errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            run.errorMessage,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SubmissionList extends StatelessWidget {
  const _SubmissionList({
    required this.submissions,
    required this.onApprove,
    required this.onReject,
    this.compact = false,
  });

  final List<EventSubmission> submissions;
  final ValueChanged<EventSubmission> onApprove;
  final ValueChanged<EventSubmission> onReject;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (submissions.isEmpty) {
      return const CosCard(
        child: _AdminEmptyRow(icon: Icons.post_add_outlined, message: '目前沒有投稿'),
      );
    }

    return Column(
      children: [
        for (final submission in submissions)
          _SubmissionTile(
            submission: submission,
            compact: compact,
            onApprove: () => onApprove(submission),
            onReject: () => onReject(submission),
          ),
      ],
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({
    required this.submission,
    required this.onApprove,
    required this.onReject,
    this.compact = false,
  });

  final EventSubmission submission;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy/MM/dd').format(submission.startDate);
    final pending = submission.reviewStatus == 'pending';

    if (compact) {
      return _AdminCompactRow(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              date.substring(5),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              submission.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              submission.venue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 118,
            child: pending
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: '核准上架',
                        visualDensity: VisualDensity.compact,
                        onPressed: onApprove,
                        icon: const Icon(Icons.check, size: 18),
                      ),
                      IconButton(
                        tooltip: '拒絕',
                        visualDensity: VisualDensity.compact,
                        onPressed: onReject,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _statusText(submission.reviewStatus),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CosCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    submission.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CosBadge(
                  label: _statusText(submission.reviewStatus),
                  icon: pending
                      ? Icons.pending_actions_outlined
                      : Icons.verified_outlined,
                  highlighted: pending,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('$date · ${submission.venue}'),
            if (submission.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(submission.description),
            ],
            if (pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check),
                      label: const Text('核准上架'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close),
                      label: const Text('拒絕'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusText(String status) {
    return switch (status) {
      'approved' => '已核准',
      'rejected' => '已拒絕',
      _ => '待審',
    };
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CosIconBubble(icon: Icons.error_outline, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      child: Row(
        children: [
          CosLoadingPulse(color: scheme.secondary, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _AdminEmptyRow extends StatelessWidget {
  const _AdminEmptyRow({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CosIconBubble(icon: icon),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    );
  }
}
