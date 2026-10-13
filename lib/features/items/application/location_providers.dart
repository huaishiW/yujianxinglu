import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../app/providers/app_providers.dart';

final locationChildrenProvider = FutureProvider.autoDispose
    .family<List<Location>, int?>((ref, parentId) {
      return ref.watch(locationRepositoryProvider).listChildren(parentId);
    });
