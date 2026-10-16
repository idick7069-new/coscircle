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
import '../../../core/repositories/profile_repository.dart';
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

enum LocationFilter { all, followed, circle, friends }

class _LocationShareSettings {
  const _LocationShareSettings({
    required this.visibility,
    required this.expiresInMinutes,
  });

  final String visibility;
  final int expiresInMinutes;
}

class CurrentEventPage extends ConsumerStatefulWidget {
  const CurrentEventPage({
    super.key,
    this.eventId,
    this.dayIndex = 1,
    this.onOpenEvents,
    this.isVisible = true,
  });

  final String? eventId;
  final int dayIndex;
  final VoidCallback? onOpenEvents;
  final bool isVisible;

  @override
  ConsumerState<CurrentEventPage> createState() => _CurrentEventPageState();
}

class _CurrentEventPageState extends ConsumerState<CurrentEventPage>
    with WidgetsBindingObserver {
  static const _defaultPosition = LatLng(25.033964, 121.564468);
  LocationFilter _filter = LocationFilter.all;
  bool _isSharing = false;
  bool _myLocationEnabled = false;
  bool _hasConfirmedLocationSharing = false;
  final LatLng _initialPosition = _defaultPosition;
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
    WidgetsBinding.instance.addObserver(this);
    _updateRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CurrentEventPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) _updateRefreshTimer();
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.dayIndex != widget.dayIndex) {
      _selectedTarget = null;
      _resetEventScopedState();
    }
  }

  void _updateRefreshTimer() {
    _refreshTimer?.cancel();
    if (!widget.isVisible ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCurrentEventData(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateRefreshTimer();
      if (widget.isVisible) _refreshCurrentEventData();
    } else {
      _refreshTimer?.cancel();
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
            final mySharedLocation = dayLocations
                .where((item) => item.isMe)
                .firstOrNull;
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
                if (noticeRecognition != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 86,
                    child: RecognitionNoticeCard(
                      request: noticeRecognition,
                      onCome: () => _respondRecognition(
                        noticeRecognition,
                        RecognitionStatus.accepted,
                      ),
                      onBusy: () => _respondRecognition(
                        noticeRecognition,
                        RecognitionStatus.declined,
                      ),
                    ),
                  )
                else if (activeMeetup != null && eventId != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 86,
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
                if (isResolvingEvent)
                  const Positioned(
                    left: 24,
                    right: 24,
                    top: 166,
                    child: _CurrentEventLoadingCard(),
                  )
                else if (event == null)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: 166,
                    child: _CurrentEventEmptyCard(
                      onOpenEvents: widget.onOpenEvents,
                    ),
                  ),
                if (eventId != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _MapActionDock(
                      circleItems: circleItems,
                      visibleCount: _filtered(dayLocations).length,
                      totalCount: dayLocations.length,
                      activeMeetup: activeMeetup,
                      isSharing: _isSharing,
                      mySharedLocation: mySharedLocation,
                      onMeetup: circleItems.isEmpty
                          ? null
                          : () => _showMeetupSheet(eventId, circleItems),
                      onShareLocation: _isSharing
                          ? null
                          : () => _shareLocation(eventId, dayIndex),
                      onUpdateLocation: mySharedLocation == null || _isSharing
                          ? null
                          : () => _updateSharedLocation(eventId, dayIndex),
                      onStopSharing: mySharedLocation == null || _isSharing
                          ? null
                          : () => _stopSharingLocation(eventId),
                      onStealthMode: _isSharing
                          ? null
                          : () => _enableStealthMode(eventId),
                    ),
                  ),
              ],
            );
          },
          error: (error, stack) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _CurrentEventErrorCard(message: '位置載入失敗：$error'),
              ),
            ),
          ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: _CurrentEventLoadingCard(),
            ),
          ),
        ),
      ),
    );
  }

  String? _defaultCurrentEventId(List<CosEvent>? events) {
    if (events == null) return null;

    return _currentEventTargets(events).firstOrNull?.event.id;
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
    final day = _currentDayIndex(event, target);
    if (!event.joinedDayIndexes.contains(day) ||
        EventDayItem(event: event, dayIndex: day).status(now) !=
            EventStatus.active) {
      return null;
    }
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
      LocationFilter.friends =>
        items.where((item) => item.isFriend || item.isMe).toList(),
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
            '已回覆：${status == RecognitionStatus.accepted ? '快來' : '當前不方便'}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = userFacingError(error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('回覆失敗：$message')));
    }
  }

  Future<void> _requestRecognition(
    String eventId,
    SharedLocation location,
  ) async {
    try {
      await ref
          .read(locationRepositoryProvider)
          .requestRecognition(
            eventId: eventId,
            dayIndex: location.dayIndex,
            targetUserId: location.userId,
          );
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
      final message = userFacingError(error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('認親通知失敗：$message')));
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
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CosGradientPanel(
              icon: Icons.flag_circle_outlined,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CosSectionHeader(
                    title: '${meetup.circleName} 集合',
                    subtitle: meetup.description.isEmpty
                        ? '集合點已設定'
                        : meetup.description,
                    icon: Icons.flag_circle_outlined,
                    trailing: CosBadge(
                      label: DateFormat('HH:mm').format(meetup.meetAt),
                      icon: Icons.schedule,
                      highlighted: true,
                      color: scheme.tertiary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: CosMetricTile(
                          icon: Icons.place_outlined,
                          label: '集合座標',
                          value:
                              '${meetup.latitude.toStringAsFixed(4)}, ${meetup.longitude.toStringAsFixed(4)}',
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CosMetricTile(
                          icon: Icons.groups_2_outlined,
                          label: '通知對象',
                          value: meetup.circleName,
                          color: scheme.secondary,
                        ),
                      ),
                    ],
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
                              _showMeetupSheet(
                                eventId,
                                circles,
                                meetup: meetup,
                              );
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
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMeetup(String eventId, MeetupPoint meetup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RadarConfirmDialog(
        icon: Icons.delete_outline,
        title: '取消集合',
        message: '確定要取消「${meetup.circleName}」的集合通知？小圈圈成員會看不到這個集合點。',
        cancelLabel: '保留',
        confirmLabel: '取消集合',
        confirmIcon: Icons.delete_outline,
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
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final scheme = Theme.of(context).colorScheme;
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
                    CosReveal(
                      child: CosGradientPanel(
                        icon: Icons.flag_circle_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CosSectionHeader(
                              title: meetup == null ? '設定集合點' : '編輯集合點',
                              subtitle: '把小圈圈要集合的位置、時間和提示一次講清楚',
                              icon: Icons.flag_circle_outlined,
                              trailing: CosBadge(
                                label: DateFormat('HH:mm').format(meetAt),
                                icon: Icons.schedule,
                                highlighted: true,
                                color: scheme.tertiary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: CosMetricTile(
                                    icon: Icons.groups_2_outlined,
                                    label: '呼叫小圈圈',
                                    value:
                                        circles
                                            .where(
                                              (circle) =>
                                                  circle.id == selectedCircleId,
                                            )
                                            .map((circle) => circle.name)
                                            .firstOrNull ??
                                        '未選擇',
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: CosMetricTile(
                                    icon: Icons.place_outlined,
                                    label: '集合座標',
                                    value:
                                        '${selectedPosition.latitude.toStringAsFixed(4)}, ${selectedPosition.longitude.toStringAsFixed(4)}',
                                    color: scheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    CosReveal(
                      delay: const Duration(milliseconds: 60),
                      child: CosCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CosSectionHeader(
                              title: '通知內容',
                              subtitle: '選擇要呼叫的小圈圈，補上一句現場提示',
                              icon: Icons.campaign_outlined,
                            ),
                            const SizedBox(height: 12),
                            _MeetupCircleSelector(
                              circles: circles,
                              selectedCircleId: selectedCircleId,
                              onChanged: (value) =>
                                  setSheetState(() => selectedCircleId = value),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: descriptionController,
                              decoration: const InputDecoration(
                                labelText: '集合點描述',
                                hintText: '例如：大門口左邊樹下',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CosReveal(
                      delay: const Duration(milliseconds: 110),
                      child: CosCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CosSectionHeader(
                              title: '集合位置',
                              subtitle: '拖動圖釘或點地圖即可變更集合座標',
                              icon: Icons.map_outlined,
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                CosUi.radiusLg,
                              ),
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
                                      icon:
                                          BitmapDescriptor.defaultMarkerWithHue(
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
                            const SizedBox(height: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(
                                CosUi.radiusMd,
                              ),
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
                              child: CosInfoTile(
                                icon: Icons.schedule,
                                label: '集合時間',
                                value: DateFormat('HH:mm').format(meetAt),
                                color: scheme.tertiary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            CosInfoTile(
                              icon: Icons.place,
                              label: '集合座標',
                              value:
                                  '${selectedPosition.latitude.toStringAsFixed(5)}, ${selectedPosition.longitude.toStringAsFixed(5)}',
                              color: scheme.secondary,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: useCurrentLocation,
                                icon: const Icon(Icons.my_location),
                                label: const Text('改用目前位置'),
                              ),
                            ),
                            if (_draftMeetupPosition != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '已使用地圖上長按放置的圖釘；可以拖動黃色圖釘調整，也可以改用目前位置。',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MeetupSubmitBar(
                      isSaving: isSaving,
                      editing: meetup != null,
                      onSubmit: saveMeetup,
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

  Future<void> _shareLocation(String eventId, int dayIndex) async {
    final settings = await _showLocationSharingSheet();
    if (settings == null || !mounted) return;
    setState(() => _isSharing = true);
    try {
      final position = await _currentPosition();
      if (!mounted) return;
      await ref
          .read(locationRepositoryProvider)
          .shareLocation(
            eventId: eventId,
            dayIndex: dayIndex,
            latitude: position.latitude,
            longitude: position.longitude,
            visibility: settings.visibility,
            expiresInMinutes: settings.expiresInMinutes,
          );
      if (!mounted) return;
      ref.invalidate(sharedLocationsProvider(eventId));
      setState(() => _myLocationEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已分享位置，${settings.expiresInMinutes} 分鐘後自動停止')),
      );
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

  Future<void> _stopSharingLocation(String eventId) async {
    try {
      await ref.read(locationRepositoryProvider).stopSharingLocation(eventId);
      ref.invalidate(sharedLocationsProvider(eventId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已停止分享位置')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('停止分享失敗：${userFacingError(error)}')),
      );
    }
  }

  Future<void> _updateSharedLocation(String eventId, int dayIndex) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final position = await _currentPosition();
      if (!mounted) return;
      await ref
          .read(locationRepositoryProvider)
          .updateSharedLocation(
            eventId: eventId,
            dayIndex: dayIndex,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      if (!mounted) return;
      ref.invalidate(sharedLocationsProvider(eventId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('位置已更新，原分享範圍與到期時間不變')));
    } catch (error) {
      if (!mounted) return;
      ref.invalidate(sharedLocationsProvider(eventId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新位置失敗：${userFacingError(error)}'),
          action: '$error'.contains('永久拒絕')
              ? SnackBarAction(
                  label: '開啟設定',
                  onPressed: Geolocator.openAppSettings,
                )
              : null,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _enableStealthMode(String eventId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RadarConfirmDialog(
        icon: Icons.visibility_off_outlined,
        title: '啟動緊急隱身',
        message: '會立即停止分享目前活動的位置，並把你的活動預訂可見範圍改成小圈圈。你之後可以在個人頁改回公開。',
        cancelLabel: '取消',
        confirmLabel: '啟動',
        confirmIcon: Icons.visibility_off_outlined,
      ),
    );
    if (confirmed != true) return;
    setState(() => _isSharing = true);
    try {
      await ref.read(locationRepositoryProvider).stopSharingLocation(eventId);
      final profile = await ref
          .read(profileRepositoryProvider)
          .currentProfile();
      if (profile != null && profile.bookingVisibility != 'circle') {
        await ref
            .read(profileRepositoryProvider)
            .saveProfile(profile.copyWith(bookingVisibility: 'circle'));
      }
      ref.invalidate(sharedLocationsProvider(eventId));
      ref.invalidate(eventsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已啟動緊急隱身')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('啟動隱身失敗：${userFacingError(error)}')),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<_LocationShareSettings?> _showLocationSharingSheet() async {
    if (!_hasConfirmedLocationSharing) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _RadarConfirmDialog(
          icon: Icons.verified_user_outlined,
          title: '先確認隱私設定',
          message: '你可以選擇誰看得到位置，也可以設定自動停止時間。位置只保留最新一筆，不會顯示移動路線。',
          cancelLabel: '先不要',
          confirmLabel: '設定分享',
          confirmIcon: Icons.tune,
          onConfirm: () {
            _hasConfirmedLocationSharing = true;
            Navigator.pop(context, true);
          },
        ),
      );
      if (confirmed != true) return null;
      if (!mounted) return null;
    }

    var visibility = 'circle';
    var expiresInMinutes = 30;
    return showModalBottomSheet<_LocationShareSettings>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final scheme = Theme.of(context).colorScheme;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CosGradientPanel(
                  icon: Icons.share_location,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CosSectionHeader(
                        title: '分享位置',
                        subtitle: '選擇看得到你的人，以及多久後自動停止分享',
                        icon: Icons.share_location,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '可見範圍',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'circle',
                            label: Text('小圈圈'),
                            icon: Icon(Icons.groups_2_outlined),
                          ),
                          ButtonSegment(
                            value: 'followed',
                            label: Text('關注者'),
                            icon: Icon(Icons.favorite_border),
                          ),
                          ButtonSegment(
                            value: 'public',
                            label: Text('活動參加者'),
                            icon: Icon(Icons.event_available_outlined),
                          ),
                        ],
                        selected: {visibility},
                        onSelectionChanged: (value) =>
                            setSheetState(() => visibility = value.first),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '自動停止',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final minutes in const [15, 30, 60])
                            ChoiceChip(
                              label: Text('$minutes 分鐘'),
                              selected: expiresInMinutes == minutes,
                              onSelected: (_) => setSheetState(
                                () => expiresInMinutes = minutes,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      CosInfoTile(
                        icon: Icons.privacy_tip_outlined,
                        label: '安全提醒',
                        value: '你可以隨時停止分享；封鎖的人看不到你的資料、預訂與位置。',
                        color: scheme.tertiary,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(
                                context,
                                _LocationShareSettings(
                                  visibility: visibility,
                                  expiresInMinutes: expiresInMinutes,
                                ),
                              ),
                              icon: const Icon(Icons.share_location),
                              label: const Text('分享'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final roleColor = participantRoleColorForScheme(location.role, scheme);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                CosReveal(
                  child: CosGradientPanel(
                    icon: Icons.person_pin_circle_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: roleColor,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [CosUi.softShadow(roleColor)],
                              ),
                              child: CircleAvatar(
                                radius: 34,
                                backgroundImage: pickedImageProvider(
                                  location.avatarUrl,
                                ),
                                child: location.avatarUrl.isEmpty
                                    ? Text(
                                        location
                                                .nickname
                                                .characters
                                                .firstOrNull ??
                                            '?',
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      CosBadge(
                                        label: _roleText(location),
                                        icon: Icons.badge_outlined,
                                        highlighted: true,
                                        color: roleColor,
                                      ),
                                      if (location.isCircleMember)
                                        CosBadge(
                                          label: '小圈圈成員',
                                          icon: Icons.groups_2_outlined,
                                          color: scheme.tertiary,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    location.nickname,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          height: 1.02,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_statusText(location.presenceStatus)} · ${_elapsedText(location, now: now)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: CosMetricTile(
                                icon: Icons.schedule,
                                label: '出沒時間',
                                value: location.availableTime.isEmpty
                                    ? '未填寫'
                                    : location.availableTime,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CosMetricTile(
                                icon: Icons.waving_hand_outlined,
                                label: '互動方式',
                                value: location.interactionTags.isEmpty
                                    ? '未設定'
                                    : '${location.interactionTags.length} 種',
                                color: scheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (location.interactionTags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CosReveal(
                    delay: const Duration(milliseconds: 70),
                    child: CosCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CosSectionHeader(
                            title: '歡迎互動方式',
                            subtitle: '先看對方開放的互動，再決定怎麼打招呼',
                            icon: Icons.forum_outlined,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final tag in location.interactionTags)
                                CosBadge(
                                  label: tag,
                                  icon: Icons.auto_awesome,
                                  color: scheme.secondary,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (location.characterName.isNotEmpty ||
                    location.outfitImageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CosReveal(
                    delay: const Duration(milliseconds: 110),
                    child: CosCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CosSectionHeader(
                            title: '今日角色',
                            subtitle: '現場辨識用的小提示',
                            icon: Icons.theater_comedy_outlined,
                          ),
                          if (location.characterName.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            CosInfoTile(
                              icon: Icons.auto_awesome,
                              label: '角色',
                              value: location.characterName,
                              color: roleColor,
                            ),
                          ],
                          if (location.outfitImageUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                CosUi.radiusLg,
                              ),
                              child: Image(
                                image: pickedImageProvider(
                                  location.outfitImageUrl,
                                )!,
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Text('當天出的角：${location.outfitImageUrl}'),
                              ),
                            ),
                          ],
                        ],
                      ),
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
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => _confirmBlockUser(location, eventId),
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('封鎖這位使用者'),
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

  Future<void> _confirmBlockUser(
    SharedLocation location,
    String eventId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RadarConfirmDialog(
        icon: Icons.block_outlined,
        title: '封鎖 ${location.nickname}',
        message: '封鎖後，對方將看不到你的個人資料、活動預訂與位置；你也不會再看到對方的現場位置。',
        cancelLabel: '取消',
        confirmLabel: '封鎖',
        confirmIcon: Icons.block_outlined,
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(profileRepositoryProvider).blockUser(location.userId);
      ref.invalidate(sharedLocationsProvider(eventId));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已封鎖 ${location.nickname}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('封鎖失敗：${userFacingError(error)}')));
    }
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

class _RadarConfirmDialog extends StatelessWidget {
  const _RadarConfirmDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.confirmIcon,
    this.onConfirm,
  });

  final IconData icon;
  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final IconData confirmIcon;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      clipBehavior: Clip.antiAlias,
      child: CosGradientPanel(
        icon: icon,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CosSectionHeader(title: title, subtitle: message, icon: icon),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onConfirm ?? () => Navigator.pop(context, true),
                    icon: Icon(confirmIcon),
                    label: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetupCircleSelector extends StatelessWidget {
  const _MeetupCircleSelector({
    required this.circles,
    required this.selectedCircleId,
    required this.onChanged,
  });

  final List<CircleGroup> circles;
  final String selectedCircleId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 380;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final circle in circles)
              SizedBox(
                width: narrow
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 8) / 2,
                child: _MeetupCircleOption(
                  circle: circle,
                  selected: circle.id == selectedCircleId,
                  onTap: () => onChanged(circle.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MeetupCircleOption extends StatelessWidget {
  const _MeetupCircleOption({
    required this.circle,
    required this.selected,
    required this.onTap,
  });

  final CircleGroup circle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = circle.isOwner ? scheme.primary : scheme.secondary;
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
              : scheme.surfaceContainerHighest.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.48)
                : scheme.outlineVariant.withValues(alpha: 0.55),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            CosIconBubble(
              icon: Icons.groups_2_outlined,
              color: accent,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    circle.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${circle.memberCount} 位成員',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? accent : scheme.outline,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetupSubmitBar extends StatelessWidget {
  const _MeetupSubmitBar({
    required this.isSaving,
    required this.editing,
    required this.onSubmit,
  });

  final bool isSaving;
  final bool editing;
  final VoidCallback onSubmit;

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
        child: FilledButton.icon(
          onPressed: isSaving ? null : onSubmit,
          icon: isSaving
              ? CosLoadingPulse(color: scheme.onPrimary, size: 20)
              : const Icon(Icons.notifications_active_outlined),
          label: Text(
            isSaving
                ? '同步集合訊號'
                : editing
                ? '更新集合通知'
                : '通知小圈圈集合',
          ),
        ),
      ),
    );
  }
}

class _CurrentEventLoadingCard extends StatelessWidget {
  const _CurrentEventLoadingCard();

  @override
  Widget build(BuildContext context) {
    return CosReveal(
      child: _CurrentEventStateCard(
        icon: Icons.radar_outlined,
        title: '正在接上現場雷達',
        subtitle: '讀取你已加入的活動和現場同好位置',
        accentColor: Theme.of(context).colorScheme.primary,
        child: const _RadarPulse(),
      ),
    );
  }
}

class _CurrentEventEmptyCard extends StatelessWidget {
  const _CurrentEventEmptyCard({required this.onOpenEvents});

  final VoidCallback? onOpenEvents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CosReveal(
      child: _CurrentEventStateCard(
        icon: Icons.event_available_outlined,
        title: '目前無當前活動',
        subtitle: '先加入今天或即將參加的場次，再回來分享位置、集合與認親',
        accentColor: scheme.secondary,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onOpenEvents,
            icon: const Icon(Icons.event_available),
            label: const Text('去活動清單'),
          ),
        ),
      ),
    );
  }
}

class _CurrentEventErrorCard extends StatelessWidget {
  const _CurrentEventErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CosReveal(
      child: _CurrentEventStateCard(
        icon: Icons.wifi_off_outlined,
        title: '現場訊號沒有接上',
        subtitle: message,
        accentColor: scheme.error,
      ),
    );
  }
}

class _CurrentEventStateCard extends StatelessWidget {
  const _CurrentEventStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CosUi.radiusXl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerLowest.withValues(alpha: 0.96),
            scheme.surfaceContainerHighest.withValues(alpha: 0.88),
          ],
        ),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
        boxShadow: [CosUi.softShadow(scheme.shadow)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CosIconBubble(icon: icon, color: accentColor, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (child != null) ...[const SizedBox(height: 16), child!],
          ],
        ),
      ),
    );
  }
}

class _RadarPulse extends StatefulWidget {
  const _RadarPulse();

  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (MediaQuery.disableAnimationsOf(context)) {
      return SizedBox(
        height: 58,
        child: Icon(Icons.location_searching, color: scheme.primary, size: 24),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return SizedBox(
          height: 58,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final offset in const [0.0, 0.33, 0.66])
                _RadarRing(
                  progress: (value + offset) % 1,
                  color: scheme.primary,
                ),
              Icon(Icons.location_searching, color: scheme.primary, size: 24),
            ],
          ),
        );
      },
    );
  }
}

class _RadarRing extends StatelessWidget {
  const _RadarRing({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scale = 0.42 + progress * 0.9;
    final opacity = (1 - progress).clamp(0.0, 1.0);

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.42), width: 2),
          ),
        ),
      ),
    );
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
    final filterLabel = switch (filter) {
      LocationFilter.all => '全部',
      LocationFilter.followed => '關注',
      LocationFilter.circle => '小圈圈',
      LocationFilter.friends => '戳友',
    };
    final eventTitle = event == null
        ? '目前無當前活動'
        : currentEventTitle(event!, dayIndex);
    final countText = event == null
        ? '加入場次後顯示現場'
        : '$visibleCount / $totalCount 位可見';

    return CosReveal(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(CosUi.radiusLg),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          eventTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '$countText · $filterLabel · D$dayIndex',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (switchTargets.length > 1)
                    _HeaderIconMenu<CurrentEventTarget>(
                      tooltip: '切換當前活動',
                      icon: Icons.swap_horiz,
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
                      visualDensity: VisualDensity.compact,
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  _HeaderIconMenu<LocationFilter>(
                    tooltip: '篩選',
                    icon: Icons.tune_outlined,
                    initialValue: filter,
                    onSelected: onFilterChanged,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: LocationFilter.all,
                        child: Text('全部'),
                      ),
                      PopupMenuItem(
                        value: LocationFilter.followed,
                        child: Text('僅顯示關注'),
                      ),
                      PopupMenuItem(
                        value: LocationFilter.circle,
                        child: Text('僅顯示小圈圈'),
                      ),
                      PopupMenuItem(
                        value: LocationFilter.friends,
                        child: Text('僅顯示戳友'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _sameTarget(EventDayItem item, CurrentEventTarget target) {
    return item.event.id == target.eventId && item.dayIndex == target.dayIndex;
  }
}

class _HeaderIconMenu<T> extends StatelessWidget {
  const _HeaderIconMenu({
    required this.tooltip,
    required this.icon,
    required this.itemBuilder,
    required this.onSelected,
    this.initialValue,
  });

  final String tooltip;
  final IconData icon;
  final T? initialValue;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: initialValue,
      icon: Icon(icon),
      onSelected: onSelected,
      itemBuilder: itemBuilder,
    );
  }
}

class _MapActionDock extends StatefulWidget {
  const _MapActionDock({
    required this.circleItems,
    required this.visibleCount,
    required this.totalCount,
    required this.activeMeetup,
    required this.isSharing,
    required this.mySharedLocation,
    required this.onMeetup,
    required this.onShareLocation,
    required this.onUpdateLocation,
    required this.onStopSharing,
    required this.onStealthMode,
  });

  final List<CircleGroup> circleItems;
  final int visibleCount;
  final int totalCount;
  final MeetupPoint? activeMeetup;
  final bool isSharing;
  final SharedLocation? mySharedLocation;
  final VoidCallback? onMeetup;
  final VoidCallback? onShareLocation;
  final VoidCallback? onUpdateLocation;
  final VoidCallback? onStopSharing;
  final VoidCallback? onStealthMode;

  @override
  State<_MapActionDock> createState() => _MapActionDockState();
}

class _MapActionDockState extends State<_MapActionDock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meetupLabel = widget.activeMeetup == null
        ? '尚未設定'
        : widget.activeMeetup!.circleName;
    final sharingLocation = widget.mySharedLocation;
    final sharingLabel = sharingLocation == null
        ? '未分享'
        : _shareVisibilityLabel(sharingLocation.visibility);
    final expiryMinutes = sharingLocation?.minutesUntilExpiry(DateTime.now());
    final sharingSubtitle = sharingLocation == null
        ? '目前沒有公開你的現場位置。'
        : expiryMinutes == null
        ? '位置目前分享中，可隨時停止。'
        : '位置分享中，約 $expiryMinutes 分鐘後自動停止。';
    return CosReveal(
      delay: const Duration(milliseconds: 110),
      offset: const Offset(0, 18),
      child: SafeArea(
        top: false,
        child: CosCard(
          padding: const EdgeInsets.all(8),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: _expanded
                    ? (MediaQuery.sizeOf(context).height * 0.42).clamp(
                        220.0,
                        360.0,
                      )
                    : ((MediaQuery.textScalerOf(context).scale(14) +
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(12)) *
                                  1.5 +
                              16)
                          .clamp(64.0, 140.0),
              ),
              child: SingleChildScrollView(
                physics: _expanded
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MapActionDockHeader(
                      sharingLocation: sharingLocation,
                      sharingLabel: sharingLabel,
                      sharingSubtitle: sharingSubtitle,
                      visibleCount: widget.visibleCount,
                      totalCount: widget.totalCount,
                      expanded: _expanded,
                      isSharing: widget.isSharing,
                      onPrimaryAction: sharingLocation == null
                          ? widget.onShareLocation
                          : widget.onStopSharing,
                      onUpdateLocation: widget.onUpdateLocation,
                      onExpandedChanged: (value) =>
                          setState(() => _expanded = value),
                    ),
                    if (_expanded) ...[
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 380;
                          final metricTiles = [
                            CosMetricTile(
                              icon: Icons.location_on_outlined,
                              label: '現場同好',
                              value:
                                  '${widget.visibleCount} / ${widget.totalCount}',
                              color: scheme.primary,
                            ),
                            CosMetricTile(
                              icon: Icons.flag_outlined,
                              label: '集合點',
                              value: meetupLabel,
                              color: scheme.secondary,
                            ),
                            CosMetricTile(
                              icon: Icons.privacy_tip_outlined,
                              label: '位置可見',
                              value: sharingLabel,
                              color: scheme.tertiary,
                            ),
                          ];
                          final actionButtons = [
                            FilledButton.icon(
                              onPressed: widget.onMeetup,
                              icon: const Icon(Icons.flag_outlined),
                              label: const Text('集合點'),
                            ),
                            OutlinedButton.icon(
                              onPressed: sharingLocation == null
                                  ? widget.onShareLocation
                                  : widget.onUpdateLocation,
                              icon: widget.isSharing
                                  ? CosLoadingPulse(
                                      color: scheme.primary,
                                      size: 20,
                                    )
                                  : const Icon(Icons.share_location),
                              label: Text(
                                widget.isSharing
                                    ? '定位中'
                                    : sharingLocation == null
                                    ? '分享位置'
                                    : '更新位置',
                              ),
                            ),
                            if (sharingLocation != null)
                              TextButton.icon(
                                onPressed: widget.onStopSharing,
                                icon: const Icon(Icons.visibility_off_outlined),
                                label: const Text('停止分享'),
                              ),
                            TextButton.icon(
                              onPressed: widget.onStealthMode,
                              icon: const Icon(Icons.shield_outlined),
                              label: const Text('緊急隱身'),
                            ),
                          ];

                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 72,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: metricTiles.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) => SizedBox(
                                      width: 132,
                                      child: metricTiles[index],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: actionButtons,
                                ),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              Row(
                                children: [
                                  for (
                                    var index = 0;
                                    index < metricTiles.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const SizedBox(width: 8),
                                    Expanded(child: metricTiles[index]),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  for (
                                    var index = 0;
                                    index < actionButtons.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const SizedBox(width: 10),
                                    Expanded(child: actionButtons[index]),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '長按地圖可先放置集合點草稿，再通知小圈圈。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapActionDockHeader extends StatelessWidget {
  const _MapActionDockHeader({
    required this.sharingLocation,
    required this.sharingLabel,
    required this.sharingSubtitle,
    required this.visibleCount,
    required this.totalCount,
    required this.expanded,
    required this.isSharing,
    required this.onPrimaryAction,
    required this.onUpdateLocation,
    required this.onExpandedChanged,
  });

  final SharedLocation? sharingLocation;
  final String sharingLabel;
  final String sharingSubtitle;
  final int visibleCount;
  final int totalCount;
  final bool expanded;
  final bool isSharing;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onUpdateLocation;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CosIconBubble(
          icon: Icons.radar_outlined,
          color: scheme.secondary,
          size: 30,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(CosUi.radiusSm),
            onTap: () => onExpandedChanged(!expanded),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '現場雷達',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    expanded
                        ? sharingSubtitle
                        : '$visibleCount / $totalCount 位同好 · $sharingLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: sharingLocation == null ? '分享位置' : '停止分享',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          onPressed: onPrimaryAction,
          icon: isSharing
              ? CosLoadingPulse(color: scheme.primary, size: 20)
              : Icon(
                  sharingLocation == null
                      ? Icons.share_location
                      : Icons.visibility_off_outlined,
                ),
        ),
        if (sharingLocation != null)
          IconButton(
            tooltip: '更新位置',
            onPressed: onUpdateLocation,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: const Icon(Icons.my_location),
          ),
        IconButton(
          tooltip: expanded ? '收合現場雷達' : '展開現場雷達',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          onPressed: () => onExpandedChanged(!expanded),
          icon: AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: const Icon(Icons.keyboard_arrow_up),
          ),
        ),
      ],
    );
  }
}

String _shareVisibilityLabel(String visibility) {
  return switch (visibility) {
    'public' => '活動參加者',
    'followed' => '關注者',
    'circle' => '小圈圈',
    _ => '小圈圈',
  };
}
