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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CosIconBubble(icon: Icons.flag_circle, color: scheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      meetup.circleName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      meetup.description.isEmpty
                          ? '集合點已設定'
                          : meetup.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              CosBadge(
                label: timeText,
                icon: Icons.schedule,
                highlighted: true,
                color: scheme.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onNavigate,
                  icon: const Icon(Icons.navigation),
                  label: const Text('導航'),
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: '編輯集合',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                ),
              ],
              if (onCancel != null) ...[
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: '取消集合',
                  onPressed: onCancel,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
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
    final scheme = Theme.of(context).colorScheme;
    if (request.isRequester && request.status != RecognitionStatus.pending) {
      return CosCard(
        child: Row(
          children: [
            CosIconBubble(icon: Icons.mark_chat_read, color: scheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${request.targetNickname} 回覆',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    request.responseMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            CosBadge(
              label: '認親回覆',
              icon: Icons.waving_hand_outlined,
              color: scheme.secondary,
            ),
          ],
        ),
      );
    }

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
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              CosBadge(
                label: '認親訊號',
                icon: Icons.waving_hand_outlined,
                highlighted: true,
                color: scheme.primary,
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
