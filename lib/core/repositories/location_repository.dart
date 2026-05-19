import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/shared_location.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return ApiLocationRepository(apiClient: ref.watch(apiClientProvider));
});

abstract class LocationRepository {
  Future<List<SharedLocation>> fetchSharedLocations(String eventId);
  Future<void> shareLocation({
    required String eventId,
    required double latitude,
    required double longitude,
  });
}

class ApiLocationRepository implements LocationRepository {
  ApiLocationRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<List<SharedLocation>> fetchSharedLocations(String eventId) async {
    final response = await _apiClient.get('/events/$eventId/locations');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => SharedLocation.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> shareLocation({
    required String eventId,
    required double latitude,
    required double longitude,
  }) async {
    await _apiClient.put(
      '/events/$eventId/location',
      data: {'latitude': latitude, 'longitude': longitude},
    );
  }
}
