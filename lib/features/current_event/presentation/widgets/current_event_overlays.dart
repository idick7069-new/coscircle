import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/meetup_point.dart';
import '../../../../core/models/recognition_request.dart';
import '../../../../shared/widgets/cos_ui.dart';

class MeetupNoticeCard extends StatelessWidget {
  const MeetupNoticeCard({
    super.key,
    required this.meetup,
    required this.onNavigate,
    this.onEdit,
    this.onCancel,
  });

  final MeetupPoint meetup;
  final VoidCallback onNavigate;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat('HH:mm').format(meetup.meetAt);
    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CosIconBubble(icon: Icons.flag_circle, color: scheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${meetup.circleName} $timeText 集合',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  meetup.description.isEmpty ? '集合點已設定' : meetup.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation),
                label: const Text('導航'),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: '編輯集合',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                ),
              if (onCancel != null)
                IconButton(
                  tooltip: '取消集合',
                  onPressed: onCancel,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class RecognitionNoticeCard extends StatelessWidget {
  const RecognitionNoticeCard({
    super.key,
    required this.request,
    required this.onCome,
    required this.onBusy,
  });

  final RecognitionRequest request;
  final VoidCallback onCome;
  final VoidCallback onBusy;

  @override
  Widget build(BuildContext context) {
    if (request.isRequester && request.status != RecognitionStatus.pending) {
      return CosCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: const CosIconBubble(icon: Icons.mark_chat_read),
          title: Text(
            '${request.targetNickname} 回覆：${request.responseMessage}',
          ),
          subtitle: const Text('認親回覆通知'),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return CosCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CosIconBubble(icon: Icons.waving_hand, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${request.requesterNickname} 要過來認親',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(onPressed: onCome, child: const Text('快來')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onBusy,
                  child: const Text('當前不方便'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
