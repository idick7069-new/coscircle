import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/circle.dart';
import '../../../core/models/event.dart';
import '../../../core/models/event_day_item.dart';
import '../../../core/models/meetup_point.dart';
import '../../../core/models/recognition_request.dart';
import '../../../core/models/shared_location.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/location_repository.dart';
import '../../../core/repositories/social_repository.dart';
import '../../../core/services/local_notification_service.dart';
import '../../../core/utils/event_day_display.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../shared/widgets/cos_ui.dart';
import 'widgets/current_event_overlays.dart';

final sharedLocationsProvider = FutureProvider.autoDispose
    .family<List<SharedLocation>, String>((ref, eventId) {
      return ref
          .watch(locationRepositoryProvider)
          .fetchSharedLocations(eventId);
    });

final meetupPointsProvider = FutureProvider.autoDispose
    .family<List<MeetupPoint>, String>((ref, eventId) {
      return ref.watch(locationRepositoryProvider).fetchMeetups(eventId);
    });

final recognitionRequestsProvider = FutureProvider.autoDispose
    .family<List<RecognitionRequest>, String>((ref, eventId) {
      return ref.watch(locationRepositoryProvider).fetchRecognitions(eventId);
    });

final currentEventCirclesProvider =
    FutureProvider.autoDispose<List<CircleGroup>>((ref) {
      return ref.watch(socialRepositoryProvider).fetchCircles();
    });

enum LocationFilter { all, followed, circle }

class CurrentEventPage extends ConsumerStatefulWidget {
  const CurrentEventPage({
    super.key,
    this.eventId,
    this.dayIndex = 1,
    this.onOpenEvents,
  });

  final String? eventId;
  final int dayIndex;
  final VoidCallback? onOpenEvents;

  @override
  ConsumerState<CurrentEventPage> createState() => _CurrentEventPageState();
}

class _CurrentEventPageState extends ConsumerState<CurrentEventPage> {
  static const _defaultPosition = LatLng(25.033964, 121.564468);
  LocationFilter _filter = LocationFilter.all;
  bool _isSharing = false;
  bool _myLocationEnabled = false;
  bool _hasConfirmedLocationSharing = false;
  LatLng _initialPosition = _defaultPosition;
  LatLng? _draftMeetupPosition;
  CurrentEventTarget? _selectedTarget;
  GoogleMapController? _mapController;
  Timer? _refreshTimer;
  Map<String, MeetupPoint> _knownMeetups = const {};
  bool _hasMeetupSnapshot = false;
  final Map<String, BitmapDescriptor> _markerIcons = {};
  final Set<String> _loadingMarkerIcons = {};

