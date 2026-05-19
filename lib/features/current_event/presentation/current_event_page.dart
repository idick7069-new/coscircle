import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/models/event.dart';
import '../../../core/models/shared_location.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/repositories/location_repository.dart';
import '../../../core/utils/picked_image_provider.dart';

final sharedLocationsProvider = FutureProvider.autoDispose
    .family<List<SharedLocation>, String>((ref, eventId) {
      return ref
          .watch(locationRepositoryProvider)
          .fetchSharedLocations(eventId);
    });

enum LocationFilter { all, followed, circle }

class CurrentEventPage extends ConsumerStatefulWidget {
  const CurrentEventPage({super.key, this.eventId});

  final String? eventId;

  @override
  ConsumerState<CurrentEventPage> createState() => _CurrentEventPageState();
}

class _CurrentEventPageState extends ConsumerState<CurrentEventPage> {
  static const _defaultPosition = LatLng(25.033964, 121.564468);
  LocationFilter _filter = LocationFilter.all;
  bool _isSharing = false;
  bool _myLocationEnabled = false;
  final Map<String, BitmapDescriptor> _markerIcons = {};
  final Set<String> _loadingMarkerIcons = {};

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final eventItems = events.whenOrNull(data: (items) => items);
    final event = _currentEvent(eventItems);
    final eventId = event?.id;
    final isResolvingEvent = events.isLoading;
    final locations = event == null
        ? const AsyncData(<SharedLocation>[])
        : ref.watch(sharedLocationsProvider(event.id));

    return Scaffold(
      appBar: widget.eventId == null
          ? null
          : AppBar(
              leading: IconButton(
                tooltip: '返回',
                onPressed: () => context.go('/'),
                icon: const BackButtonIcon(),
              ),
              title: Text(event?.name ?? '當前活動'),
            ),
      body: SafeArea(
        child: locations.when(
          data: (items) {
            _warmMarkerIcons(items);
            return Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: _defaultPosition,
                    zoom: 15,
                  ),
                  myLocationButtonEnabled: true,
                  myLocationEnabled: _myLocationEnabled,
                  markers: _markersFor(items),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: _EventMapHeader(
                    event: event,
                    filter: _filter,
                    visibleCount: _filtered(items).length,
                    totalCount: items.length,
                    onFilterChanged: (value) => setState(() => _filter = value),
                    onRefresh: eventId == null
                        ? null
                        : () =>
                              ref.invalidate(sharedLocationsProvider(eventId)),
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
                        child: Text(
                          '目前無當前活動',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
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
      floatingActionButton: FloatingActionButton.extended(
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

  int _distanceFromToday(CosEvent event, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      event.startDate.year,
      event.startDate.month,
      event.startDate.day,
    );
    return start.difference(today).inDays.abs();
  }

  CosEvent? _currentEvent(List<CosEvent>? events) {
    if (events == null) return null;
    final now = DateTime.now();
    final id = widget.eventId ?? _defaultCurrentEventId(events);
    if (id == null) return null;
    final event = events.where((event) => event.id == id).firstOrNull;
    if (event == null || event.status(now) != EventStatus.active) return null;
    return event;
  }

  Set<Marker> _markersFor(List<SharedLocation> items) {
    return _filtered(items).map((location) {
      return Marker(
        markerId: MarkerId('user-${location.userId}'),
        position: LatLng(location.latitude, location.longitude),
        icon:
            _markerIcons[location.userId] ??
            BitmapDescriptor.defaultMarkerWithHue(
              location.isMe
                  ? BitmapDescriptor.hueAzure
                  : BitmapDescriptor.hueRose,
            ),
        infoWindow: InfoWindow(
          title: location.isMe ? '我：${location.nickname}' : location.nickname,
          snippet: '${_roleText(location)} · ${_elapsedText(location)}',
        ),
        onTap: () => _showLocationSheet(location),
      );
    }).toSet();
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
      if (_markerIcons.containsKey(location.userId) ||
          _loadingMarkerIcons.contains(location.userId)) {
        continue;
      }
      _loadingMarkerIcons.add(location.userId);
      _buildAvatarMarker(location).then((icon) {
        if (!mounted) return;
        setState(() {
          _markerIcons[location.userId] = icon;
          _loadingMarkerIcons.remove(location.userId);
        });
      });
    }
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
    final color = location.isMe ? scheme.primary : scheme.secondary;
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
    final image = await _loadNetworkImage(location.avatarUrl);
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
        textDirection: TextDirection.ltr,
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

    final picture = recorder.endRecording();
    final png = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await png.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<ui.Image?> _loadNetworkImage(String url) async {
    if (url.isEmpty ||
        (!url.startsWith('http://') && !url.startsWith('https://'))) {
      return null;
    }
    try {
      final data = await NetworkAssetBundle(Uri.parse(url)).load('');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareLocation(String eventId) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享位置失敗：$error')));
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
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

  void _showLocationSheet(SharedLocation location) {
    final now = DateTime.now();
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
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: pickedImageProvider(location.avatarUrl),
                      child: location.avatarUrl.isEmpty
                          ? Text(
                              location.nickname.characters.firstOrNull ?? '?',
                            )
                          : null,
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
                            '${_roleText(location)} · ${_elapsedText(location, now: now)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                          Text('當天穿著：${location.outfitImageUrl}'),
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

  String _elapsedText(SharedLocation location, {DateTime? now}) {
    final minutes = location.minutesAgo(now ?? DateTime.now());
    if (minutes < 60) return '$minutes 分鐘前';
    final hours = minutes ~/ 60;
    return '$hours 小時前';
  }

  String _roleText(SharedLocation location) {
    return switch (location.role) {
      'photographer' => '攝影',
      'coser' =>
        location.characterName.isEmpty
            ? 'Coser'
            : 'Coser / ${location.characterName}',
      'self' => '本體',
      _ => '參加者',
    };
  }
}

class _EventMapHeader extends StatelessWidget {
  const _EventMapHeader({
    required this.event,
    required this.filter,
    required this.visibleCount,
    required this.totalCount,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final CosEvent? event;
  final LocationFilter filter;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<LocationFilter> onFilterChanged;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.event_available),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                event == null
                    ? '目前無當前活動'
                    : '${event!.name} · $visibleCount / $totalCount',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
      ),
    );
  }
}
