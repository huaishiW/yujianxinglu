import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/session_repository.dart';
import '../../items/application/location_providers.dart';

class SessionRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state += 1;
}

final sessionRefreshProvider = NotifierProvider<SessionRefreshNotifier, int>(
  SessionRefreshNotifier.new,
);

final sessionListProvider = FutureProvider.autoDispose<List<OutgoingSession>>((
  ref,
) {
  ref.watch(sessionRefreshProvider);
  ref.watch(locationBrowserRefreshProvider);
  final repo = ref.watch(sessionRepositoryProvider);
  return repo.listActive();
});

final sessionDetailProvider = FutureProvider.autoDispose
    .family<SessionDetail, int>((ref, sessionId) {
      ref.watch(sessionRefreshProvider);
      ref.watch(locationBrowserRefreshProvider);
      return ref.watch(sessionRepositoryProvider).getDetail(sessionId);
    });

final sessionShortagesProvider = FutureProvider.autoDispose
    .family<List<SessionQuantityShortage>, int>((ref, sessionId) {
      ref.watch(sessionRefreshProvider);
      ref.watch(locationBrowserRefreshProvider);
      return ref
          .watch(sessionRepositoryProvider)
          .listQuantityShortages(sessionId);
    });