  @override
  void initState() {
    super.initState();
    _resolveInitialPosition();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCurrentEventData(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CurrentEventPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.dayIndex != widget.dayIndex) {
      _selectedTarget = null;
      _resetEventScopedState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final eventItems = events.whenOrNull(data: (items) => items);
    final switchTargets = _currentEventTargets(eventItems);
    final widgetTarget = widget.eventId == null
        ? null
        : CurrentEventTarget(
            eventId: widget.eventId!,
            dayIndex: widget.dayIndex,
          );
    final effectiveTarget = _selectedTarget ?? widgetTarget;
    final event = _currentEvent(eventItems, effectiveTarget);
    final eventId = event?.id;
    final dayIndex = event == null
        ? 1
        : _currentDayIndex(event, effectiveTarget);
    final isResolvingEvent = events.isLoading;
    final locations = event == null
        ? const AsyncData(<SharedLocation>[])
        : ref.watch(sharedLocationsProvider(event.id));
    final meetups = event == null
        ? const AsyncData(<MeetupPoint>[])
        : ref.watch(meetupPointsProvider(event.id));
    final recognitions = event == null
        ? const AsyncData(<RecognitionRequest>[])
        : ref.watch(recognitionRequestsProvider(event.id));
    final circles = ref.watch(currentEventCirclesProvider);
    final circleItems =
        circles.whenOrNull(data: (items) => items) ?? const <CircleGroup>[];

    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: locations.when(
          data: (items) {
            final dayLocations = items
                .where((item) => item.dayIndex == dayIndex)
                .toList();
            _warmMarkerIcons(dayLocations);
            final meetupItems =
                meetups.whenOrNull(data: (items) => items) ??
                const <MeetupPoint>[];
            _detectMeetupNotifications(meetupItems);
            final recognitionItems =
                recognitions.whenOrNull(data: (items) => items) ??
                const <RecognitionRequest>[];
            final noticeRecognition = _activeRecognition(recognitionItems);
            final activeMeetup = _activeMeetup(meetupItems);
            return Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _initialPosition,
                    zoom: 15,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    controller.moveCamera(
                      CameraUpdate.newLatLng(_initialPosition),
                    );
                  },
                  myLocationButtonEnabled: true,
                  myLocationEnabled: _myLocationEnabled,
                  onLongPress: (position) {
                    setState(() => _draftMeetupPosition = position);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已放置集合點草稿')));
                  },
                  markers: _markersFor(dayLocations, meetupItems, eventId),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: _EventMapHeader(
                    event: event,
                    dayIndex: dayIndex,
                    filter: _filter,
                    visibleCount: _filtered(dayLocations).length,
                    totalCount: dayLocations.length,
                    switchTargets: switchTargets,
                    selectedTarget: CurrentEventTarget(
                      eventId: event?.id ?? '',
                      dayIndex: dayIndex,
                    ),
                    onTargetChanged: _selectCurrentTarget,
                    onFilterChanged: (value) => setState(() => _filter = value),
                    onRefresh: eventId == null
                        ? null
                        : () =>
                              ref.invalidate(sharedLocationsProvider(eventId)),
                  ),
                ),
                if (activeMeetup != null && eventId != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: noticeRecognition == null ? 104 : 198,
                    child: MeetupNoticeCard(
                      meetup: activeMeetup,
                      onNavigate: () => _navigateTo(
                        activeMeetup.latitude,
                        activeMeetup.longitude,
                      ),
                      onEdit: activeMeetup.isMine && circleItems.isNotEmpty
                          ? () => _showMeetupSheet(
                              eventId,
                              circleItems,
                              meetup: activeMeetup,
                            )
                          : null,
                      onCancel: activeMeetup.isMine
                          ? () => _confirmDeleteMeetup(eventId, activeMeetup)
                          : null,
                    ),
                  ),
                if (noticeRecognition != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 104,
                    child: RecognitionNoticeCard(
                      request: noticeRecognition,
                      onCome: () => _respondRecognition(
                        noticeRecognition,
                        RecognitionStatus.come,
                      ),
                      onBusy: () => _respondRecognition(
                        noticeRecognition,
                        RecognitionStatus.busy,
                      ),
                    ),
                  ),
                if (isResolvingEvent)
                  const Center(child: CircularProgressIndicator())
                else if (event == null)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: 112,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '目前無當前活動',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '先到活動清單加入今天或即將參加的場次，再回來分享位置、集合與認親。',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: widget.onOpenEvents,
                              icon: const Icon(Icons.event_available),
                              label: const Text('去活動清單'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('位置載入失敗：$error'),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (eventId != null)
            FloatingActionButton.extended(
              heroTag: 'meetup',
              onPressed: circleItems.isEmpty
                  ? null
                  : () => _showMeetupSheet(eventId, circleItems),
              icon: const Icon(Icons.flag),
              label: const Text('集合'),
            ),
          if (eventId != null) const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'share-location',
            onPressed: eventId == null || _isSharing
                ? null
                : () => _shareLocation(eventId),
            icon: _isSharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_location),
            label: Text(_isSharing ? '定位中' : '分享位置'),
          ),
        ],
      ),
    );
  }

  String? _defaultCurrentEventId(List<CosEvent>? events) {
    if (events == null) return null;

    final now = DateTime.now();
    final joined = events
        .where(
          (event) => event.isJoined && event.status(now) == EventStatus.active,
        )
        .toList();
    if (joined.isEmpty) return null;
    joined.sort(
      (a, b) =>
          _distanceFromToday(a, now).compareTo(_distanceFromToday(b, now)),
    );
    return joined.first.id;
  }

  Future<void> _resolveInitialPosition() async {
    try {
      final position = await _currentPosition();
      if (!mounted) return;
      final target = LatLng(position.latitude, position.longitude);
      setState(() {
        _initialPosition = target;
        _myLocationEnabled = true;
      });
      await _mapController?.animateCamera(CameraUpdate.newLatLng(target));
    } catch (_) {
      // Keep the default Taipei position when location is unavailable.
    }
  }

  void _refreshCurrentEventData() {
    final events = ref.read(eventsProvider).whenOrNull(data: (items) => items);
    final event = _currentEvent(events, _effectiveTarget);
    if (event == null) return;
    ref.invalidate(sharedLocationsProvider(event.id));
    ref.invalidate(meetupPointsProvider(event.id));
    ref.invalidate(recognitionRequestsProvider(event.id));
  }

  void _selectCurrentTarget(CurrentEventTarget target) {
    setState(() {
      _selectedTarget = target;
      _resetEventScopedState();
    });
    ref
        .read(selectedCurrentEventTargetProvider.notifier)
        .select(target.eventId, dayIndex: target.dayIndex);
  }

  void _resetEventScopedState() {
    _draftMeetupPosition = null;
    _knownMeetups = const {};
    _hasMeetupSnapshot = false;
  }

  CurrentEventTarget? get _effectiveTarget {
    if (_selectedTarget != null) return _selectedTarget;
    final eventId = widget.eventId;
    if (eventId == null) return null;
    return CurrentEventTarget(eventId: eventId, dayIndex: widget.dayIndex);
  }

  void _detectMeetupNotifications(List<MeetupPoint> meetups) {
    final current = {for (final meetup in meetups) meetup.id: meetup};
    if (!_hasMeetupSnapshot) {
      _knownMeetups = current;
      _hasMeetupSnapshot = true;
      return;
    }

    for (final meetup in meetups) {
      final previous = _knownMeetups[meetup.id];
      if (previous == null || meetup.isMine) continue;
      if (_meetupChanged(previous, meetup)) {
        unawaited(
          LocalNotificationService.instance.showMeetupChanged(
            '${meetup.circleName} 更改了集合位置',
          ),
        );
      }
    }
    for (final previous in _knownMeetups.values) {
      if (previous.isMine || current.containsKey(previous.id)) continue;
      unawaited(
        LocalNotificationService.instance.showMeetupChanged(
          '${previous.circleName} 取消了集合',
        ),
      );
    }
    _knownMeetups = current;
  }

  bool _meetupChanged(MeetupPoint previous, MeetupPoint current) {
    return previous.latitude != current.latitude ||
        previous.longitude != current.longitude ||
        previous.description != current.description ||
        previous.meetAt != current.meetAt ||
        previous.circleId != current.circleId;
  }

  int _distanceFromToday(CosEvent event, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      event.startDate.year,
      event.startDate.month,
      event.startDate.day,
    );
    return start.difference(today).inDays.abs();
  }

  List<EventDayItem> _currentEventTargets(List<CosEvent>? events) {
    if (events == null) return const [];
    final now = DateTime.now();
    final targets = expandEventDays(events)
        .where(
          (item) => item.isJoined && item.status(now) == EventStatus.active,
        )
        .toList();
    targets.sort((a, b) => a.date.compareTo(b.date));
    return targets;
  }

  CosEvent? _currentEvent(List<CosEvent>? events, CurrentEventTarget? target) {
    if (events == null) return null;
    final now = DateTime.now();
    final id = target?.eventId ?? _defaultCurrentEventId(events);
    if (id == null) return null;
    final event = events.where((event) => event.id == id).firstOrNull;
    if (event == null || event.status(now) != EventStatus.active) return null;
    return event;
  }

  int _currentDayIndex(CosEvent event, CurrentEventTarget? target) {
    if (target != null) {
      return target.dayIndex.clamp(1, _eventDayCount(event));
    }
    final today = DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final start = DateTime(
      event.startDate.year,
      event.startDate.month,
      event.startDate.day,
    );
    return date.difference(start).inDays.clamp(0, _eventDayCount(event) - 1) +
        1;
  }

  int _eventDayCount(CosEvent event) {
    return event.endDate.difference(event.startDate).inDays + 1;
  }

  Set<Marker> _markersFor(
    List<SharedLocation> items,
    List<MeetupPoint> meetups,
    String? eventId,
  ) {
    final locationMarkers = _filtered(items).map((location) {
      final markerIconKey = _markerIconKey(location);
      return Marker(
        markerId: MarkerId('user-${location.userId}'),
        position: LatLng(location.latitude, location.longitude),
        icon:
            _markerIcons[markerIconKey] ??
            BitmapDescriptor.defaultMarkerWithHue(
              location.isMe
                  ? BitmapDescriptor.hueAzure
                  : BitmapDescriptor.hueRose,
            ),
        infoWindow: InfoWindow(
          title: location.isMe ? '我：${location.nickname}' : location.nickname,
          snippet:
              '${location.isCircleMember ? '小圈圈成員 · ' : ''}${_roleText(location)} · ${_elapsedText(location)}',
        ),
        onTap: () {
          if (eventId != null) {
            _showLocationSheet(location, eventId);
          }
        },
      );
    });
    final meetupMarkers = meetups.map((meetup) {
      return Marker(
        markerId: MarkerId('meetup-${meetup.id}'),
        position: LatLng(meetup.latitude, meetup.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: '集合：${meetup.circleName}',
          snippet:
              '${DateFormat('HH:mm').format(meetup.meetAt)} · ${meetup.description}',
        ),
        draggable: eventId != null && meetup.isMine,
        onDragEnd: eventId != null && meetup.isMine
            ? (position) => _updateMeetupPosition(eventId, meetup, position)
            : null,
        onTap: () => eventId == null
            ? _navigateTo(meetup.latitude, meetup.longitude)
            : _showMeetupDetailSheet(eventId, meetup),
      );
    });
    final draftMarker = _draftMeetupPosition == null
        ? const <Marker>[]
        : [
            Marker(
              markerId: const MarkerId('meetup-draft'),
              position: _draftMeetupPosition!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow,
              ),
              draggable: true,
              onDragEnd: (position) =>
                  setState(() => _draftMeetupPosition = position),
              infoWindow: const InfoWindow(title: '集合點草稿'),
            ),
          ];
    return {...locationMarkers, ...meetupMarkers, ...draftMarker};
  }

  List<SharedLocation> _filtered(List<SharedLocation> items) {
    return switch (_filter) {
      LocationFilter.followed =>
        items.where((item) => item.isFollowed || item.isMe).toList(),
      LocationFilter.circle =>
        items.where((item) => item.isCircleMember || item.isMe).toList(),
      LocationFilter.all => items,
    };
  }

  void _warmMarkerIcons(List<SharedLocation> items) {
    for (final location in items) {
      final markerIconKey = _markerIconKey(location);
      if (_markerIcons.containsKey(markerIconKey) ||
          _loadingMarkerIcons.contains(markerIconKey)) {
        continue;
      }
      _loadingMarkerIcons.add(markerIconKey);
      _buildAvatarMarker(location).then((icon) {
        if (!mounted) return;
        setState(() {
          _markerIcons[markerIconKey] = icon;
          _loadingMarkerIcons.remove(markerIconKey);
        });
      });
    }
  }

  String _markerIconKey(SharedLocation location) {
    return '${location.userId}:${location.avatarUrl}:${location.isMe}:${location.isFollowed}:${location.isCircleMember}:${location.role}';
  }

  Future<BitmapDescriptor> _buildAvatarMarker(SharedLocation location) async {
    final bytes = await _avatarMarkerBytes(location);
    return BitmapDescriptor.bytes(bytes, width: 54, height: 66);
  }

  Future<Uint8List> _avatarMarkerBytes(SharedLocation location) async {
    const width = 108.0;
    const height = 132.0;
    const avatarSize = 84.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    final center = Offset(width / 2, avatarSize / 2 + 8);
    final scheme = Theme.of(context).colorScheme;
    final color = location.isCircleMember
        ? scheme.tertiary
        : participantRoleColorForScheme(location.role, scheme);
    final placeholderColor = scheme.primaryContainer;
    final placeholderTextColor = scheme.onPrimaryContainer;

    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: avatarSize / 2 + 8))
      ..moveTo(width / 2 - 14, avatarSize + 18)
      ..lineTo(width / 2, height - 8)
      ..lineTo(width / 2 + 14, avatarSize + 18)
      ..close();
    paint.color = color;
    canvas.drawPath(path, paint);

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: 38)),
    );
    final image = await _loadAvatarImage(location.avatarUrl);
    if (image == null) {
      paint.color = placeholderColor;
      canvas.drawCircle(center, 38, paint);
      final painter = TextPainter(
        text: TextSpan(
          text: location.nickname.characters.firstOrNull ?? '?',
          style: TextStyle(
            color: placeholderTextColor,
            fontSize: 36,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    } else {
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromCircle(center: center, radius: 38);
      canvas.drawImageRect(image, src, dst, Paint()..isAntiAlias = true);
    }
    canvas.restore();

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.white;
    canvas.drawCircle(center, 40, paint);

    if (location.isCircleMember) {
      final badgeCenter = center + const Offset(28, -28);
      paint
        ..style = PaintingStyle.fill
        ..color = scheme.tertiaryContainer;
      canvas.drawCircle(badgeCenter, 16, paint);
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white;
      canvas.drawCircle(badgeCenter, 16, paint);
      final iconPainter = TextPainter(
        text: TextSpan(
          text: '◎',
          style: TextStyle(
            color: scheme.onTertiaryContainer,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        badgeCenter - Offset(iconPainter.width / 2, iconPainter.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final png = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await png.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<ui.Image?> _loadAvatarImage(String url) async {
    if (url.isEmpty) return null;
    try {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final data = await NetworkAssetBundle(Uri.parse(url)).load('');
        return _decodeImage(data.buffer.asUint8List());
      }

      final filePath = url.startsWith('file://')
          ? Uri.parse(url).toFilePath()
          : url;
      final file = File(filePath);
      if (!await file.exists()) return null;
      return _decodeImage(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  MeetupPoint? _activeMeetup(List<MeetupPoint> meetups) {
    if (meetups.isEmpty) return null;
    final now = DateTime.now();
    final upcoming = meetups
        .where(
          (meetup) =>
              meetup.meetAt.isAfter(now.subtract(const Duration(minutes: 10))),
        )
        .toList();
    if (upcoming.isEmpty) return meetups.first;
    upcoming.sort((a, b) => a.meetAt.compareTo(b.meetAt));
    return upcoming.first;
  }

  RecognitionRequest? _activeRecognition(List<RecognitionRequest> requests) {
    final pendingForMe = requests
        .where(
          (request) =>
              request.isTarget && request.status == RecognitionStatus.pending,
        )
        .toList();
    if (pendingForMe.isNotEmpty) return pendingForMe.first;
    final answeredForMe = requests
        .where(
          (request) =>
              request.isRequester &&
              request.status != RecognitionStatus.pending,
        )
        .toList();
    return answeredForMe.firstOrNull;
  }

  Future<void> _navigateTo(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=walking',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(latitude, longitude), 17),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已將地圖移到目標位置')));
    }
  }

  Future<void> _respondRecognition(
    RecognitionRequest request,
    RecognitionStatus status,
  ) async {
    try {
      await ref
          .read(locationRepositoryProvider)
          .respondRecognition(requestId: request.id, status: status);
      ref.invalidate(recognitionRequestsProvider(request.eventId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已回覆：${status == RecognitionStatus.come ? '快來' : '當前不方便'}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('回覆失敗：$error')));
    }
  }

  Future<void> _requestRecognition(
    String eventId,
    SharedLocation location,
  ) async {
    try {
      await ref
          .read(locationRepositoryProvider)
          .requestRecognition(eventId: eventId, targetUserId: location.userId);
      ref.invalidate(recognitionRequestsProvider(eventId));
      if (!mounted) return;
      Navigator.of(context).pop();
      await _navigateTo(location.latitude, location.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已通知 ${location.nickname} 你要過去認親')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('認親通知失敗：$error')));
    }
  }

  Future<void> _updateMeetupPosition(
    String eventId,
    MeetupPoint meetup,
    LatLng position,
  ) async {
    try {
      await ref
          .read(locationRepositoryProvider)
          .updateMeetup(
            eventId: eventId,
            meetupId: meetup.id,
            circleId: meetup.circleId,
            latitude: position.latitude,
            longitude: position.longitude,
            description: meetup.description,
            meetAt: meetup.meetAt,
          );
      ref.invalidate(meetupPointsProvider(eventId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已更新集合位置並通知成員')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新集合位置失敗：$error')));
    }
  }

  void _showMeetupDetailSheet(String eventId, MeetupPoint meetup) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '集合：${meetup.circleName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('時間：${DateFormat('HH:mm').format(meetup.meetAt)}'),
                const SizedBox(height: 8),
                Text(
                  meetup.description.isEmpty ? '集合點已設定' : meetup.description,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _navigateTo(meetup.latitude, meetup.longitude),
                        icon: const Icon(Icons.navigation),
                        label: const Text('導航'),
                      ),
                    ),
                    if (meetup.isMine) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            final circles =
                                ref
                                    .read(currentEventCirclesProvider)
                                    .whenOrNull(data: (items) => items) ??
                                const <CircleGroup>[];
                            if (circles.isEmpty) return;
                            _showMeetupSheet(eventId, circles, meetup: meetup);
                          },
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: const Text('編輯'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (meetup.isMine) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _confirmDeleteMeetup(eventId, meetup);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('取消集合'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMeetup(String eventId, MeetupPoint meetup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消集合'),
        content: Text('確定要取消「${meetup.circleName}」的集合通知？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消集合'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(locationRepositoryProvider)
          .deleteMeetup(eventId: eventId, meetupId: meetup.id);
      ref.invalidate(meetupPointsProvider(eventId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已取消集合並通知成員')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('取消集合失敗：$error')));
    }
  }

  Future<void> _showMeetupSheet(
    String eventId,
    List<CircleGroup> circles, {
    MeetupPoint? meetup,
  }) async {
    final descriptionController = TextEditingController(
      text: meetup?.description ?? '',
    );
    final initialCircleId = meetup?.circleId;
    var selectedCircleId =
        initialCircleId != null &&
            circles.any((circle) => circle.id == initialCircleId)
        ? initialCircleId
        : circles.first.id;
    var selectedPosition = meetup == null
        ? _draftMeetupPosition ?? _initialPosition
        : LatLng(meetup.latitude, meetup.longitude);
    var meetAt =
        meetup?.meetAt ?? DateTime.now().add(const Duration(minutes: 30));
    var isSaving = false;
    GoogleMapController? pickerMapController;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> useCurrentLocation() async {
              try {
                final position = await _currentPosition();
                setSheetState(() {
                  selectedPosition = LatLng(
                    position.latitude,
                    position.longitude,
                  );
                });
                await pickerMapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(selectedPosition, 17),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('定位失敗：$error')));
              }
            }

            Future<void> saveMeetup() async {
              setSheetState(() => isSaving = true);
              try {
                if (meetup == null) {
                  await ref
                      .read(locationRepositoryProvider)
                      .createMeetup(
                        eventId: eventId,
                        circleId: selectedCircleId,
                        latitude: selectedPosition.latitude,
                        longitude: selectedPosition.longitude,
                        description: descriptionController.text.trim(),
                        meetAt: meetAt,
                      );
                } else {
                  await ref
                      .read(locationRepositoryProvider)
                      .updateMeetup(
                        eventId: eventId,
                        meetupId: meetup.id,
                        circleId: selectedCircleId,
                        latitude: selectedPosition.latitude,
                        longitude: selectedPosition.longitude,
                        description: descriptionController.text.trim(),
                        meetAt: meetAt,
                      );
                }
                ref.invalidate(meetupPointsProvider(eventId));
                if (mounted) {
                  setState(() => _draftMeetupPosition = null);
                }
                if (!context.mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(meetup == null ? '已發出集合通知' : '已更新集合通知'),
                  ),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('建立集合失敗：$error')));
              } finally {
                if (context.mounted) {
                  setSheetState(() => isSaving = false);
                }
              }
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  children: [
                    Text(
                      meetup == null ? '設定集合點' : '編輯集合點',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCircleId,
                      decoration: const InputDecoration(labelText: '呼叫小圈圈'),
                      items: [
                        for (final circle in circles)
                          DropdownMenuItem(
                            value: circle.id,
                            child: Text(circle.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selectedCircleId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: '集合點描述',
                        hintText: '例如：大門口左邊樹下',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 220,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: selectedPosition,
                            zoom: 17,
                          ),
                          onMapCreated: (controller) {
                            pickerMapController = controller;
                          },
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          gestureRecognizers: {
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          },
                          onTap: (position) {
                            setSheetState(() {
                              selectedPosition = position;
                            });
                          },
                          markers: {
                            Marker(
                              markerId: const MarkerId('meetup-picker'),
                              position: selectedPosition,
                              draggable: true,
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueYellow,
                              ),
                              onDragEnd: (position) {
                                setSheetState(() {
                                  selectedPosition = position;
                                });
                              },
                            ),
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '拖動圖釘或點地圖即可變更集合座標。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('集合時間'),
                      subtitle: Text(DateFormat('HH:mm').format(meetAt)),
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(meetAt),
                        );
                        if (picked == null) return;
                        final base = meetAt;
                        setSheetState(() {
                          meetAt = DateTime(
                            base.year,
                            base.month,
                            base.day,
                            picked.hour,
                            picked.minute,
                          );
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place),
                      title: const Text('集合座標'),
                      subtitle: Text(
                        '${selectedPosition.latitude.toStringAsFixed(5)}, ${selectedPosition.longitude.toStringAsFixed(5)}',
                      ),
                      trailing: TextButton(
                        onPressed: useCurrentLocation,
                        child: const Text('用目前位置'),
                      ),
                    ),
                    if (_draftMeetupPosition != null)
                      Text(
                        '已使用地圖上長按放置的圖釘；可以拖動黃色圖釘調整，也可以改用目前位置。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isSaving ? null : saveMeetup,
                        icon: isSaving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.notifications_active),
                        label: Text(
                          isSaving
                              ? '儲存中'
                              : meetup == null
                              ? '通知小圈圈集合'
                              : '更新集合通知',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareLocation(String eventId) async {
    final confirmed = await _confirmLocationSharing();
    if (confirmed != true) return;
    setState(() => _isSharing = true);
    try {
      final position = await _currentPosition();
      await ref
          .read(locationRepositoryProvider)
          .shareLocation(
            eventId: eventId,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      ref.invalidate(sharedLocationsProvider(eventId));
      if (!mounted) return;
      setState(() => _myLocationEnabled = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已分享最新位置')));
    } catch (error) {
      if (!mounted) return;
      final message = userFacingError(error);
      final permanentlyDenied = '$error'.contains('永久拒絕');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('分享位置失敗：$message'),
          action: permanentlyDenied
              ? SnackBarAction(
                  label: '開啟設定',
                  onPressed: Geolocator.openAppSettings,
                )
              : null,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  Future<bool?> _confirmLocationSharing() {
    if (_hasConfirmedLocationSharing) return Future.value(true);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('分享現場位置'),
        content: const Text(
          '你的座標只會提供給同活動中與你有關係的人查看，例如你自己、已關注對象或同小圈圈成員。位置只會在你主動按下分享時更新。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('先不要'),
          ),
          FilledButton(
            onPressed: () {
              _hasConfirmedLocationSharing = true;
              Navigator.pop(context, true);
            },
            child: const Text('分享位置'),
          ),
        ],
      ),
    );
  }

  Future<Position> _currentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('請先開啟手機定位服務');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('需要允許定位權限才能分享位置');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('定位權限已被永久拒絕，請到系統設定開啟 CosCircle 的定位權限');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }

  void _showLocationSheet(SharedLocation location, String eventId) {
    final now = DateTime.now();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: participantRoleColorForScheme(
                          location.role,
                          Theme.of(context).colorScheme,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundImage: pickedImageProvider(
                          location.avatarUrl,
                        ),
                        child: location.avatarUrl.isEmpty
                            ? Text(
                                location.nickname.characters.firstOrNull ?? '?',
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            location.nickname,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${location.isCircleMember ? '小圈圈成員 · ' : ''}${_roleText(location)} · ${_statusText(location.presenceStatus)} · ${_elapsedText(location, now: now)}',
                          ),
                        ],
                      ),
                    ),
                    if (location.isCircleMember)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.tertiaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.groups,
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                      ),
                  ],
                ),
                if (location.availableTime.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('出沒時間：${location.availableTime}'),
                ],
                if (location.interactionTags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in location.interactionTags)
                        Chip(label: Text(tag)),
                    ],
                  ),
                ],
                if (location.characterName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('角色：${location.characterName}'),
                ],
                if (location.outfitImageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(
                      image: pickedImageProvider(location.outfitImageUrl)!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Text('當天出的角：${location.outfitImageUrl}'),
                    ),
                  ),
                ],
                if (!location.isMe) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _navigateTo(
                            location.latitude,
                            location.longitude,
                          ),
                          icon: const Icon(Icons.navigation),
                          label: const Text('導航'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              _requestRecognition(eventId, location),
                          icon: const Icon(Icons.waving_hand),
                          label: const Text('我要認親'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _elapsedText(SharedLocation location, {DateTime? now}) {
    final seconds = (now ?? DateTime.now())
        .difference(location.sharedAt)
        .inSeconds
        .clamp(0, 999999)
        .toInt();
    if (seconds < 60) return '$seconds 秒前';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分鐘前';
    final hours = minutes ~/ 60;
    return '$hours 小時前';
  }

  String _roleText(SharedLocation location) {
    final label = participantRoleLabel(location.role);
    if (location.role != 'coser') {
      return label;
    }
    final details = [
      if (location.workName.isNotEmpty) location.workName,
      if (location.characterName.isNotEmpty) location.characterName,
    ];
    if (details.isEmpty) return label;
    return '$label / ${details.join(' / ')}';
  }

  String _statusText(String status) {
    return switch (status) {
      'moving' => '移動中',
      'resting' => '休息中',
      'quiet' => '暫不互動',
      'left' => '已離場',
      _ => '可來找我',
    };
  }
}

class _EventMapHeader extends StatelessWidget {
  const _EventMapHeader({
    required this.event,
    required this.dayIndex,
    required this.filter,
    required this.visibleCount,
    required this.totalCount,
    required this.switchTargets,
    required this.selectedTarget,
    required this.onTargetChanged,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final CosEvent? event;
  final int dayIndex;
  final LocationFilter filter;
  final int visibleCount;
  final int totalCount;
  final List<EventDayItem> switchTargets;
  final CurrentEventTarget selectedTarget;
  final ValueChanged<CurrentEventTarget> onTargetChanged;
  final ValueChanged<LocationFilter> onFilterChanged;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CosIconBubble(
            icon: Icons.location_on_outlined,
            color: scheme.primary,
            size: 40,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event == null
                      ? '目前無當前活動'
                      : currentEventTitle(event!, dayIndex),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  event == null
                      ? '從活動頁加入場次後會顯示現場資訊'
                      : '$visibleCount / $totalCount 位同好可見',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (switchTargets.length > 1)
            PopupMenuButton<CurrentEventTarget>(
              tooltip: '切換當前活動',
              icon: const Icon(Icons.swap_horiz),
              onSelected: onTargetChanged,
              itemBuilder: (context) => [
                for (final item in switchTargets)
                  PopupMenuItem(
                    value: CurrentEventTarget(
                      eventId: item.event.id,
                      dayIndex: item.dayIndex,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _sameTarget(item, selectedTarget)
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${item.title} · ${DateFormat('MM/dd E', 'zh_TW').format(item.date)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (onRefresh != null)
            IconButton(
              tooltip: '重新整理',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          PopupMenuButton<LocationFilter>(
            tooltip: '篩選',
            initialValue: filter,
            onSelected: onFilterChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: LocationFilter.all, child: Text('全部')),
              PopupMenuItem(
                value: LocationFilter.followed,
                child: Text('僅顯示關注'),
              ),
              PopupMenuItem(
                value: LocationFilter.circle,
                child: Text('僅顯示小圈圈'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _sameTarget(EventDayItem item, CurrentEventTarget target) {
    return item.event.id == target.eventId && item.dayIndex == target.dayIndex;
  }
}
