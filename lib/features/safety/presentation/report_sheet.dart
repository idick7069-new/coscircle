import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repositories/report_repository.dart';

Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  String? targetUserId,
  int? eventId,
  int? dayIndex,
  String? circleId,
  String? targetLabel,
}) async {
  final ReportTarget target;
  switch (targetType) {
    case 'user' when targetUserId != null:
      target = ReportTarget.user(userId: targetUserId, label: targetLabel);
    case 'booking'
        when targetUserId != null && eventId != null && dayIndex != null:
      target = ReportTarget.booking(
        userId: targetUserId,
        eventId: eventId,
        dayIndex: dayIndex,
        label: targetLabel,
      );
    case 'circle' when circleId != null:
      target = ReportTarget.circle(circleId: circleId, label: targetLabel);
    default:
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('檢舉對象資料不完整，請重新整理')));
      return;
  }
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => _ReportSheet(target: target),
  );
  if (submitted == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('檢舉已送出，將由管理員審核')));
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.target});
  final ReportTarget target;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _formKey = GlobalKey<FormState>();
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(reportRepositoryProvider)
          .submit(
            target: widget.target,
            reason: _reason!,
            details: _details.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = reportErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_submitting,
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
                          '檢舉${widget.target.type.label}',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '關閉',
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (widget.target.label?.isNotEmpty == true) ...[
                    Text(
                      widget.target.label!,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Text('檢舉將交由管理員私下審核，檢舉人身分不會通知被檢舉者。'),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<ReportReason>(
                    initialValue: _reason,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '檢舉原因'),
                    items: ReportReason.values
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason,
                            child: Text(reason.label),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (reason) => setState(() => _reason = reason),
                    validator: (reason) => reason == null ? '請選擇檢舉原因' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _details,
                    enabled: !_submitting,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: const InputDecoration(labelText: '補充說明（選填）'),
                    validator: (value) => (value ?? '').runes.length > 1000
                        ? '補充內容不可超過 1000 字'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.flag_outlined),
                    label: Text(_submitting ? '送出中' : '送出檢舉'),
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
