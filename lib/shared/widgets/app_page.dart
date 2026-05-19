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
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
