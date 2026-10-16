import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_sync_job.dart';
import '../repositories/admin_repository.dart';

final adminSyncJobProvider =
    AsyncNotifierProvider.autoDispose<AdminSyncController, AdminSyncJob?>(
      AdminSyncController.new,
    );

class AdminSyncController extends AsyncNotifier<AdminSyncJob?> {
  Timer? _timer;
  bool _polling = false;

  @override
  Future<AdminSyncJob?> build() async {
    ref.onDispose(() => _timer?.cancel());
    final job = await ref.read(adminRepositoryProvider).fetchSyncJob('current');
    if (ref.mounted && job?.isRunning == true) _watch(job!.id);
    return job;
  }

  Future<void> start() async {
    if (state.isLoading || state.value?.isRunning == true) return;
    state = const AsyncLoading();
    try {
      final job = await ref.read(adminRepositoryProvider).syncDoujinEvents();
      if (!ref.mounted) return;
      state = AsyncData(job);
      if (job.isRunning) _watch(job.id);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    }
  }

  void _watch(String id) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_polling || !ref.mounted) return;
      _polling = true;
      try {
        final job = await ref.read(adminRepositoryProvider).fetchSyncJob(id);
        if (!ref.mounted) return;
        state = AsyncData(job);
        if (job?.isRunning != true) _timer?.cancel();
      } catch (error, stack) {
        _timer?.cancel();
        if (ref.mounted) state = AsyncError(error, stack);
      } finally {
        _polling = false;
      }
    });
  }
}
