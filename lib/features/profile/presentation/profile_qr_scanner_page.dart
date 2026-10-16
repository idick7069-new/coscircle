import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/event_providers.dart';
import '../../../core/models/event_day_item.dart';

import '../../../shared/widgets/cos_ui.dart';
import '../../../core/utils/app_qr_code.dart';

class ProfileQrScannerPage extends ConsumerStatefulWidget {
  const ProfileQrScannerPage({super.key});

  @override
  ConsumerState<ProfileQrScannerPage> createState() =>
      _ProfileQrScannerPageState();
}

class _ProfileQrScannerPageState extends ConsumerState<ProfileQrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('交換個人名片')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_handled) return;
              final value = capture.barcodes
                  .map((barcode) => barcode.rawValue?.trim() ?? '')
                  .where((value) => value.isNotEmpty)
                  .firstOrNull;
              final publicCode = extractAppQrCode(
                value,
                'profiles',
                minimumLength: 8,
              );
              if (publicCode == null) return;
              _handled = true;
              final target = ref.read(selectedCurrentEventTargetProvider);
              final days = expandEventDays(
                ref.read(eventsProvider).asData?.value ?? [],
              );
              final now = DateTime.now();
              final day = days
                  .where(
                    (day) =>
                        day.event.id == target?.eventId &&
                        day.dayIndex == target?.dayIndex &&
                        day.date == DateTime(now.year, now.month, now.day),
                  )
                  .firstOrNull;
              context.replace(
                Uri(
                  path: '/profiles/$publicCode',
                  queryParameters: day == null
                      ? null
                      : {
                          'eventId': day.event.id,
                          'dayIndex': '${day.dayIndex}',
                        },
                ).toString(),
              );
            },
          ),
          CosScannerOverlay(
            icon: Icons.qr_code_scanner,
            title: '掃描個人名片',
            message: '對準 CosCircle 個人 QRCode，確認對方坑單、照片牆與交流資訊。',
            accentColor: Theme.of(context).colorScheme.secondary,
            statusIcon: Icons.badge_outlined,
            statusLabel: '名片交換模式',
          ),
        ],
      ),
    );
  }
}
