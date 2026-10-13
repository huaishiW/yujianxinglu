import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_items_assistant/app/providers/app_providers.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';

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
}
