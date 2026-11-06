import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

final accountSafetyRepositoryProvider = Provider(
  (ref) => AccountSafetyRepository(ref.watch(apiClientProvider)),
);

class AccountSafetyRepository {
  AccountSafetyRepository(this.api);

  final ApiClient api;

  Future<List<String>> loginMethods(ApiSession session) async {
    final response = await api.get('/me/auth-identities', session: session);
    session.checkActive();
    return (response.data as List)
        .map((row) => (row as Map)['provider'].toString())
        .toList();
  }

  Future<String> accountLabel(ApiSession session) async {
    final response = await api.get('/me', session: session);
    session.checkActive();
    final data = response.data as Map;
    final name = data['nickname']?.toString() ?? 'CosCircle 使用者';
    final identifier =
        data['email']?.toString() ?? data['publicCode']?.toString() ?? '';
    return identifier.isEmpty ? name : '$name（$identifier）';
  }

  Future<void> deleteAccount({
    required ApiSession session,
    String? password,
    String? lineAccessToken,
  }) async {
    await api.post(
      '/me/delete-account',
      session: session,
      data: {
        'confirmation': 'DELETE',
        if (password != null) 'password': password,
        if (lineAccessToken != null) 'lineAccessToken': lineAccessToken,
      },
      receiveTimeout: const Duration(seconds: 30),
    );
    session.checkActive();
  }
}
