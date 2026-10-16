import 'package:coscircle/core/models/admin_sync_run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source names and outcomes stay independent', () {
    final blocked = AdminSyncRun.fromJson({
      'sourceKey': 'doujin-source',
      'status': 'failure',
      'errorCode': '403',
      'importedCount': 0,
    });
    final success = AdminSyncRun.fromJson({
      'sourceKey': 'acosta-source',
      'status': 'success',
      'importedCount': 2,
    });
    expect(blocked.sourceName, '同人誌中心');
    expect(blocked.resultLabel, '失敗 · 403');
    expect(success.sourceName, 'acosta!');
    expect(success.resultLabel, '成功 · 匯入 2 筆');
    expect(blocked.sourceGroup, isNot(success.sourceGroup));
  });
  test('historical mixed success is not proof of source success', () {
    final legacy = AdminSyncRun.fromJson({
      'sourceKey': 'doujin-events-daily',
      'status': 'success',
      'importedCount': 3,
    });
    expect(legacy.isLegacyAggregate, isTrue);
    expect(legacy.sourceName, '舊版混合來源');
    expect(legacy.resultLabel, '無法判定各來源');
    final edge = AdminSyncRun.fromJson({'sourceKey': 'doujin-events-edge'});
    final direct = AdminSyncRun.fromJson({'sourceKey': 'doujin-source'});
    expect(edge.sourceGroup, direct.sourceGroup);
  });
}
