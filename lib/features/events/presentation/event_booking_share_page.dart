import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/event.dart';
import '../../../core/models/participant.dart';
import '../../../core/utils/participant_role_style.dart';
import '../../../core/utils/picked_image_provider.dart';

class EventBookingSharePage extends StatefulWidget {
  const EventBookingSharePage({
    super.key,
    required this.event,
    required this.bookings,
  });

  final CosEvent event;
  final List<EventParticipant> bookings;

  @override
  State<EventBookingSharePage> createState() => _EventBookingSharePageState();
}

class _EventBookingSharePageState extends State<EventBookingSharePage> {
  static const _backgroundColors = [
    Color(0xffffd9a6),
    Color(0xffd8e8ff),
    Color(0xffead9ff),
    Color(0xffdcefd2),
    Color(0xffffd7df),
    Color(0xfff0e3c7),
  ];

  final _boundaryKey = GlobalKey();
  final _previewKey = GlobalKey();
  late Color _backgroundColor;
  late final Map<int, TextEditingController> _labelControllers;
  late final Map<int, _EditableTransform> _photoTransforms;
  late final Map<int, _EditableTransform> _labelTransforms;
  late final Map<int, double> _labelFontSizes;
  late final TextEditingController _messageController;
  _SelectedShareLayer? _selectedLayer;
  _EditableTransform _gestureStartTransform = const _EditableTransform();
  Offset _gestureStartFocalPoint = Offset.zero;
  int _previewPointerCount = 0;
  bool _previewScrollLocked = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _backgroundColor =
        _backgroundColors[Random().nextInt(_backgroundColors.length)];
    _photoTransforms = {
      for (var index = 1; index <= _dayCount; index += 1)
        index: const _EditableTransform(),
    };
    _labelControllers = {
      for (var index = 1; index <= _dayCount; index += 1)
        index: TextEditingController(
          text: _bookingForDay(index)?.characterName ?? '',
        ),
    };
    _labelTransforms = {
      for (var index = 1; index <= _dayCount; index += 1)
        index: const _EditableTransform(offset: Offset(22, 260)),
    };
    _labelFontSizes = {
      for (var index = 1; index <= _dayCount; index += 1) index: 80,
    };
    _messageController = TextEditingController(text: _primaryBooking.message);
  }

  @override
  void dispose() {
    for (final controller in _labelControllers.values) {
      controller.dispose();
    }
    _messageController.dispose();
    super.dispose();
  }

  int get _dayCount {
    return max(
      1,
      widget.event.endDate.difference(widget.event.startDate).inDays + 1,
    );
  }

  EventParticipant? _bookingForDay(int dayIndex) {
    return widget.bookings
        .where((item) => item.dayIndex == dayIndex)
        .firstOrNull;
  }

  EventParticipant get _primaryBooking => widget.bookings.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('預訂分享圖'),
        actions: [
          IconButton(
            tooltip: '分享圖片',
            onPressed: _sharing ? null : _shareImage,
            icon: _sharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          physics: _previewScrollLocked
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Listener(
              onPointerDown: (_) => _handlePreviewPointerDown(),
              onPointerUp: (_) => _handlePreviewPointerEnd(),
              onPointerCancel: (_) => _handlePreviewPointerEnd(),
              child: GestureDetector(
                key: _previewKey,
                behavior: HitTestBehavior.translucent,
                onScaleStart: _handlePreviewScaleStart,
                onScaleUpdate: _handlePreviewScaleUpdate,
                child: AspectRatio(
                  aspectRatio: 1800 / 1200,
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: SizedBox(
                        width: 1800,
                        height: 1200,
                        child: _ShareCanvas(
                          event: widget.event,
                          bookings: widget.bookings,
                          backgroundColor: _backgroundColor,
                          dayCount: _dayCount,
                          photoTransforms: _photoTransforms,
                          labelControllers: _labelControllers,
                          labelTransforms: _labelTransforms,
                          labelFontSizes: _labelFontSizes,
                          message: _messageController.text,
                          selectedLayer: _sharing ? null : _selectedLayer,
                          onLayerSelected: (layer) {
                            setState(() => _selectedLayer = layer);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('背景色', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ColorPicker(
              color: _backgroundColor,
              onChanged: (color) => setState(() => _backgroundColor = color),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _backgroundColors)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _backgroundColor = color),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == _backgroundColor
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: color == _backgroundColor ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('備註', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: '留言內容',
                helperText: '會同步顯示在左側留言欄',
              ),
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('角色名', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var index = 1; index <= _dayCount; index += 1) ...[
              TextField(
                controller: _labelControllers[index],
                decoration: InputDecoration(
                  labelText: 'D$index 角色名',
                  helperText: '先點選元件，再於預覽圖任意位置拖曳、雙指縮放旋轉',
                ),
                onChanged: (_) => setState(() {}),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 68,
                    child: Text('字級 ${(_labelFontSizes[index] ?? 80).round()}'),
                  ),
                  Expanded(
                    child: Slider(
                      min: 50,
                      max: 300,
                      value: _labelFontSizes[index] ?? 80,
                      onChanged: (value) {
                        debugPrint(
                          '[BookingShare] set D$index labelFontSize=$value',
                        );
                        setState(() => _labelFontSizes[index] = value);
                      },
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _photoTransforms[index] = const _EditableTransform();
                        _labelTransforms[index] = const _EditableTransform(
                          offset: Offset(22, 260),
                        );
                        _labelFontSizes[index] = 80;
                        debugPrint(
                          '[BookingShare] reset D$index labelFontSize=80',
                        );
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重置'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _sharing ? null : _shareImage,
              icon: const Icon(Icons.ios_share),
              label: const Text('產生並分享圖片'),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePreviewScaleStart(ScaleStartDetails details) {
    final layer = _selectedLayer;
    if (_sharing || layer == null) return;
    _setPreviewScrollLocked(true);
    _gestureStartTransform = _transformForLayer(layer);
    _gestureStartFocalPoint = details.focalPoint;
  }

  void _handlePreviewScaleUpdate(ScaleUpdateDetails details) {
    final layer = _selectedLayer;
    if (_sharing || layer == null) return;
    final minScale = layer.kind == _ShareLayerKind.photo ? 1.0 : 0.5;
    final maxScale = layer.kind == _ShareLayerKind.photo ? 5.0 : 4.0;
    final canvasDelta =
        (details.focalPoint - _gestureStartFocalPoint) / _previewScale;
    final next = _gestureStartTransform.copyWith(
      offset: _gestureStartTransform.offset + canvasDelta,
      scale: (_gestureStartTransform.scale * details.scale)
          .clamp(minScale, maxScale)
          .toDouble(),
      rotation: _gestureStartTransform.rotation + details.rotation,
    );
    setState(() {
      if (layer.kind == _ShareLayerKind.photo) {
        _photoTransforms[layer.dayIndex] = next;
      } else {
        _labelTransforms[layer.dayIndex] = next;
      }
    });
  }

  double get _previewScale {
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width;
    if (width == null || width <= 0) return 1;
    return width / 1800;
  }

  void _handlePreviewPointerDown() {
    _previewPointerCount += 1;
    if (_selectedLayer != null || _previewPointerCount > 1) {
      _setPreviewScrollLocked(true);
    }
  }

  void _handlePreviewPointerEnd() {
    _previewPointerCount = max(0, _previewPointerCount - 1);
    if (_previewPointerCount == 0) {
      _setPreviewScrollLocked(false);
    }
  }

  void _setPreviewScrollLocked(bool locked) {
    if (_previewScrollLocked == locked) return;
    setState(() => _previewScrollLocked = locked);
  }

  _EditableTransform _transformForLayer(_SelectedShareLayer layer) {
    if (layer.kind == _ShareLayerKind.photo) {
      return _photoTransforms[layer.dayIndex] ?? const _EditableTransform();
    }
    return _labelTransforms[layer.dayIndex] ??
        const _EditableTransform(offset: Offset(22, 260));
  }

  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return;
      final file = await _writeTempImage(bytes);
      await SharePlus.instance.share(
        ShareParams(
          title: '${widget.event.name} 參加預定',
          text: '${widget.event.name} 參加預定',
          files: [XFile(file.path, mimeType: 'image/png')],
          fileNameOverrides: ['coscircle_booking_${widget.event.id}.png'],
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<File> _writeTempImage(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/coscircle_booking_${widget.event.id}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    return file.writeAsBytes(bytes, flush: true);
  }
}

class _ShareCanvas extends StatelessWidget {
  const _ShareCanvas({
    required this.event,
    required this.bookings,
    required this.backgroundColor,
    required this.dayCount,
    required this.photoTransforms,
    required this.labelControllers,
    required this.labelTransforms,
    required this.labelFontSizes,
    required this.message,
    required this.selectedLayer,
    required this.onLayerSelected,
  });

  final CosEvent event;
  final List<EventParticipant> bookings;
  final Color backgroundColor;
  final int dayCount;
  final Map<int, _EditableTransform> photoTransforms;
  final Map<int, TextEditingController> labelControllers;
  final Map<int, _EditableTransform> labelTransforms;
  final Map<int, double> labelFontSizes;
  final String message;
  final _SelectedShareLayer? selectedLayer;
  final ValueChanged<_SelectedShareLayer> onLayerSelected;

  EventParticipant get primary => bookings.first;

  @override
  Widget build(BuildContext context) {
    final days = [for (var index = 1; index <= dayCount; index += 1) index];
    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 82,
            child: ColoredBox(
              color: _strongColor(backgroundColor),
              child: Center(
                child: Text(
                  '${event.name} / COSPLAY 參加預定',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 30,
            top: 116,
            width: 430,
            bottom: 32,
            child: _InfoPanel(
              event: event,
              participant: primary,
              message: message,
            ),
          ),
          Positioned(
            left: 500,
            right: 24,
            top: 116,
            bottom: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final dayIndex in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: _DayColumn(
                        event: event,
                        dayIndex: dayIndex,
                        participant: bookings
                            .where((item) => item.dayIndex == dayIndex)
                            .firstOrNull,
                        photoTransform:
                            photoTransforms[dayIndex] ??
                            const _EditableTransform(),
                        labelController: labelControllers[dayIndex]!,
                        labelTransform:
                            labelTransforms[dayIndex] ??
                            const _EditableTransform(offset: Offset(22, 260)),
                        labelFontSize: labelFontSizes[dayIndex] ?? 80,
                        selectedLayer: selectedLayer,
                        onLayerSelected: onLayerSelected,
                        accent: _strongColor(backgroundColor),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _strongColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withSaturation(0.72).withLightness(0.44).toColor();
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.event,
    required this.participant,
    required this.message,
  });

  final CosEvent event;
  final EventParticipant participant;
  final String message;

  @override
  Widget build(BuildContext context) {
    final role = participantRoleLabel(participant.role);
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  event.name,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
            ),
            Text(
              _dateText(event),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 7,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              role,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 38,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              participant.nickname,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 38,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            _Box(label: 'CN / 名字', text: participant.nickname, maxLines: 2),
            const SizedBox(height: 12),
            _Box(label: '留言', text: message, maxLines: 5),
            const SizedBox(height: 8),
            Text(
              '#${event.name.replaceAll(' ', '')} #cosplay #CosCircle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.label, required this.text, required this.maxLines});

  final String label;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: maxLines,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.orange, width: 3),
        ),
        child: Text(
          text.isEmpty ? label : '$label\n$text',
          maxLines: maxLines + 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.event,
    required this.dayIndex,
    required this.participant,
    required this.photoTransform,
    required this.labelController,
    required this.labelTransform,
    required this.labelFontSize,
    required this.selectedLayer,
    required this.onLayerSelected,
    required this.accent,
  });

  final CosEvent event;
  final int dayIndex;
  final EventParticipant? participant;
  final _EditableTransform photoTransform;
  final TextEditingController labelController;
  final _EditableTransform labelTransform;
  final double labelFontSize;
  final _SelectedShareLayer? selectedLayer;
  final ValueChanged<_SelectedShareLayer> onLayerSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final date = event.startDate.add(Duration(days: dayIndex - 1));
    final photoLayer = _SelectedShareLayer.photo(dayIndex);
    final labelLayer = _SelectedShareLayer.label(dayIndex);
    debugPrint('[BookingShare] canvas D$dayIndex labelFontSize=$labelFontSize');
    return Column(
      children: [
        Text(
          'D$dayIndex',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 48,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: accent, width: 4),
                ),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    if (participant?.outfitImageUrl.isNotEmpty == true)
                      Positioned.fill(
                        child: _TransformableLayer(
                          transform: photoTransform,
                          isSelected: selectedLayer == photoLayer,
                          minScale: 1,
                          maxScale: 5,
                          onSelected: () => onLayerSelected(photoLayer),
                          child: Image(
                            image: pickedImageProvider(
                              participant!.outfitImageUrl,
                            )!,
                            fit: BoxFit.cover,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: Text(
                          '未發布此日照片',
                          style: TextStyle(
                            color: Colors.black45,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: _TransformableLayer(
                        transform: labelTransform,
                        isSelected: selectedLayer == labelLayer,
                        minScale: 0.5,
                        maxScale: 4,
                        onSelected: () => onLayerSelected(labelLayer),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Text(
                              labelController.text.trim().isEmpty
                                  ? participant?.characterName ?? ''
                                  : labelController.text.trim(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: labelFontSize,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          DateFormat('M/d (E)', 'zh_TW').format(date),
          style: const TextStyle(
            color: Colors.black,
            fontSize: 42,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.white, blurRadius: 3)],
          ),
        ),
      ],
    );
  }
}

class _TransformableLayer extends StatefulWidget {
  const _TransformableLayer({
    required this.transform,
    required this.isSelected,
    required this.onSelected,
    required this.child,
    this.minScale = 0.5,
    this.maxScale = 4,
  });

  final _EditableTransform transform;
  final bool isSelected;
  final VoidCallback onSelected;
  final Widget child;
  final double minScale;
  final double maxScale;

  @override
  State<_TransformableLayer> createState() => _TransformableLayerState();
}

class _TransformableLayerState extends State<_TransformableLayer> {
  final _childKey = GlobalKey();
  Size _childSize = Size.zero;

  @override
  Widget build(BuildContext context) {
    _measureChildAfterLayout();
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(constraints.maxWidth, constraints.maxHeight);
        final transform = _clampTransform(widget.transform, bounds);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: transform.offset.dx,
              top: transform.offset.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTap: widget.onSelected,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..rotateZ(transform.rotation)
                    ..scaleByDouble(transform.scale, transform.scale, 1, 1),
                  child: Stack(
                    key: _childKey,
                    clipBehavior: Clip.none,
                    children: [
                      widget.child,
                      if (widget.isSelected)
                        Positioned(right: -8, top: -8, child: _MoveHandle()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _measureChildAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _childKey.currentContext?.findRenderObject() as RenderBox?;
      final nextSize = box?.size ?? Size.zero;
      if (nextSize != _childSize) {
        setState(() => _childSize = nextSize);
      }
    });
  }

  _EditableTransform _clampTransform(
    _EditableTransform transform,
    Size bounds,
  ) {
    if (_childSize == Size.zero ||
        !bounds.width.isFinite ||
        !bounds.height.isFinite) {
      return transform;
    }

    final scale = transform.scale
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();
    final width = _childSize.width * scale;
    final height = _childSize.height * scale;
    final cosValue = cos(transform.rotation).abs();
    final sinValue = sin(transform.rotation).abs();
    final rotatedWidth = width * cosValue + height * sinValue;
    final rotatedHeight = width * sinValue + height * cosValue;
    final halfWidth = rotatedWidth / 2;
    final halfHeight = rotatedHeight / 2;
    final currentCenter = Offset(
      transform.offset.dx + _childSize.width / 2,
      transform.offset.dy + _childSize.height / 2,
    );
    final centerX = _clampCenter(currentCenter.dx, halfWidth, bounds.width);
    final centerY = _clampCenter(currentCenter.dy, halfHeight, bounds.height);
    return transform.copyWith(
      offset: Offset(
        centerX - _childSize.width / 2,
        centerY - _childSize.height / 2,
      ),
      scale: scale,
    );
  }

  double _clampCenter(double value, double halfExtent, double maxExtent) {
    final minValue = halfExtent;
    final maxValue = maxExtent - halfExtent;
    if (minValue > maxValue) return maxExtent / 2;
    return value.clamp(minValue, maxValue).toDouble();
  }
}

class _MoveHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.all(7),
        child: Icon(Icons.open_with, color: Colors.white, size: 22),
      ),
    );
  }
}

class _SelectedShareLayer {
  const _SelectedShareLayer._(this.dayIndex, this.kind);

  factory _SelectedShareLayer.photo(int dayIndex) {
    return _SelectedShareLayer._(dayIndex, _ShareLayerKind.photo);
  }

  factory _SelectedShareLayer.label(int dayIndex) {
    return _SelectedShareLayer._(dayIndex, _ShareLayerKind.label);
  }

  final int dayIndex;
  final _ShareLayerKind kind;

  @override
  bool operator ==(Object other) {
    return other is _SelectedShareLayer &&
        other.dayIndex == dayIndex &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(dayIndex, kind);
}

enum _ShareLayerKind { photo, label }

class _EditableTransform {
  const _EditableTransform({
    this.offset = Offset.zero,
    this.scale = 1,
    this.rotation = 0,
  });

  final Offset offset;
  final double scale;
  final double rotation;

  _EditableTransform copyWith({
    Offset? offset,
    double? scale,
    double? rotation,
  }) {
    return _EditableTransform(
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final red = _channel(color, 16);
    final green = _channel(color, 8);
    final blue = _channel(color, 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            _ColorChannelSlider(
              label: 'R',
              value: red,
              color: Colors.red,
              onChanged: (value) =>
                  onChanged(Color.fromARGB(255, value.round(), green, blue)),
            ),
            _ColorChannelSlider(
              label: 'G',
              value: green,
              color: Colors.green,
              onChanged: (value) =>
                  onChanged(Color.fromARGB(255, red, value.round(), blue)),
            ),
            _ColorChannelSlider(
              label: 'B',
              value: blue,
              color: Colors.blue,
              onChanged: (value) =>
                  onChanged(Color.fromARGB(255, red, green, value.round())),
            ),
          ],
        ),
      ),
    );
  }

  int _channel(Color color, int shift) => (color.toARGB32() >> shift) & 0xff;
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(label, style: TextStyle(color: color)),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: 255,
            value: value.toDouble(),
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

String _dateText(CosEvent event) {
  if (event.startDate == event.endDate) {
    return DateFormat('yyyy/MM/dd').format(event.startDate);
  }
  return '${DateFormat('yyyy/MM/dd').format(event.startDate)} - ${DateFormat('MM/dd').format(event.endDate)}';
}
