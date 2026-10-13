import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_items_assistant/app/providers/app_providers.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';
import 'package:personal_items_assistant/features/items/application/location_providers.dart';

class _TrackingDatabase extends AppDatabase {
  _TrackingDatabase(super.executor);

  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
    await super.close();
  }
}

void main() {
  late _TrackingDatabase database;
  late ProviderContainer container;
  late int createCalls;
  var containerDisposed = false;

  setUp(() {
    database = _TrackingDatabase(NativeDatabase.memory());
    createCalls = 0;
    containerDisposed = false;
    container = ProviderContainer(
      overrides: [
        appDatabaseFactoryProvider.overrideWithValue(() {
          createCalls += 1;
          return database;
        }),
      ],
    );
  });

  tearDown(() async {
    if (!containerDisposed) {
      container.dispose();
    }
    await Future<void>.delayed(Duration.zero);
    if (database.closeCalls == 0) {
      await database.close();
    }
  });

  test('four Repository Provider share one injected AppDatabase', () {
    final resolvedDatabase = container.read(appDatabaseProvider);

    expect(
      identical(
        container.read(locationRepositoryProvider).db,
        resolvedDatabase,
      ),
      isTrue,
    );
    expect(
      identical(container.read(itemRepositoryProvider).db, resolvedDatabase),
      isTrue,
    );
    expect(
      identical(
        container.read(templateRepositoryProvider).db,
        resolvedDatabase,
      ),
      isTrue,
    );
    expect(
      identical(container.read(sessionRepositoryProvider).db, resolvedDatabase),
      isTrue,
    );
  });

  test(
    'database is created once and closed when the container is disposed',
    () {
      expect(identical(container.read(appDatabaseProvider), database), isTrue);
      expect(identical(container.read(appDatabaseProvider), database), isTrue);
      expect(createCalls, 1);
      expect(database.closeCalls, 0);

      container.dispose();
      containerDisposed = true;

      expect(database.closeCalls, 1);
    },
  );

  test('location providers query direct children and items from the shared database', () async {
    final locationRepository = container.read(locationRepositoryProvider);
    final itemRepository = container.read(itemRepositoryProvider);
    final rootId = await locationRepository.create(name: '卧室');
    final childId = await locationRepository.create(
      name: '书桌',
      parentId: rootId,
    );
    final directItemId = await itemRepository.create(
      name: '根位置物品',
      locationId: rootId,
    );
    await itemRepository.create(name: '子位置物品', locationId: childId);

    final children = await container.read(
      locationChildrenProvider(rootId).future,
    );
    final directItems = await container.read(
      locationDirectItemsProvider(rootId).future,
    );

    expect(children.map((location) => location.id), [childId]);
    expect(directItems.map((item) => item.id), [directItemId]);
    expect(
      identical(
        container.read(locationRepositoryProvider).db,
        container.read(appDatabaseProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(itemRepositoryProvider).db,
        container.read(appDatabaseProvider),
      ),
      isTrue,
    );
  });
}
