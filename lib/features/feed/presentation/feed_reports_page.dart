import 'dart:convert';
import '../../../core/utils/picked_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/repositories/feed_repository.dart';
import '../../../core/utils/error_message.dart';
import 'feed_page.dart';

final _reports = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(feedSessionProvider);
  return ((await ref.watch(apiClientProvider).get('/admin/feed-reports')).data
          as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});

class FeedReportsPage extends ConsumerWidget {
  const FeedReportsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('動態檢舉審核')),
    body: ref
        .watch(_reports)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(_reports),
              child: Text('重新載入：${userFacingError(e)}'),
            ),
          ),
          data: (rows) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_reports);
              await ref.read(_reports.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (rows.isEmpty) const Text('目前沒有動態檢舉'),
                for (final r in rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${r['id']} · ${r['commentId'] == null ? '貼文' : '留言'} · ${r['reason']}',
                          ),
                          Text(r['details']?.toString() ?? ''),
                          const SizedBox(height: 8),
                          _ReportEvidence(value: r['evidence']),
                          Text('狀態：${r['status']}'),
                          if (r['status'] == 'pending')
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final action in ['remove', 'dismiss'])
                                  TextButton(
                                    onPressed: () async {
                                      if (!await feedConfirm(
                                        context,
                                        action == 'remove'
                                            ? '移除被檢舉的內容？'
                                            : '不處分並結案？',
                                      )) {
                                        return;
                                      }
                                      try {
                                        await ref
                                            .read(apiClientProvider)
                                            .post(
                                              '/admin/feed-reports/${r['id']}/review',
                                              data: {'action': action},
                                            );
                                        ref.invalidate(_reports);
                                      } catch (e) {
                                        if (context.mounted) {
                                          feedError(context, e);
                                        }
                                      }
                                    },
                                    child: Text(
                                      action == 'remove' ? '移除內容並結案' : '不處分並結案',
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
  );
}

class _ReportEvidence extends StatelessWidget {
  const _ReportEvidence({required this.value});
  final Object? value;
  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? data;
    try {
      final parsed = value is String ? jsonDecode(value as String) : value;
      if (parsed is Map) data = Map<String, dynamic>.from(parsed);
    } catch (_) {}
    if (data == null) return const Text('證據已到期或已清除');
    final images = [
      ...(data['images'] as List? ?? []).map((x) => x.toString()),
      if ((data['outfitImageUrl']?.toString() ?? '').isNotEmpty)
        data['outfitImageUrl'].toString(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data['body']?.toString() ?? ''),
        for (final url in images)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Image(
              image: pickedImageProvider(url)!,
              height: 200,
              fit: BoxFit.contain,
              errorBuilder: (_, e, st) => const Text('證據圖片已無法顯示'),
            ),
          ),
      ],
    );
  }
}
