import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/repositories/report_repository.dart';
import '../../../shared/widgets/cos_ui.dart';

class ReportManagementPage extends ConsumerStatefulWidget {
  const ReportManagementPage({super.key});

  @override
  ConsumerState<ReportManagementPage> createState() =>
      _ReportManagementPageState();
}

class _ReportManagementPageState extends ConsumerState<ReportManagementPage> {
  ReportStatus _status = ReportStatus.pending;
  List<AdminContentReport> _items = [];
  String? _nextBeforeId;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (append && (_loading || _loadingMore || _nextBeforeId == null)) return;
    final generation = ++_generation;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
      }
      _error = null;
    });
    try {
      final page = await ref
          .read(reportRepositoryProvider)
          .fetchReports(
            status: _status,
            beforeId: append ? _nextBeforeId : null,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = append ? [..._items, ...page.items] : page.items;
        _nextBeforeId = page.nextBeforeId;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = reportErrorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _review(AdminContentReport report) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (_) => _ReviewSheet(report: report),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('檢舉管理'),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<ReportStatus>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '審核狀態'),
                    items: ReportStatus.values
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                        )
                        .toList(),
                    onChanged: (status) {
                      if (status == null || status == _status) return;
                      setState(() {
                        _status = status;
                        _items = [];
                        _nextBeforeId = null;
                      });
                      _load();
                    },
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _load(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              children: [
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _load(
                                    append:
                                        _items.isNotEmpty &&
                                        _nextBeforeId != null,
                                  ),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重試'),
                                ),
                              ],
                            ),
                          ),
                        if (!_loading && _error == null && _items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('目前沒有這個狀態的檢舉')),
                          ),
                        for (final report in _items) ...[
                          _ReportEntry(
                            report: report,
                            onReview: _loading ? null : () => _review(report),
                          ),
                          const Divider(height: 1),
                        ],
                        if (_nextBeforeId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: TextButton.icon(
                              onPressed: _loading || _loadingMore
                                  ? null
                                  : () => _load(append: true),
                              icon: _loadingMore
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.expand_more),
                              label: const Text('載入更多'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _snapshotLabels = {
  'nickname': '暱稱',
  'bio': '自我介紹',
  'role': '出席身分',
  'characterName': '角色',
  'message': '出席備註',
  'name': '圈圈名稱',
  'description': '圈圈介紹',
};

String _date(DateTime? value) => value == null
    ? '時間不詳'
    : DateFormat('yyyy/MM/dd HH:mm').format(value.toLocal());

class _ReportEntry extends StatelessWidget {
  const _ReportEntry({required this.report, required this.onReview});
  final AdminContentReport report;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: ValueKey('${report.id}-${report.version}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      title: Text(
        '#${report.id} · ${report.targetType.label} · ${report.reason.label}',
      ),
      subtitle: Text('${report.status.label} · ${_date(report.createdAt)}'),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('檢舉人：${report.reporterUserId ?? '已刪除帳號'}'),
        Text('對象帳號：${report.targetUserId ?? '已刪除帳號'}'),
        if (report.eventId != null)
          Text('活動：${report.eventId} · 第 ${report.dayIndex} 天'),
        if (report.circleId != null) Text('小圈圈：${report.circleId}'),
        const SizedBox(height: 12),
        Text('補充說明', style: theme.textTheme.titleSmall),
        Text(
          report.details?.isNotEmpty == true ? report.details! : '無補充說明或已清除',
        ),
        const SizedBox(height: 12),
        Text('檢舉時內容', style: theme.textTheme.titleSmall),
        if (report.snapshot == null)
          const Text('證據已清除，無法執行內容或帳號操作')
        else ...[
          for (final entry in report.snapshot!.entries)
            if (_snapshotLabels.containsKey(entry.key))
              Text(
                '${_snapshotLabels[entry.key]}：${entry.value == '' ? '未填寫' : entry.value ?? '未填寫'}',
              ),
          if (report.evidencePhotoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in report.evidencePhotoUrls)
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: InkWell(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => Dialog(
                                child: SizedBox(
                                  width: 640,
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.7,
                                  child: Column(
                                    children: [
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: IconButton(
                                          tooltip: '關閉照片',
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ),
                                      Expanded(
                                        child: InteractiveViewer(
                                          child: _EvidencePhoto(
                                            url: url,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            child: _EvidencePhoto(url: url),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton.filledTonal(
                            tooltip: '複製照片網址',
                            onPressed: () async {
                              if (!isSafeReportPhotoUrl(url)) return;
                              await Clipboard.setData(ClipboardData(text: url));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('照片網址已複製')),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          Text(
            '證據到期：${_date(report.evidenceExpiresAt)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (report.reviews.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('最近審核紀錄', style: theme.textTheme.titleSmall),
          for (final review in report.reviews)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_date(review.createdAt)} · 管理員 ${review.adminUserId ?? '已刪除'}\n'
                '${review.status.label} · ${review.action.label}\n${review.note ?? '說明已清除'}',
              ),
            ),
        ],
        if (!report.status.isClosed) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('審核'),
            ),
          ),
        ],
      ],
    );
  }
}

class _EvidencePhoto extends StatelessWidget {
  const _EvidencePhoto({required this.url, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    const fallback = Center(
      child: Icon(Icons.broken_image_outlined, semanticLabel: '照片無法載入'),
    );
    if (!isSafeReportPhotoUrl(url)) return fallback;
    return Image.network(
      url,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      semanticLabel: '檢舉時照片',
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.report});
  final AdminContentReport report;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

enum _ReviewPhase { idle, confirming, saving }

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  late ReportStatus _status;
  ReportAction _action = ReportAction.none;
  _ReviewPhase _phase = _ReviewPhase.idle;
  bool get _saving => _phase != _ReviewPhase.idle;
  bool _outdated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.report.status == ReportStatus.pending
        ? ReportStatus.reviewing
        : ReportStatus.resolved;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _outdated || !_formKey.currentState!.validate()) return;
    setState(() {
      _phase = _action == ReportAction.none
          ? _ReviewPhase.saving
          : _ReviewPhase.confirming;
      _error = null;
    });
    if (_action != ReportAction.none) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => CosSafetyConfirmDialog(
          title: _action.label,
          message: '確認對此檢舉執行「${_action.label}」並結案？',
          actionLabel: '確認處置',
          destructive: true,
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _phase = _ReviewPhase.idle);
        return;
      }
      setState(() => _phase = _ReviewPhase.saving);
    }
    try {
      await ref
          .read(reportRepositoryProvider)
          .review(
            report: widget.report,
            status: _status,
            action: _action,
            note: _note.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _ReviewPhase.idle;
          _error = reportErrorMessage(error);
          _outdated = reportErrorCode(error) == 'stale_report';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '審核 #${widget.report.id}',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '關閉',
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(_outdated),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ReportStatus>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '變更狀態'),
                    items: ReportStatus.values
                        .where((status) => status != widget.report.status)
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                        )
                        .toList(),
                    onChanged: _saving || _outdated
                        ? null
                        : (status) {
                            if (status != null) {
                              setState(() {
                                _status = status;
                                _action = ReportAction.none;
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ReportAction>(
                    key: ValueKey(_status),
                    initialValue: _action,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '處置方式'),
                    items: widget.report.availableActions
                        .map(
                          (action) => DropdownMenuItem(
                            value: action,
                            child: Text(action.label),
                          ),
                        )
                        .toList(),
                    onChanged:
                        _saving || _outdated || _status != ReportStatus.resolved
                        ? null
                        : (action) {
                            if (action != null) {
                              setState(() => _action = action);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _note,
                    enabled: !_saving && !_outdated,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: InputDecoration(
                      labelText: _action == ReportAction.none
                          ? '審核說明（選填）'
                          : '處置原因（必填）',
                    ),
                    validator: (value) {
                      if ((value ?? '').runes.length > 1000) {
                        return '審核說明不可超過 1000 字';
                      }
                      if (_action != ReportAction.none &&
                          (value ?? '').trim().isEmpty) {
                        return '請填寫處置原因';
                      }
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_outdated)
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新載入'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _phase == _ReviewPhase.saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(switch (_phase) {
                        _ReviewPhase.saving => '儲存中',
                        _ReviewPhase.confirming => '等待確認',
                        _ReviewPhase.idle => '儲存審核',
                      }),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
