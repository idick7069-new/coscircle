import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/models/feed_post.dart';
import '../../../core/models/work.dart';
import '../../../core/models/circle.dart';
import '../../../core/models/event.dart';
import '../../../core/models/participant.dart';
import '../../../core/repositories/feed_repository.dart';
import '../../../core/repositories/event_repository.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../core/utils/upload_image_data.dart';
import '../../works/presentation/work_selector.dart';

class FeedComposerPage extends ConsumerStatefulWidget {
  const FeedComposerPage({
    super.key,
    this.booking = false,
    this.initialEventId,
    this.existing,
  });
  final bool booking;
  final String? initialEventId;
  final FeedPost? existing;
  @override
  ConsumerState<FeedComposerPage> createState() => _FeedComposerPageState();
}

class _FeedComposerPageState extends ConsumerState<FeedComposerPage> {
  final _text = TextEditingController();
  final List<String> _images = [];
  final List<XFile> _picked = [];
  List<CircleGroup> _circles = [];
  List<CosEvent> _events = [];
  final List<({CosEvent event, EventParticipant participant})> _bookings = [];
  String _visibility = 'public';
  String? _circleId, _eventId, _bookingKey;
  WorkTag? _work;
  int _shareGeneration = 0;
  bool _loadingShare = false;
  Object? _shareError;
  bool _loading = true,
      _saving = false,
      _comments = true,
      _restrictedBooking = false,
      _allowClose = false;
  Object? _error;
  bool get _isBooking => widget.existing?.isBooking ?? widget.booking;
  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    if (old != null) {
      _text.text = old.body;
      _images.addAll(old.images);
      _visibility = old.visibility;
      _circleId = old.data['circleId']?.toString();
      _eventId = old.data['eventId']?.toString();
      _comments = old.commentsEnabled;
      if (old.text('workId').isNotEmpty) {
        _work = WorkTag(id: old.text('workId'), name: old.text('workName'));
      }
    } else {
      _eventId = widget.initialEventId;
    }
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final circles = await ref.read(socialRepositoryProvider).fetchCircles();
      final events = await ref.read(eventRepositoryProvider).fetchEvents();
      final me = await ref.read(profileRepositoryProvider).currentProfile();
      final bookings = _isBooking
          ? await ref.read(eventRepositoryProvider).fetchMyBookings()
          : <String, List<EventParticipant>>{};
      if (!mounted) return;
      _bookings.clear();
      for (final e in events) {
        for (final b in bookings[e.id] ?? <EventParticipant>[]) {
          if (widget.initialEventId == null || e.id == widget.initialEventId) {
            _bookings.add((event: e, participant: b));
          }
        }
      }
      setState(() {
        _circles = circles;
        _events = events;
        _restrictedBooking = _isBooking && me?.bookingVisibility == 'circle';
        if (_restrictedBooking) _visibility = 'circle';
        if (_circleId != null && !circles.any((c) => c.id == _circleId)) {
          _circleId = null;
        }
        if (_eventId != null && !events.any((e) => e.id == _eventId)) {
          _eventId = null;
        }
      });
      if (widget.existing == null && _isBooking && _bookings.isNotEmpty) {
        _selectBooking(
          '${_bookings.first.event.id}:${_bookings.first.participant.dayIndex}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectBooking(String key) async {
    final generation = ++_shareGeneration;
    final changed = _bookingKey != key;
    setState(() {
      _bookingKey = key;
      _loadingShare = true;
      _shareError = null;
      if (changed) {
        _text.clear();
        _images.clear();
        _picked.clear();
        _visibility = _restrictedBooking ? 'circle' : 'public';
        _circleId = null;
        _comments = true;
      }
    });
    final b = _bookings
        .where((b) => '${b.event.id}:${b.participant.dayIndex}' == key)
        .firstOrNull;
    if (b == null) {
      setState(() {
        _loadingShare = false;
        _shareError = StateError('找不到這一天的預定');
      });
      return;
    }
    try {
      final old = await ref
          .read(feedRepositoryProvider)
          .bookingShare(b.event.id, b.participant.dayIndex);
      if (!mounted || _bookingKey != key || generation != _shareGeneration) {
        return;
      }
      if (old != null) {
        final visibility = old['visibility']?.toString();
        if (!const ['public', 'friends', 'circle'].contains(visibility)) {
          throw const FormatException('分享設定格式不符，請重新載入');
        }
        setState(() {
          _text.text = old['body']?.toString() ?? '';
          _visibility = _restrictedBooking ? 'circle' : visibility!;
          final circleId = old['circleId']?.toString();
          _circleId = _circles.any((c) => c.id == circleId) ? circleId : null;
          _images
            ..clear()
            ..addAll((old['images'] as List? ?? []).map((u) => u.toString()));
          _comments =
              old['commentsEnabled'] != false && old['commentsEnabled'] != 0;
        });
      }
    } catch (e) {
      if (mounted && _bookingKey == key && generation == _shareGeneration) {
        setState(() => _shareError = e);
      }
    } finally {
      if (mounted && _bookingKey == key && generation == _shareGeneration) {
        setState(() => _loadingShare = false);
      }
    }
  }

  bool _picking = false;
  Future<void> _photos() async {
    if (_picking || _saving || _loadingShare) return;
    final key = _bookingKey;
    final session = ref.read(feedSessionProvider);
    setState(() => _picking = true);
    try {
      final files = await ImagePicker().pickMultiImage(
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (!mounted ||
          key != _bookingKey ||
          session != ref.read(feedSessionProvider)) {
        return;
      }
      setState(
        () => _picked.addAll(files.take(4 - _images.length - _picked.length)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_picking ||
        _saving ||
        _loading ||
        _loadingShare ||
        _shareError != null) {
      return;
    }
    if (_visibility == 'circle' && _circleId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請選擇一個小圈圈')));
      return;
    }
    if (!_isBooking &&
        _text.text.trim().isEmpty &&
        _images.isEmpty &&
        _picked.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('寫一些內容或加入照片吧')));
      return;
    }
    final booking = _bookings
        .where((b) => '${b.event.id}:${b.participant.dayIndex}' == _bookingKey)
        .firstOrNull;
    if (_isBooking && widget.existing == null && booking == null) return;
    setState(() => _saving = true);
    try {
      final session = ref.read(feedSessionProvider);
      while (_picked.isNotEmpty) {
        final file = _picked.first;
        final upload = await readUploadImage(file);
        final url = await ref
            .read(profileRepositoryProvider)
            .uploadImage(bytes: upload.bytes, mimeType: upload.mimeType);
        if (!mounted || ref.read(feedSessionProvider) != session) {
          throw StateError('登入已變更，請重新發佈');
        }
        _images.add(url);
        _picked.removeAt(0);
      }
      final old = widget.existing;
      await ref.read(feedRepositoryProvider).save({
        'kind': _isBooking ? 'booking' : 'general',
        'body': _text.text.trim(),
        'visibility': _visibility,
        'circleId': _visibility == 'circle' ? _circleId : null,
        'eventId': _isBooking
            ? (old?.data['eventId'] ?? booking?.event.id)
            : _eventId,
        'dayIndex': _isBooking
            ? (old?.data['dayIndex'] ?? booking?.participant.dayIndex)
            : null,
        'workId': _isBooking ? null : _work?.id,
        'images': _images,
        'commentsEnabled': _comments,
      }, id: old?.id);
      if (mounted) {
        setState(() => _allowClose = true);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    if (_saving) return;
    final changed =
        _text.text != (widget.existing?.body ?? '') ||
        _picked.isNotEmpty ||
        _images.length != (widget.existing?.images.length ?? 0) ||
        _visibility != (widget.existing?.visibility ?? 'public') ||
        _bookingKey != null;
    if (changed) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('放棄這次編輯？'),
          content: const Text('尚未發佈的內容不會儲存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('繼續編輯'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放棄'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => _allowClose = true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowClose,
      onPopInvokedWithResult: (popped, result) {
        if (!popped) _discard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existing != null
                ? '編輯貼文'
                : _isBooking
                ? '分享場次預定'
                : '發佈貼文',
          ),
          leading: IconButton(
            tooltip: '返回',
            onPressed: _saving ? null : _discard,
            icon: const BackButtonIcon(),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: FilledButton.icon(
              onPressed:
                  _picking ||
                      _saving ||
                      _loading ||
                      _loadingShare ||
                      _shareError != null ||
                      _error != null ||
                      (_isBooking &&
                          widget.existing == null &&
                          _bookings.isEmpty)
                  ? null
                  : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish),
              label: Text(
                _saving
                    ? '發佈中…'
                    : widget.existing == null
                    ? '發佈'
                    : '儲存變更',
              ),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: TextButton(
                  onPressed: _load,
                  child: Text('重新載入：${userFacingError(_error!)}'),
                ),
              )
            : AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_isBooking) ...[
                      if (widget.existing != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event),
                          title: Text(widget.existing!.text('eventName')),
                          subtitle: Text(
                            '${widget.existing!.text('eventDate')} · D${widget.existing!.text('dayIndex')}',
                          ),
                        )
                      else if (_bookings.isEmpty)
                        Column(
                          children: [
                            const Text('先發佈一筆場次預定，再分享給同好。'),
                            TextButton(
                              onPressed: () => context.go('/?tab=events'),
                              child: const Text('前往活動頁'),
                            ),
                          ],
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: _bookingKey,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '選擇要分享的預定',
                          ),
                          items: [
                            for (final b in _bookings)
                              DropdownMenuItem(
                                value:
                                    '${b.event.id}:${b.participant.dayIndex}',
                                child: Text(
                                  '${b.event.name} · D${b.participant.dayIndex}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) _selectBooking(v);
                          },
                        ),
                      if (_loadingShare) const LinearProgressIndicator(),
                      if (_shareError != null)
                        Column(
                          children: [
                            const Text('無法確認這一天的分享設定，請重試。'),
                            TextButton(
                              onPressed: _loadingShare || _bookingKey == null
                                  ? null
                                  : () => _selectBooking(_bookingKey!),
                              child: const Text('重新載入分享設定'),
                            ),
                          ],
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('預定內容會同步更新；取消出席後，這篇貼文仍會保留討論並標示已取消。'),
                      ),
                    ],
                    TextField(
                      controller: _text,
                      maxLength: 2000,
                      minLines: 4,
                      maxLines: 10,
                      decoration: InputDecoration(
                        labelText: _isBooking ? '跟同好說幾句（選填）' : '想分享什麼？',
                        hintText: _isBooking
                            ? '這次會出什麼角色？想找誰一起拍照？'
                            : '出角準備、場後心得，或找同坑夥伴聊聊…',
                      ),
                    ),
                    if (!_isBooking) ...[
                      WorkSingleSelector(
                        label: '標記作品（選填）',
                        selected: _work,
                        onChanged: (w) => setState(() => _work = w),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _eventId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '標記活動（選填）',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('不標記活動'),
                          ),
                          for (final e in _events)
                            DropdownMenuItem(
                              value: e.id,
                              child: Text(
                                e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _eventId = v == '' ? null : v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final url in _images)
                          Stack(
                            children: [
                              Image(
                                image: pickedImageProvider(url)!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, st) => const SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  tooltip: '移除照片',
                                  onPressed: () =>
                                      setState(() => _images.remove(url)),
                                  icon: const Icon(Icons.cancel),
                                ),
                              ),
                            ],
                          ),
                        for (final f in _picked)
                          Stack(
                            children: [
                              Image(
                                image: pickedImageProvider(f.path)!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, st) => const SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: Icon(Icons.image),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  tooltip: '移除照片',
                                  onPressed: () =>
                                      setState(() => _picked.remove(f)),
                                  icon: const Icon(Icons.cancel),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (_images.length + _picked.length < 4)
                      TextButton.icon(
                        onPressed: _picking || _loadingShare ? null : _photos,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          '加入照片（${_images.length + _picked.length}/4）',
                        ),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey('feed-audience-$_visibility'),
                      initialValue: _visibility,
                      decoration: const InputDecoration(labelText: '誰可以看到'),
                      items: [
                        if (!_restrictedBooking) ...[
                          const DropdownMenuItem(
                            value: 'public',
                            child: Text('公開'),
                          ),
                          const DropdownMenuItem(
                            value: 'friends',
                            child: Text('戳友限定'),
                          ),
                        ],
                        const DropdownMenuItem(
                          value: 'circle',
                          child: Text('指定小圈圈'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _visibility = v);
                      },
                    ),
                    if (_restrictedBooking)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('你的預定限定小圈圈可見，分享到動態也會維持限制。'),
                      ),
                    if (_visibility == 'circle')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _circles.isEmpty
                            ? const Text('請先加入或建立小圈圈。')
                            : DropdownButtonFormField<String>(
                                key: ValueKey('feed-circle-$_circleId'),
                                initialValue: _circleId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '選擇小圈圈',
                                ),
                                items: [
                                  for (final c in _circles)
                                    DropdownMenuItem(
                                      value: c.id,
                                      child: Text(
                                        c.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _circleId = v),
                              ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('開放留言'),
                      value: _comments,
                      onChanged: (v) => setState(() => _comments = v),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
