import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';

void main() {
  AppDatabase? database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    final opened = database;
    database = null;
    await opened?.close();
  });

  int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<int> insertLocation(
    AppDatabase db, {
    required String name,
    int? parentId,
  }) {
    final timestamp = now();
    return db
        .into(db.locations)
        .insert(
          LocationsCompanion(
            name: Value(name),
            parentId: Value(parentId),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
  }

  Future<int> insertItem(
    AppDatabase db, {
    required String name,
    required int locationId,
    int quantity = 1,
  }) {
    final timestamp = now();
    return db
        .into(db.items)
        .insert(
          ItemsCompanion(
            name: Value(name),
            quantity: Value(quantity),
            locationId: Value(locationId),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
  }

  Future<int> insertTemplate(AppDatabase db, {String name = '出门模板'}) {
    final timestamp = now();
    return db
        .into(db.outgoingTemplates)
        .insert(
          OutgoingTemplatesCompanion(
            name: Value(name),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
  }

  Future<int> insertSession(AppDatabase db, {String status = 'IN_PROGRESS'}) {
    final timestamp = now();
    return db
        .into(db.outgoingSessions)
        .insert(
          OutgoingSessionsCompanion(
            title: const Value('本次出门'),
            status: Value(status),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
            completedAt: Value(status == 'COMPLETED' ? timestamp : null),
          ),
        );
  }

  test('creates all six tables with schema version 1', () async {
    final db = database!;

    expect(db.schemaVersion, 1);

    final rows = await db.customSelect('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ORDER BY name
    ''').get();
    final names = rows.map((row) => row.read<String>('name')).toList();

    expect(
      names,
      containsAll(<String>[
        'locations',
        'items',
        'outgoing_templates',
        'template_items',
        'outgoing_sessions',
        'session_items',
      ]),
    );
  });

  test('enables SQLite foreign keys for every opened connection', () async {
    final row = await database!.customSelect('PRAGMA foreign_keys').getSingle();

    expect(row.read<int>('foreign_keys'), 1);
  });

  test('allows basic CRUD across all six tables', () async {
    final db = database!;
    final rootId = await insertLocation(db, name: '卧室');
    final itemId = await insertItem(
      db,
      name: '充电宝',
      locationId: rootId,
      quantity: 2,
    );
    final templateId = await insertTemplate(db);

    final templateItemId = await db
        .into(db.templateItems)
        .insert(
          TemplateItemsCompanion(
            templateId: Value(templateId),
            itemType: const Value('REGISTERED_ITEM'),
            itemId: Value(itemId),
            requiredQuantity: const Value(1),
            sortOrder: const Value(0),
          ),
        );
    final sessionId = await insertSession(db);
    final sessionItemId = await db
        .into(db.sessionItems)
        .insert(
          SessionItemsCompanion(
            sessionId: Value(sessionId),
            itemType: const Value('REGISTERED_ITEM'),
            itemId: Value(itemId),
            nameSnapshot: const Value('充电宝'),
            locationSnapshot: const Value('卧室'),
            requiredQuantity: const Value(1),
            checked: const Value(0),
            checkedAt: const Value(null),
            sortOrder: const Value(0),
          ),
        );

    expect(
      await (db.select(
        db.locations,
      )..where((t) => t.id.equals(rootId))).getSingle().then((row) => row.name),
      '卧室',
    );
    expect(
      await (db.select(db.items)..where((t) => t.id.equals(itemId)))
          .getSingle()
          .then((row) => row.quantity),
      2,
    );
    expect(
      await (db.select(db.templateItems)
            ..where((t) => t.id.equals(templateItemId)))
          .getSingle()
          .then((row) => row.itemId),
      itemId,
    );
    expect(
      await (db.select(db.sessionItems)
            ..where((t) => t.id.equals(sessionItemId)))
          .getSingle()
          .then((row) => row.sessionId),
      sessionId,
    );

    await (db.update(db.items)..where((t) => t.id.equals(itemId))).write(
      const ItemsCompanion(name: Value('新充电宝')),
    );
    expect(
      await (db.select(
        db.items,
      )..where((t) => t.id.equals(itemId))).getSingle().then((row) => row.name),
      '新充电宝',
    );

    await (db.delete(
      db.outgoingSessions,
    )..where((t) => t.id.equals(sessionId))).go();
    expect(
      await (db.select(
        db.sessionItems,
      )..where((t) => t.sessionId.equals(sessionId))).get(),
      isEmpty,
    );
  });

  test('rejects duplicate top-level and sibling location names', () async {
    final db = database!;
    final rootId = await insertLocation(db, name: '卧室');

    await expectLater(insertLocation(db, name: '卧室'), throwsA(anything));

    await insertLocation(db, name: '书桌', parentId: rootId);
    await expectLater(
      insertLocation(db, name: '书桌', parentId: rootId),
      throwsA(anything),
    );

    final otherRootId = await insertLocation(db, name: '书房');
    await expectLater(
      insertLocation(db, name: '书桌', parentId: otherRootId),
      completes,
    );
  });

  test(
    'enforces foreign keys and restricts deleting referenced locations',
    () async {
      final db = database!;
      final rootId = await insertLocation(db, name: '卧室');

      await expectLater(
        insertItem(db, name: '无效物品', locationId: rootId + 1000),
        throwsA(anything),
      );

      await insertItem(db, name: '鼠标', locationId: rootId);
      await expectLater(
        (db.delete(db.locations)..where((t) => t.id.equals(rootId))).go(),
        throwsA(anything),
      );
    },
  );

  test('enforces positive quantities and item type constraints', () async {
    final db = database!;
    final rootId = await insertLocation(db, name: '卧室');

    await expectLater(
      insertItem(db, name: '数量为零', locationId: rootId, quantity: 0),
      throwsA(anything),
    );

    final itemId = await insertItem(db, name: '耳机', locationId: rootId);
    final templateId = await insertTemplate(db);

    await expectLater(
      db
          .into(db.templateItems)
          .insert(
            TemplateItemsCompanion(
              templateId: Value(templateId),
              itemType: const Value('REGISTERED_ITEM'),
              itemId: Value(itemId),
              requiredQuantity: const Value(0),
              sortOrder: const Value(0),
            ),
          ),
      throwsA(anything),
    );

    await expectLater(
      db
          .into(db.templateItems)
          .insert(
            TemplateItemsCompanion(
              templateId: Value(templateId),
              itemType: const Value('REGISTERED_ITEM'),
              requiredQuantity: const Value(1),
              sortOrder: const Value(0),
            ),
          ),
      throwsA(anything),
    );
  });

  test(
    'rejects duplicate registered items in one template or session',
    () async {
      final db = database!;
      final rootId = await insertLocation(db, name: '卧室');
      final itemId = await insertItem(db, name: '数据线', locationId: rootId);
      final templateId = await insertTemplate(db);

      final templateEntry = TemplateItemsCompanion(
        templateId: Value(templateId),
        itemType: const Value('REGISTERED_ITEM'),
        itemId: Value(itemId),
        requiredQuantity: const Value(1),
        sortOrder: const Value(0),
      );
      await db.into(db.templateItems).insert(templateEntry);
      await expectLater(
        db.into(db.templateItems).insert(templateEntry),
        throwsA(anything),
      );

      final sessionId = await insertSession(db);
      final sessionEntry = SessionItemsCompanion(
        sessionId: Value(sessionId),
        itemType: const Value('REGISTERED_ITEM'),
        itemId: Value(itemId),
        nameSnapshot: const Value('数据线'),
        requiredQuantity: const Value(1),
        checked: const Value(0),
        checkedAt: const Value(null),
        sortOrder: const Value(0),
      );
      await db.into(db.sessionItems).insert(sessionEntry);
      await expectLater(
        db.into(db.sessionItems).insert(sessionEntry),
        throwsA(anything),
      );
    },
  );

  test('closes an isolated database cleanly', () async {
    final opened = database!;
    database = null;

    await opened.close();
  });
}
