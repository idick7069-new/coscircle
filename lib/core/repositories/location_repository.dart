import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/meetup_point.dart';
import '../models/recognition_request.dart';
import '../models/shared_location.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return ApiLocationRepository(apiClient: ref.watch(apiClientProvider));
});

abstract class LocationRepository {
  Future<List<SharedLocation>> fetchSharedLocations(String eventId);
  Future<List<MeetupPoint>> fetchMeetups(String eventId);
  Future<List<RecognitionRequest>> fetchRecognitions(String eventId);
  Future<void> shareLocation({
    required String eventId,
    required int dayIndex,
    required double latitude,
    required double longitude,
    required String visibility,
    required int expiresInMinutes,
  });
  Future<void> stopSharingLocation(String eventId);
  Future<void> updateSharedLocation({
    required String eventId,
    required int dayIndex,
    required double latitude,
    required double longitude,
  });
  Future<void> createMeetup({
    required String eventId,
    required String circleId,
    required double latitude,
    required double longitude,
    required String description,
    required DateTime meetAt,
  });
  Future<void> updateMeetup({
    required String eventId,
    required String meetupId,
    required String circleId,
    required double latitude,
    required double longitude,
    required String description,
    required DateTime meetAt,
  });
  Future<void> deleteMeetup({
    required String eventId,
    required String meetupId,
  });
  Future<void> requestRecognition({
    required String eventId,
    required int dayIndex,
    required String targetUserId,
  });
  Future<void> respondRecognition({
    required String requestId,
    required RecognitionStatus status,
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
  Future<List<MeetupPoint>> fetchMeetups(String eventId) async {
    final response = await _apiClient.get('/events/$eventId/meetups');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => MeetupPoint.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<RecognitionRequest>> fetchRecognitions(String eventId) async {
    final response = await _apiClient.get('/events/$eventId/recognitions');
    final rows = response.data as List<dynamic>;
    return rows
        .map((row) => RecognitionRequest.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> shareLocation({
    required String eventId,
    required int dayIndex,
    required double latitude,
    required double longitude,
    required String visibility,
    required int expiresInMinutes,
  }) async {
    await _apiClient.put(
      '/events/$eventId/location',
      data: {
        'dayIndex': dayIndex,
        'latitude': latitude,
        'longitude': longitude,
        'visibility': visibility,
        'expiresInMinutes': expiresInMinutes,
      },
    );
  }

  @override
  Future<void> stopSharingLocation(String eventId) async {
    await _apiClient.delete('/events/$eventId/location');
  }

  @override
  Future<void> updateSharedLocation({
    required String eventId,
    required int dayIndex,
    required double latitude,
    required double longitude,
  }) async {
    await _apiClient.put(
      '/events/$eventId/location/coordinates',
      data: {
        'dayIndex': dayIndex,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
  }

  @override
  Future<void> createMeetup({
    required String eventId,
    required String circleId,
    required double latitude,
    required double longitude,
    required String description,
    required DateTime meetAt,
  }) async {
    await _apiClient.post(
      '/events/$eventId/meetups',
      data: {
        'circleId': circleId,
        'latitude': latitude,
        'longitude': longitude,
        'description': description,
        'meetAt': meetAt.toIso8601String(),
      },
    );
  }

  @override
  Future<void> updateMeetup({
    required String eventId,
    required String meetupId,
    required String circleId,
    required double latitude,
    required double longitude,
    required String description,
    required DateTime meetAt,
  }) async {
    await _apiClient.put(
      '/events/$eventId/meetups/$meetupId',
      data: {
        'circleId': circleId,
        'latitude': latitude,
        'longitude': longitude,
        'description': description,
        'meetAt': meetAt.toIso8601String(),
      },
    );
  }

  @override
  Future<void> deleteMeetup({
    required String eventId,
    required String meetupId,
  }) async {
    await _apiClient.delete('/events/$eventId/meetups/$meetupId');
  }

  @override
  Future<void> requestRecognition({
    required String eventId,
    required int dayIndex,
    required String targetUserId,
  }) async {
    await _apiClient.post(
      '/events/$eventId/recognitions',
      data: {'targetUserId': targetUserId, 'dayIndex': dayIndex},
    );
  }

  @override
  Future<void> respondRecognition({
    required String requestId,
    required RecognitionStatus status,
  }) async {
    await _apiClient.post(
      '/recognitions/$requestId/respond',
      data: {'status': status.value},
    );
  }
}
