import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/repositories/social_repository.dart';
import '../../../core/utils/app_qr_code.dart';
import '../../../core/utils/error_message.dart';
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
              final invite = extractAppQrCode(value, 'join');
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('加入失敗：${userFacingError(error)}')),
                );
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
}
