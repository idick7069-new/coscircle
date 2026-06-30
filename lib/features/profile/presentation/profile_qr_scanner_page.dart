import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../shared/widgets/cos_ui.dart';

class ProfileQrScannerPage extends StatefulWidget {
  const ProfileQrScannerPage({super.key});

  @override
  State<ProfileQrScannerPage> createState() => _ProfileQrScannerPageState();
}

class _ProfileQrScannerPageState extends State<ProfileQrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('掃描個人 QRCode')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_handled) return;
              final value = capture.barcodes
                  .map((barcode) => barcode.rawValue?.trim() ?? '')
                  .where((value) => value.isNotEmpty)
                  .firstOrNull;
              final publicCode = _extractPublicCode(value);
              if (publicCode == null) return;
              _handled = true;
              context.replace('/profiles/$publicCode');
            },
          ),
          CosScannerOverlay(
            icon: Icons.qr_code_scanner,
            title: '掃描個人名片',
            message: '對準 CosCircle 個人 QRCode，確認對方坑單、照片牆與交流資訊。',
            accentColor: Theme.of(context).colorScheme.secondary,
          ),
        ],
      ),
    );
  }

  String? _extractPublicCode(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri != null) {
      if (uri.scheme == 'coscircle' &&
          uri.host == 'profiles' &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      final profileIndex = uri.pathSegments.indexOf('profiles');
      if (profileIndex >= 0 && profileIndex + 1 < uri.pathSegments.length) {
        return uri.pathSegments[profileIndex + 1];
      }
    }

    if (RegExp(r'^[a-zA-Z0-9_-]{8,80}$').hasMatch(text)) return text;
    return null;
  }
}
