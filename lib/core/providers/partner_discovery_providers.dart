import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/partner_work.dart';
import '../models/same_work_user.dart';
import '../repositories/social_repository.dart';
import 'friendship_providers.dart';
import 'same_work_providers.dart';

final partnerDiscoverySessionProvider = Provider<int>((ref) {
  final client = ref.watch(apiClientProvider);
  void changed() {
    ref.invalidate(friendshipsProvider);
    ref.invalidate(sameWorkUsersProvider);
    ref.invalidateSelf();
  }

  client.sessionChanges.addListener(changed);
  ref.onDispose(() => client.sessionChanges.removeListener(changed));
  return client.sessionVersion;
});

class PartnerDiscoveryData<T> {
  const PartnerDiscoveryData({
    required this.items,
    this.nextOffset,
    this.loadingMore = false,
    this.moreError,
  });

  final List<T> items;
  final int? nextOffset;
  final bool loadingMore;
  final Object? moreError;
}

final partnerWorksProvider = AsyncNotifierProvider.autoDispose
    .family<
      PartnerWorksController,
      PartnerDiscoveryData<PartnerWork>,
      PartnerWorkQuery
    >(PartnerWorksController.new, retry: (retryCount, error) => null);

final partnerWorkUsersProvider = AsyncNotifierProvider.autoDispose
    .family<
      PartnerWorkUsersController,
      PartnerDiscoveryData<SameWorkUser>,
      String
    >(PartnerWorkUsersController.new, retry: (retryCount, error) => null);

abstract class PartnerDiscoveryController<T>
    extends AsyncNotifier<PartnerDiscoveryData<T>> {
  int _generation = 0;

  Future<PartnerDiscoveryData<T>> fetchPage(int offset);
  String itemId(T item);

  @override
  Future<PartnerDiscoveryData<T>> build() {
    ref.watch(partnerDiscoverySessionProvider);
    ref.watch(socialRepositoryProvider);
    _generation++;
    ref.onDispose(() => _generation++);
    return fetchPage(0);
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final offset = current?.nextOffset;
    if (current == null ||
        offset == null ||
        current.loadingMore ||
        state.isLoading) {
      return;
    }
    final generation = _generation;
    final client = ref.read(apiClientProvider);
    final session = client.sessionVersion;
    state = AsyncData(
      PartnerDiscoveryData(
        items: current.items,
        nextOffset: offset,
        loadingMore: true,
      ),
    );
    try {
      final next = await fetchPage(offset);
      if (!ref.mounted ||
          generation != _generation ||
          session != client.sessionVersion) {
        return;
      }
      final ids = current.items.map(itemId).toSet();
      state = AsyncData(
        PartnerDiscoveryData(
          items: [
            ...current.items,
            ...next.items.where((item) => ids.add(itemId(item))),
          ],
          nextOffset: next.nextOffset,
        ),
      );
    } catch (error) {
      if (!ref.mounted ||
          generation != _generation ||
          session != client.sessionVersion) {
        return;
      }
      state = AsyncData(
        PartnerDiscoveryData(
          items: current.items,
          nextOffset: offset,
          moreError: error,
        ),
      );
    }
  }
}

class PartnerWorksController extends PartnerDiscoveryController<PartnerWork> {
  PartnerWorksController(this.query);
  final PartnerWorkQuery query;

  @override
  String itemId(PartnerWork item) => item.id;

  @override
  Future<PartnerDiscoveryData<PartnerWork>> fetchPage(int offset) async {
    final page = await ref
        .read(socialRepositoryProvider)
        .fetchPartnerWorks(scope: query.scope, q: query.q, offset: offset);
    return PartnerDiscoveryData(items: page.items, nextOffset: page.nextOffset);
  }
}

class PartnerWorkUsersController
    extends PartnerDiscoveryController<SameWorkUser> {
  PartnerWorkUsersController(this.workId);
  final String workId;

  @override
  String itemId(SameWorkUser item) => item.userId;

  @override
  Future<PartnerDiscoveryData<SameWorkUser>> fetchPage(int offset) async {
    final page = await ref
        .read(socialRepositoryProvider)
        .fetchPartnerWorkUsers(workId, offset: offset);
    return PartnerDiscoveryData(items: page.items, nextOffset: page.nextOffset);
  }
}
