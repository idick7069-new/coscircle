import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/models/booking.dart';
import '../../../core/models/event.dart';
import '../../../core/models/event_day_item.dart';
import '../../../core/models/participant.dart';
import '../../../core/models/work.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/upload_image_data.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/user_action.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../works/presentation/work_selector.dart';

Future<void> showEventBookingSheet(
  BuildContext context,
  WidgetRef ref,
  CosEvent event, {
  required int dayIndex,
}) async {
  final day = EventDayItem(event: event, dayIndex: dayIndex);
  if (day.status(DateTime.now()) == EventStatus.ended) return;
  EventParticipant? initial;
  final ready = await runUserAction(context, () async {
    final participants = await ref.read(
      eventParticipantsProvider(event.id).future,
    );
    initial = participants
        .where((item) => item.isMe && item.dayIndex == dayIndex)
        .firstOrNull;
    if (day.isJoined && initial == null) {
      throw Exception('自己的出席資訊尚未載入，請重新整理後再試');
    }
  });
  if (!ready || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BookingSheet(
      event: event,
      initialDayIndex: dayIndex,
      initialParticipant: initial,
    ),
  );
}

class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({
    super.key,
    required this.event,
    this.initialDayIndex = 1,
    this.initialParticipant,
  });

  final CosEvent event;
  final int initialDayIndex;
  final EventParticipant? initialParticipant;

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<BookingSheet> {
  static const _interactionOptions = ['認親', '拍照', '交換無料', '聊天', '一起逛', '找同作品'];
  static const _statusOptions = [
    ('open', '可來找我'),
    ('moving', '移動中'),
    ('resting', '休息中'),
    ('quiet', '暫不互動'),
    ('left', '已離場'),
  ];

  ParticipantRole _role = ParticipantRole.coser;
  final _characterController = TextEditingController();
  final _availableTimeController = TextEditingController();
  final _messageController = TextEditingController();
  final Set<String> _interactionTags = {};
  String _presenceStatus = 'open';
  String? _outfitImagePath;
  XFile? _pickedOutfitImage;
  WorkTag? _selectedWork;
  int _dayIndex = 1;
  bool _submitting = false;
  bool _allowClose = false;
  bool _confirmingDiscard = false;

  bool get _hasChanges {
    final initial = widget.initialParticipant;
    final tags = initial?.interactionTags ?? const <String>[];
    return _dayIndex != (initial?.dayIndex ?? widget.initialDayIndex) ||
        _role.name != (initial?.role ?? 'coser') ||
        _characterController.text != (initial?.characterName ?? '') ||
        _messageController.text != (initial?.message ?? '') ||
        _availableTimeController.text != (initial?.availableTime ?? '') ||
        _presenceStatus != (initial?.presenceStatus ?? 'open') ||
        (_selectedWork?.id ?? '') != (initial?.workId ?? '') ||
        _pickedOutfitImage != null ||
        (_outfitImagePath ?? '') != (initial?.outfitImageUrl ?? '') ||
        tags.length != _interactionTags.length ||
        !tags.every(_interactionTags.contains);
  }

  @override
  void initState() {
    super.initState();
    _dayIndex = widget.initialDayIndex;
    final participant = widget.initialParticipant;
    if (participant != null) {
      _role = _roleFromString(participant.role);
      _dayIndex = participant.dayIndex;
      _characterController.text = participant.characterName;
      _availableTimeController.text = participant.availableTime;
      _messageController.text = participant.message;
      _interactionTags.addAll(participant.interactionTags);
      _presenceStatus = participant.presenceStatus;
      _outfitImagePath = participant.outfitImageUrl.isEmpty
          ? null
          : participant.outfitImageUrl;
      if (participant.workId.isNotEmpty || participant.workName.isNotEmpty) {
        _selectedWork = WorkTag(
          id: participant.workId,
          name: participant.workName,
        );
      }
    }
    for (final controller in [
      _characterController,
      _availableTimeController,
      _messageController,
    ]) {
      controller.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _characterController.dispose();
    _availableTimeController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final scheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final roleName = participantRoleLabel(_role.name);
    final roleColor = participantRoleColorForScheme(_role.name, scheme);

    return PopScope(
      canPop: !_submitting && (_allowClose || !_hasChanges),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.86,
            ),
            child: AbsorbPointer(
              absorbing: _submitting,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  CosReveal(
                    child: CosGradientPanel(
                      icon: Icons.badge_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CosSectionHeader(
                            title: widget.initialParticipant != null
                                ? '修改參戰名片'
                                : '建立參戰名片',
                            subtitle: '讓同好知道你哪天會到、扮什麼、怎麼找你互動',
                            icon: Icons.theater_comedy_outlined,
                            trailing: CosBadge(
                              label: roleName,
                              icon: Icons.badge_outlined,
                              highlighted: true,
                              color: roleColor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: CosMetricTile(
                                  icon: Icons.calendar_month_outlined,
                                  label: '參加日',
                                  value: 'D$_dayIndex',
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: CosMetricTile(
                                  icon: Icons.forum_outlined,
                                  label: '互動方式',
                                  value: _interactionTags.isEmpty
                                      ? '待選擇'
                                      : '${_interactionTags.length} 種',
                                  color: scheme.secondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: CosMetricTile(
                                  icon: Icons.sensors_outlined,
                                  label: '現場狀態',
                                  value: _presenceStatusLabel(_presenceStatus),
                                  color: scheme.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BookingSection(
                    title: '日期與身份',
                    subtitle: '先決定這張名片代表哪一天、你在現場的角色',
                    icon: Icons.event_available_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '參加日',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (
                              var index = 1;
                              index <= _eventDayCount(event);
                              index += 1
                            )
                              CosChoicePill(
                                label:
                                    'D$index · ${DateFormat('MM/dd').format(event.startDate.add(Duration(days: index - 1)))}',
                                selected: _dayIndex == index,
                                enabled: false,
                                icon: Icons.calendar_today_outlined,
                                onTap: () => setState(() => _dayIndex = index),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _RoleChoiceGrid(
                          selectedRole: _role,
                          onChanged: (role) => setState(() => _role = role),
                        ),
                      ],
                    ),
                  ),
                  if (_role == ParticipantRole.coser) ...[
                    const SizedBox(height: 12),
                    _BookingSection(
                      title: '作品與角色',
                      subtitle: '這會成為同好認親時最先看到的資訊',
                      icon: Icons.auto_awesome,
                      child: Column(
                        children: [
                          WorkSingleSelector(
                            label: '作品',
                            selected: _selectedWork,
                            onChanged: (work) =>
                                setState(() => _selectedWork = work),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _characterController,
                            decoration: const InputDecoration(labelText: '角色名'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _BookingSection(
                    title: '現場互動',
                    subtitle: '把界線和歡迎方式講清楚，認親會更順',
                    icon: Icons.forum_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _availableTimeController,
                          decoration: const InputDecoration(
                            labelText: '預計出沒時間',
                            hintText: '例如 13:00 - 16:00、午後、整天',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '歡迎互動方式',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in _interactionOptions)
                              CosChoicePill(
                                label: option,
                                selected: _interactionTags.contains(option),
                                icon: Icons.add_circle_outline,
                                color: Theme.of(context).colorScheme.secondary,
                                onTap: () {
                                  setState(() {
                                    if (_interactionTags.contains(option)) {
                                      _interactionTags.remove(option);
                                    } else {
                                      _interactionTags.add(option);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _PresenceStatusSelector(
                          value: _presenceStatus,
                          options: _statusOptions,
                          onChanged: (value) =>
                              setState(() => _presenceStatus = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _BookingSection(
                    title: '照片與備註',
                    subtitle: '放一點辨識線索，現場比較容易找到彼此',
                    icon: Icons.photo_library_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _OutfitImagePicker(
                          imagePath: _outfitImagePath,
                          onPick: _pickOutfitImage,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            labelText: '備註',
                            hintText: '例如 看到我可以打招呼、社恐請先私訊',
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BookingSubmitBar(
                    editing: widget.initialParticipant != null,
                    submitting:
                        _submitting ||
                        EventDayItem(
                              event: event,
                              dayIndex: _dayIndex,
                            ).status(DateTime.now()) ==
                            EventStatus.ended,
                    onRemove:
                        widget.initialParticipant == null ||
                            EventDayItem(
                                  event: event,
                                  dayIndex: _dayIndex,
                                ).status(DateTime.now()) ==
                                EventStatus.ended
                        ? null
                        : () => _removeAttendance(context, event),
                    onSave: () => _saveAttendance(context, event),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_submitting || _confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => const CosSafetyConfirmDialog(
        title: '捨棄未儲存的預定？',
        message: '這次修改尚未儲存。',
        actionLabel: '捨棄',
        cancelLabel: '繼續編輯',
        icon: Icons.edit_off_outlined,
        destructive: true,
      ),
    );
    _confirmingDiscard = false;
    if (discard == true && mounted) {
      setState(() => _allowClose = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _pickOutfitImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (image == null || !mounted) return;
    try {
      await readUploadImage(image);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(error))));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _outfitImagePath = image.path;
      _pickedOutfitImage = image;
    });
  }

  Future<void> _saveAttendance(BuildContext context, CosEvent event) async {
    if (_submitting ||
        EventDayItem(
              event: event,
              dayIndex: _dayIndex,
            ).status(DateTime.now()) ==
            EventStatus.ended) {
      return;
    }
    setState(() => _submitting = true);
    try {
      var outfitImageUrl = _outfitImagePath;
      final pickedOutfitImage = _pickedOutfitImage;
      if (pickedOutfitImage != null) {
        final upload = await readUploadImage(pickedOutfitImage);
        final uploadedUrl = await ref
            .read(profileRepositoryProvider)
            .uploadImage(bytes: upload.bytes, mimeType: upload.mimeType);
        if (uploadedUrl.isNotEmpty) {
          outfitImageUrl = uploadedUrl;
          _outfitImagePath = uploadedUrl;
          _pickedOutfitImage = null;
        }
      }

      await ref
          .read(eventRepositoryProvider)
          .upsertBooking(
            EventBooking(
              eventId: event.id,
              role: _role,
              dayIndex: _dayIndex,
              workId: _role == ParticipantRole.coser ? _selectedWork?.id : null,
              characterName: _characterController.text,
              outfitImagePath: outfitImageUrl,
              interactionTags: _interactionTags.toList(),
              availableTime: _availableTimeController.text.trim(),
              presenceStatus: _presenceStatus,
              message: _messageController.text,
            ),
          );
      await _refreshAfterAttendanceChanged(event.id);
      if (context.mounted) {
        setState(() {
          _allowClose = true;
          _submitting = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存出席失敗：${userFacingError(error)}')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  int _eventDayCount(CosEvent event) {
    return event.endDate.difference(event.startDate).inDays + 1;
  }

  Future<void> _removeAttendance(BuildContext context, CosEvent event) async {
    if (_submitting ||
        EventDayItem(
              event: event,
              dayIndex: _dayIndex,
            ).status(DateTime.now()) ==
            EventStatus.ended) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CosSafetyConfirmDialog(
        title: '取消這一天的預定？',
        message: '其他日期的預定會保留。',
        actionLabel: '取消預定',
        cancelLabel: '保留',
        icon: Icons.delete_outline,
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(eventRepositoryProvider)
          .removeBooking(event.id, dayIndex: _dayIndex);
      await _refreshAfterAttendanceChanged(event.id);
      if (context.mounted) {
        setState(() {
          _allowClose = true;
          _submitting = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消出席失敗：${userFacingError(error)}')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  ParticipantRole _roleFromString(String value) {
    return ParticipantRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => ParticipantRole.coser,
    );
  }

  Future<void> _refreshAfterAttendanceChanged(String eventId) async {
    ref.invalidate(eventParticipantsProvider(eventId));
    ref.invalidate(eventsProvider);
  }

  String _presenceStatusLabel(String value) {
    return _statusOptions
            .where((option) => option.$1 == value)
            .map((option) => option.$2)
            .firstOrNull ??
        value;
  }
}

class _BookingSection extends StatelessWidget {
  const _BookingSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CosReveal(
      offset: const Offset(0, 10),
      child: CosCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosSectionHeader(title: title, subtitle: subtitle, icon: icon),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RoleChoiceGrid extends StatelessWidget {
  const _RoleChoiceGrid({required this.selectedRole, required this.onChanged});

  final ParticipantRole selectedRole;
  final ValueChanged<ParticipantRole> onChanged;

  static const _roles = [
    (ParticipantRole.photographer, Icons.camera_alt_outlined, '攝影', '捕捉現場'),
    (
      ParticipantRole.coser,
      Icons.face_retouching_natural_outlined,
      'Coser',
      '角色亮相',
    ),
    (ParticipantRole.manager, Icons.support_agent_outlined, '馬內', '協助同行'),
    (ParticipantRole.self, Icons.person_pin_circle_outlined, '路人', '自由逛場'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in _roles)
              SizedBox(
                width: narrow
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 8) / 2,
                child: _RoleChoiceCard(
                  role: role.$1,
                  icon: role.$2,
                  title: role.$3,
                  subtitle: role.$4,
                  selected: selectedRole == role.$1,
                  onTap: () => onChanged(role.$1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.role,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final ParticipantRole role;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = participantRoleColorForScheme(role.name, scheme);
    return InkWell(
      borderRadius: BorderRadius.circular(CosUi.radiusMd),
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            CosIconBubble(icon: icon, color: accent, size: 36),
            const SizedBox(width: 10),
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
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedScale(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              scale: selected ? 1 : 0.86,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? accent : scheme.outline,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceStatusSelector extends StatelessWidget {
  const _PresenceStatusSelector({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '現場狀態',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              CosChoicePill(
                label: option.$2,
                selected: value == option.$1,
                icon: _presenceStatusIcon(option.$1),
                color: _presenceStatusColor(scheme, option.$1),
                onTap: () => onChanged(option.$1),
              ),
          ],
        ),
      ],
    );
  }

  IconData _presenceStatusIcon(String value) {
    return switch (value) {
      'open' => Icons.waving_hand_outlined,
      'moving' => Icons.directions_walk_outlined,
      'resting' => Icons.local_cafe_outlined,
      'quiet' => Icons.do_not_disturb_on_outlined,
      'left' => Icons.logout_outlined,
      _ => Icons.info_outline,
    };
  }

  Color _presenceStatusColor(ColorScheme scheme, String value) {
    return switch (value) {
      'open' => scheme.secondary,
      'moving' => scheme.primary,
      'resting' => scheme.tertiary,
      'quiet' => scheme.error,
      'left' => scheme.onSurfaceVariant,
      _ => scheme.primary,
    };
  }
}

class _BookingSubmitBar extends StatelessWidget {
  const _BookingSubmitBar({
    required this.editing,
    required this.submitting,
    required this.onSave,
    this.onRemove,
  });

  final bool editing;
  final bool submitting;
  final VoidCallback onSave;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [CosUi.softShadow(scheme.shadow)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (onRemove != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : onRemove,
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('取消出席'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: submitting ? null : onSave,
                icon: submitting
                    ? CosLoadingPulse(color: scheme.onPrimary, size: 20)
                    : Icon(
                        editing
                            ? Icons.save_outlined
                            : Icons.how_to_reg_outlined,
                      ),
                label: Text(
                  submitting
                      ? '同步中'
                      : editing
                      ? '儲存出席'
                      : '我會去',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitImagePicker extends StatelessWidget {
  const _OutfitImagePicker({required this.imagePath, required this.onPick});

  final String? imagePath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CosUi.radiusLg),
      onTap: onPick,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(CosUi.radiusLg),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CosUi.radiusMd),
                  child: imagePath == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.secondary.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: scheme.secondary,
                          ),
                        )
                      : Image(
                          image: pickedImageProvider(imagePath!)!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                ),
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      imagePath == null ? '當天長這樣' : '已選擇照片',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      imagePath == null ? '上傳一張方便同好認出你的照片' : imagePath!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
