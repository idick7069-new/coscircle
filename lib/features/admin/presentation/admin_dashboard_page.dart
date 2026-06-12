import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/admin_stats.dart';
import '../../../core/models/admin_user.dart';
import '../../../core/models/event.dart';
import '../../../core/models/event_submission.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/error_message.dart';

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

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final events = ref.watch(adminEventsProvider);
    final users = ref.watch(adminUsersProvider);
    final submissions = ref.watch(adminSubmissionsProvider);

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
            tooltip: '同步同人誌中心',
            onPressed: () => _syncDoujinEvents(context, ref),
            icon: const Icon(Icons.cloud_sync_outlined),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              stats.when(
                data: (value) => _StatsGrid(stats: value),
                error: (error, stack) => _ErrorPanel(
                  message: '資料庫狀態載入失敗：${userFacingError(error)}',
                ),
                loading: () => const _LoadingPanel(message: '載入資料庫狀態...'),
              ),
              const SizedBox(height: 20),
              Text(
                '使用者管理',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              users.when(
                data: (items) => _AdminUserList(
                  users: items,
                  onDelete: (user) => _confirmDeleteUser(context, ref, user),
                ),
                error: (error, stack) =>
                    _ErrorPanel(message: '使用者載入失敗：${userFacingError(error)}'),
                loading: () => const _LoadingPanel(message: '載入使用者資料...'),
              ),
              const SizedBox(height: 20),
              Text(
                '投稿審核',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              submissions.when(
                data: (items) => _SubmissionList(
                  submissions: items,
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
                error: (error, stack) =>
                    _ErrorPanel(message: '投稿載入失敗：${userFacingError(error)}'),
                loading: () => const _LoadingPanel(message: '載入投稿資料...'),
              ),
              const SizedBox(height: 20),
              Text(
                '活動資料',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              events.when(
                data: (items) => Column(
                  children: [
                    for (final event in items)
                      _AdminEventTile(
                        event: event,
                        onEdit: () => _showEditEventSheet(context, ref, event),
                        onDelete: () => _confirmDelete(context, ref, event),
                      ),
                  ],
                ),
                error: (error, stack) =>
                    _ErrorPanel(message: '活動載入失敗：${userFacingError(error)}'),
                loading: () => const _LoadingPanel(message: '載入活動資料...'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncDoujinEvents(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在同步同人誌中心活動...')));
    try {
      final count = await ref.read(adminRepositoryProvider).syncDoujinEvents();
      await _refresh(ref);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('同人誌中心同步完成：$count 筆活動')));
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('同步失敗：$error')));
    }
  }

  void _showApiInfo(BuildContext context, WidgetRef ref) {
    final apiUrl = ref.read(adminRepositoryProvider).apiBaseUrl;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('後台 API 位址'),
        content: Text(apiUrl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([
      ref.refresh(adminStatsProvider.future),
      ref.refresh(adminEventsProvider.future),
      ref.refresh(adminUsersProvider.future),
      ref.refresh(adminSubmissionsProvider.future),
    ]);
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
      builder: (context) => AlertDialog(
        title: const Text('刪除活動'),
        content: Text('確定要刪除「${event.name}」？相關預訂與位置資料也會一併移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
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
      builder: (context) => AlertDialog(
        title: const Text('刪除使用者'),
        content: Text('確定要刪除「$label」？相關出席、位置、關注與小圈圈資料也會一併移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
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
  final _sourceName = TextEditingController(text: '管理後台');
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
            Text(
              _isEditing ? '編輯活動' : '新增活動',
              style: Theme.of(context).textTheme.titleLarge,
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
                      helperText: '1 同人誌中心 / 2 投稿 / 3 後台',
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
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: '審核狀態'),
              items: _validStatuses
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _status = value);
              },
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
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

  static String _sourceNameForType(int sourceType) {
    return switch (sourceType) {
      1 => '同人誌中心',
      2 => '投稿活動',
      3 => '管理後台',
      _ => '其他來源',
    };
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('使用者', stats.users, Icons.people_alt_outlined),
      ('活動', stats.events, Icons.event_outlined),
      ('已上架', stats.approvedEvents, Icons.verified_outlined),
      ('預訂', stats.bookings, Icons.how_to_reg_outlined),
      ('位置', stats.sharedLocations, Icons.location_on_outlined),
      ('小圈圈', stats.circles, Icons.groups_outlined),
      ('投稿', stats.eventSubmissions, Icons.post_add_outlined),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.05,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(item.$3),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${item.$2}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminEventTile extends StatelessWidget {
  const _AdminEventTile({
    required this.event,
    required this.onEdit,
    required this.onDelete,
  });

  final CosEvent event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy/MM/dd').format(event.startDate);
    final endDate = DateFormat('yyyy/MM/dd').format(event.endDate);
    return Card(
      child: ListTile(
        title: Text(event.name),
        subtitle: Text(
          event.startDate == event.endDate
              ? '$date · ${event.venue}'
              : '$date - $endDate · ${event.venue}',
        ),
        leading: const Icon(Icons.event),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: '編輯活動',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
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
  const _AdminUserList({required this.users, required this.onDelete});

  final List<AdminUser> users;
  final ValueChanged<AdminUser> onDelete;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('目前沒有使用者')),
      );
    }
    return Column(
      children: [
        for (final user in users)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  (user.nickname.isNotEmpty ? user.nickname : user.email)
                          .characters
                          .firstOrNull ??
                      '?',
                ),
              ),
              title: Text(user.nickname.isEmpty ? '未命名使用者' : user.nickname),
              subtitle: Text(
                [
                  if (user.email.isNotEmpty) user.email,
                  if (user.isAdmin) 'Admin',
                  if (user.isMe) '目前登入',
                ].join(' · '),
              ),
              trailing: IconButton(
                tooltip: '刪除使用者',
                onPressed: user.isMe ? null : () => onDelete(user),
                icon: const Icon(Icons.delete_outline),
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
  });

  final List<EventSubmission> submissions;
  final ValueChanged<EventSubmission> onApprove;
  final ValueChanged<EventSubmission> onReject;

  @override
  Widget build(BuildContext context) {
    if (submissions.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('目前沒有投稿')),
      );
    }

    return Column(
      children: [
        for (final submission in submissions)
          _SubmissionTile(
            submission: submission,
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
  });

  final EventSubmission submission;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy/MM/dd').format(submission.startDate);
    final pending = submission.reviewStatus == 'pending';

    return Card(
      child: Padding(
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
                Chip(label: Text(_statusText(submission.reviewStatus))),
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
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
