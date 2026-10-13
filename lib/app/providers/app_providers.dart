import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/item_repository.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/template_repository.dart';
import '../../features/outings/application/session_providers.dart';
import '../../features/outings/application/template_providers.dart';

typedef AppDatabaseFactory = AppDatabase Function();

final appDatabaseFactoryProvider = Provider<AppDatabaseFactory>((ref) {
  return () => AppDatabase.defaults();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = ref.watch(appDatabaseFactoryProvider)();

  // Keep the database alive for the whole ProviderScope, then close it once.
  ref.onDispose(() {
    unawaited(database.close());
  });

  return database;
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(ref.watch(appDatabaseProvider));
});

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return ItemRepository(ref.watch(appDatabaseProvider));
});

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(ref.watch(appDatabaseProvider));
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(appDatabaseProvider));
});

final activeSessionsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(sessionRefreshProvider);
  return ref.watch(sessionRepositoryProvider).listActive();
});

final templatesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(templateRefreshProvider);
  return ref.watch(templateRepositoryProvider).listAll();
});

final recentTemplatesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(templateRefreshProvider);
  return ref.watch(templateRepositoryProvider).listRecentlyUsed(limit: 4);
});
