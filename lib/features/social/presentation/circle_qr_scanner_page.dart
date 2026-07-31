import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/repositories/social_repository.dart';
import '../../../shared/widgets/cos_ui.dart';
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
      appBar: AppBar(title: const Text('加入小圈圈')),
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
          CosScannerOverlay(
            icon: Icons.groups_2_outlined,
            title: '掃描小圈圈邀請',
            message: '對準朋友的小圈圈 QRCode，加入後就能一起約場與看集合訊號。',
            accentColor: Theme.of(context).colorScheme.primary,
            statusIcon: Icons.diversity_3_outlined,
            statusLabel: '小圈圈邀請模式',
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
