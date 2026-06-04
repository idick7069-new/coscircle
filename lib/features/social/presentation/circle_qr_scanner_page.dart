import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/repositories/social_repository.dart';
import 'social_page.dart';

class CircleQrScannerPage extends ConsumerStatefulWidget {
  const CircleQrScannerPage({super.key});

  @override
  ConsumerState<CircleQrScannerPage> createState() =>
      _CircleQrScannerPageState();
}

class _CircleQrScannerPageState extends ConsumerState<CircleQrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('掃描小圈圈 QRCode')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) async {
              if (_handled) return;
              final value = capture.barcodes
                  .map((barcode) => barcode.rawValue?.trim() ?? '')
                  .where((value) => value.isNotEmpty)
                  .firstOrNull;
              final invite = _extractInvite(value);
              if (invite == null) return;
              _handled = true;
              try {
                await ref.read(socialRepositoryProvider).joinCircle(invite);
                ref.invalidate(circlesProvider);
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已加入小圈圈')));
                context.go('/');
              } catch (error) {
                _handled = false;
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('加入失敗：$error')));
              }
            },
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Card(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.92),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text('請掃描小圈圈邀請 QRCode', textAlign: TextAlign.center),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _extractInvite(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri != null) {
      final joinIndex = uri.pathSegments.indexOf('join');
      if (joinIndex >= 0 && joinIndex + 1 < uri.pathSegments.length) {
        return uri.pathSegments[joinIndex + 1];
      }
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{4,80}$').hasMatch(text)) return text;
    return null;
  }
}
