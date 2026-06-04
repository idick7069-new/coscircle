import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

final submissionRepositoryProvider = Provider<SubmissionRepository>((ref) {
  return SubmissionRepository(apiClient: ref.watch(apiClientProvider));
});

class SubmissionRepository {
  SubmissionRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<void> submitEvent({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String venue,
    required String detailedAddress,
    required String description,
  }) async {
    await _apiClient.post(
      '/events/submissions',
      data: {
        'name': name,
        'startDate': _dateOnly(startDate),
        'endDate': _dateOnly(endDate),
        'venue': venue,
        'detailedAddress': detailedAddress,
        'description': description,
      },
    );
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
