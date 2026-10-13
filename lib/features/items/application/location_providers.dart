import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../app/providers/app_providers.dart';

class LocationBrowserRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state += 1;
}

final locationBrowserRefreshProvider =
    NotifierProvider<LocationBrowserRefresh, int>(LocationBrowserRefresh.new);

final locationChildrenProvider = FutureProvider.autoDispose
    .family<List<Location>, int?>((ref, parentId) {
      ref.watch(locationBrowserRefreshProvider);
      return ref.watch(locationRepositoryProvider).listChildren(parentId);
    });

final locationDirectItemsProvider = FutureProvider.autoDispose
    .family<List<Item>, int>((ref, locationId) {
      ref.watch(locationBrowserRefreshProvider);
      return ref.watch(itemRepositoryProvider).listByLocation(locationId);
    });
