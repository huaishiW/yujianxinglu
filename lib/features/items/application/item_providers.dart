import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../data/local/app_database.dart';
import 'location_providers.dart';

final itemDetailProvider = FutureProvider.autoDispose.family<Item, int>((
  ref,
  itemId,
) {
  ref.watch(locationBrowserRefreshProvider);
  return ref.watch(itemRepositoryProvider).getById(itemId);
});

final itemLocationPathProvider = FutureProvider.autoDispose.family<String, int>(
  (ref, itemId) {
    ref.watch(locationBrowserRefreshProvider);
    return ref.watch(itemRepositoryProvider).fullLocationPath(itemId);
  },
);

final locationPathProvider = FutureProvider.autoDispose.family<String, int>((
  ref,
  locationId,
) {
  ref.watch(locationBrowserRefreshProvider);
  return ref.watch(locationRepositoryProvider).fullPath(locationId);
});

final itemSearchProvider = FutureProvider.autoDispose
    .family<List<Item>, String>((ref, keyword) {
      ref.watch(locationBrowserRefreshProvider);
      return ref.watch(itemRepositoryProvider).searchByName(keyword);
    });
