import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/friendship.dart';
import '../repositories/social_repository.dart';

final friendshipsProvider = FutureProvider.autoDispose<List<Friendship>>((ref) {
  return ref.watch(socialRepositoryProvider).fetchFriendships();
});
