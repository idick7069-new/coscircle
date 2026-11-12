import 'package:flutter/material.dart';

enum MimiScene { reading, map, hello }

class MimiMascot extends StatefulWidget {
  const MimiMascot({
    super.key,
    this.scene = MimiScene.hello,
    this.size = 128,
    this.animate = true,
    this.semanticLabel,
  });

  final MimiScene scene;
  final double size;
  final bool animate;
  final String? semanticLabel;

  @override
  State<MimiMascot> createState() => _MimiMascotState();
}

class _MimiMascotState extends State<MimiMascot> with WidgetsBindingObserver {
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _lifecycle = state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hello = widget.scene == MimiScene.hello;
    const greeting = 'portrait';
    final playing =
        !hello &&
        widget.animate &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.of(context) &&
        (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);
    final still = hello
        ? 'assets/mimi/cute-v1/$greeting.png'
        : 'assets/mimi/cute-v1/${widget.scene.name}-still.png';
    final asset = playing ? 'assets/mimi/cute-v1/${widget.scene.name}.gif' : still;
    final visual = SizedBox.square(
      dimension: widget.size,
      child: Image.asset(
        asset,
        key: ValueKey(asset),
        width: widget.size,
        height: widget.size,
        cacheWidth: 64,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stack) => Image.asset(
          'assets/mimi/cute-v1/$greeting.png',
          cacheWidth: 64,
          filterQuality: FilterQuality.none,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stack) => Icon(
            Icons.auto_awesome,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
    if (widget.semanticLabel == null) return ExcludeSemantics(child: visual);
    return Semantics(image: true, label: widget.semanticLabel, child: visual);
  }
}

class MimiLoading extends StatelessWidget {
  const MimiLoading({
    super.key,
    this.scene = MimiScene.reading,
    this.label = '希希正在整理資料…',
    this.compact = false,
  });

  final MimiScene scene;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferred = compact ? 72.0 : 128.0;
        final size = constraints.hasBoundedHeight
            ? (constraints.maxHeight * 0.55).clamp(32.0, preferred)
            : preferred;
        return Semantics(
          liveRegion: true,
          label: label,
          child: ExcludeSemantics(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 8 : 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MimiMascot(scene: scene, size: size),
                      const SizedBox(height: 12),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          5,
                          (index) => Container(
                            width: 8,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            color: index.isEven
                                ? scheme.primary
                                : scheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MimiAvatar extends StatelessWidget {
  const MimiAvatar({
    super.key,
    this.image,
    this.radius = 20,
    this.label,
    this.backgroundColor,
  });

  final ImageProvider<Object>? image;
  final double radius;
  final String? label;
  final Color? backgroundColor;

  Widget _placeholder() => Image.asset(
    'assets/mimi/cute-v1/avatar-placeholder.png',
    cacheWidth: 64,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.none,
    excludeFromSemantics: true,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: label ?? (image == null ? '希希剪影預設頭像' : '個人頭像'),
      child: Container(
        width: radius * 2,
        height: radius * 2,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: backgroundColor ?? scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant, width: 2),
        ),
        child: image == null
            ? _placeholder()
            : Image(
                image: image!,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stack) => _placeholder(),
              ),
      ),
    );
  }
}
