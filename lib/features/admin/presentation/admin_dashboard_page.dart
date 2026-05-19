import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/admin_stats.dart';
import '../../../core/models/event.dart';
import '../../../core/models/event_submission.dart';
import '../../../core/repositories/admin_repository.dart';

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  return ref.watch(adminRepositoryProvider).fetchStats();
});

final adminEventsProvider = FutureProvider.autoDispose<List<CosEvent>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchEvents();
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
                error: (error, stack) =>
                    _ErrorPanel(message: '資料庫狀態載入失敗：$error'),
                loading: () => const _LoadingPanel(message: '載入資料庫狀態...'),
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
                error: (error, stack) => _ErrorPanel(message: '投稿載入失敗：$error'),
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
                        onDelete: () => _confirmDelete(context, ref, event),
                      ),
                  ],
                ),
                error: (error, stack) => _ErrorPanel(message: '活動載入失敗：$error'),
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
      ref.refresh(adminSubmissionsProvider.future),
    ]);
  }

  Future<void> _reviewSubmission(
    BuildContext context,
    WidgetRef ref,
    EventSubmission submission, {
    required bool approve,
  }) async {
    if (approve) {
      await ref.read(adminRepositoryProvider).approveSubmission(submission.id);
    } else {
      await ref.read(adminRepositoryProvider).rejectSubmission(submission.id);
    }
    await _refresh(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(approve ? '投稿已核准並上架' : '投稿已拒絕')));
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

    await ref.read(adminRepositoryProvider).deleteEvent(event.id);
    await _refresh(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('活動已刪除')));
  }

  Future<void> _showCreateEventSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CreateEventSheet(onCreated: () => _refresh(ref)),
    );
  }
}

class _CreateEventSheet extends ConsumerStatefulWidget {
  const _CreateEventSheet({required this.onCreated});

  final VoidCallback onCreated;

  @override
  ConsumerState<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends ConsumerState<_CreateEventSheet> {
  final _name = TextEditingController();
  final _category = TextEditingController(text: '綜合');
  final _startDate = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  final _endDate = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  final _venue = TextEditingController();
  final _fee = TextEditingController();
  final _organizer = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _venue.dispose();
    _fee.dispose();
    _organizer.dispose();
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
            Text('新增活動', style: Theme.of(context).textTheme.titleLarge),
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
              decoration: const InputDecoration(labelText: '地點'),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await ref
                    .read(adminRepositoryProvider)
                    .createEvent(
                      category: _category.text.trim().isEmpty
                          ? '綜合'
                          : _category.text.trim(),
                      name: _name.text.trim(),
                      startDate: DateTime.parse(_startDate.text.trim()),
                      endDate: DateTime.parse(_endDate.text.trim()),
                      venue: _venue.text.trim(),
                      fee: _fee.text.trim(),
                      organizer: _organizer.text.trim(),
                      description: _description.text.trim(),
                    );
                widget.onCreated();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.save),
              label: const Text('建立'),
            ),
          ],
        ),
      ),
    );
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
  const _AdminEventTile({required this.event, required this.onDelete});

  final CosEvent event;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy/MM/dd').format(event.startDate);
    return Card(
      child: ListTile(
        title: Text(event.name),
        subtitle: Text('$date · ${event.venue}'),
        leading: const Icon(Icons.event),
        trailing: IconButton(
          tooltip: '刪除',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
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
