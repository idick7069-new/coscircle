import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/same_work_user.dart';
import '../repositories/social_repository.dart';

final sameWorkUsersProvider =
    AsyncNotifierProvider.autoDispose<SameWorkUsersController, SameWorkPage>(
      SameWorkUsersController.new,
    );

class SameWorkUsersController extends AsyncNotifier<SameWorkPage> {
  int _generation = 0;
  bool _loadingMore = false;

  @override
  Future<SameWorkPage> build() {
    _generation++;
    return ref.watch(socialRepositoryProvider).fetchSameWorkUsers();
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final offset = current?.nextOffset;
    if (current == null || offset == null || _loadingMore) return;
    final generation = _generation;
    _loadingMore = true;
    try {
      final next = await ref
          .read(socialRepositoryProvider)
          .fetchSameWorkUsers(offset: offset);
      if (!ref.mounted || generation != _generation) return;
      final ids = current.items.map((item) => item.userId).toSet();
      state = AsyncData(
        SameWorkPage(
          items: [
            ...current.items,
            ...next.items.where((item) => ids.add(item.userId)),
          ],
          nextOffset: next.nextOffset,
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }
}
