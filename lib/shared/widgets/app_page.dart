import 'package:flutter/material.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: SizedBox.expand(
          child: ColoredBox(
            color: scheme.surface,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
