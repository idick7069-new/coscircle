import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

const legalVersion = '2026-10-28';

final legalRepositoryProvider = Provider<LegalRepository>((ref) {
  return LegalRepository(apiClient: ref.watch(apiClientProvider));
});

class LegalStatus {
  const LegalStatus({required this.version, required this.accepted});

  final String version;
  final bool accepted;

  factory LegalStatus.fromJson(Object? json) {
    if (json is! Map ||
        json['version'] != legalVersion ||
        json['accepted'] is! bool) {
      throw const FormatException('法律文件版本或回應格式不符');
    }
    return LegalStatus(
      version: json['version'] as String,
      accepted: json['accepted'] as bool,
    );
  }
}

class LegalRepository {
  LegalRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<LegalStatus> status(ApiSession session) async {
    session.checkActive();
    final response = await _apiClient.get('/me/legal', session: session);
    session.checkActive();
    return LegalStatus.fromJson(response.data);
  }

  Future<LegalStatus> accept(ApiSession session) async {
    session.checkActive();
    final response = await _apiClient.post(
      '/me/legal',
      session: session,
      data: {'version': legalVersion, 'accepted': true},
    );
    session.checkActive();
    final result = LegalStatus.fromJson(response.data);
    if (!result.accepted) throw const FormatException('尚未確認同意紀錄');
    return result;
  }
}
