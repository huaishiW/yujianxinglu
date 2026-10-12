import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';
import 'package:personal_items_assistant/data/repositories/item_repository.dart';

void main() {
  late AppDatabase database;
  late ItemRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ItemRepository(database);
  });

  tearDown(() => database.close());

  int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<int> insertLocation(String name, {int? parentId}) {
    final timestamp = now();
    return database
        .into(database.locations)
        .insert(
          LocationsCompanion(
            name: Value(name),
            parentId: Value(parentId),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
  }

  Future<int> insertTemplate({String name = '出门模板'}) {
    final timestamp = now();
    return database
        .into(database.outgoingTemplates)
        .insert(
          OutgoingTemplatesCompanion(
            name: Value(name),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
          ),
        );
  }

  Future<int> insertSession({String status = 'IN_PROGRESS'}) {
    final timestamp = now();
    return database
        .into(database.outgoingSessions)
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

  Future<int> insertTemplateItem({
    required int templateId,
    int? itemId,
    String itemType = 'REGISTERED_ITEM',
    String? textName,
    int requiredQuantity = 1,
    int sortOrder = 0,
  }) {
    return database
        .into(database.templateItems)
        .insert(
          TemplateItemsCompanion(
            templateId: Value(templateId),
            itemType: Value(itemType),
            itemId: Value(itemId),
            textName: Value(textName),
            requiredQuantity: Value(requiredQuantity),
            sortOrder: Value(sortOrder),
          ),
        );
  }

  Future<int> insertSessionItem({
    required int sessionId,
    int? itemId,
    String itemType = 'REGISTERED_ITEM',
    String? textName,
    required String nameSnapshot,
    String? locationSnapshot,
    int requiredQuantity = 1,
    int checked = 0,
    int? checkedAt,
    int sortOrder = 0,
  }) {
    return database
        .into(database.sessionItems)
        .insert(
          SessionItemsCompanion(
            sessionId: Value(sessionId),
            itemType: Value(itemType),
            itemId: Value(itemId),
            textName: Value(textName),
            nameSnapshot: Value(nameSnapshot),
            locationSnapshot: Value(locationSnapshot),
            requiredQuantity: Value(requiredQuantity),
            checked: Value(checked),
            checkedAt: Value(checkedAt),
            sortOrder: Value(sortOrder),
          ),
        );
  }

  Matcher itemError(ItemRepositoryErrorCode code) {
    return throwsA(
      isA<ItemRepositoryException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
  }

  test('adds an item and preserves its fields', () async {
    final locationId = await insertLocation('卧室');

    final itemId = await repository.create(
      name: '  充电宝  ',
      quantity: 2,
      locationId: locationId,
      category: '电子',
      note: '短途出门使用',
    );

    final item = await repository.getById(itemId);
    expect(item.id, itemId);
    expect(item.name, '充电宝');
    expect(item.quantity, 2);
    expect(item.locationId, locationId);
    expect(item.category, '电子');
    expect(item.note, '短途出门使用');
    expect(item.createdAt, greaterThan(0));
    expect(item.updatedAt, greaterThanOrEqualTo(item.createdAt));
  });

  test('allows multiple items with the same name and distinct ids', () async {
    final firstLocationId = await insertLocation('卧室');
    final secondLocationId = await insertLocation('书房');

    final firstId = await repository.create(
      name: '数据线',
      locationId: firstLocationId,
    );
    final secondId = await repository.create(
      name: '数据线',
      locationId: secondLocationId,
    );

    expect(firstId, isNot(secondId));
    expect((await repository.getById(firstId)).name, '数据线');
    expect((await repository.getById(secondId)).name, '数据线');
  });

  test('rejects blank names and invalid quantities', () async {
    final locationId = await insertLocation('卧室');

    await expectLater(
      repository.create(name: '   ', locationId: locationId),
      itemError(ItemRepositoryErrorCode.invalidName),
    );

    for (final quantity in [0, -1]) {
      await expectLater(
        repository.create(
          name: '无效数量',
          quantity: quantity,
          locationId: locationId,
        ),
        itemError(ItemRepositoryErrorCode.invalidQuantity),
      );
    }
  });

  test('rejects a missing location when creating an item', () async {
    await expectLater(
      repository.create(name: '无位置物品', locationId: 9999),
      itemError(ItemRepositoryErrorCode.locationNotFound),
    );
    expect(await repository.searchByName('无位置物品'), isEmpty);
  });

  test(
    'finds items by id, direct location, and complete location path',
    () async {
      final bedroomId = await insertLocation('卧室');
      final deskId = await insertLocation('书桌', parentId: bedroomId);
      final rootItemId = await repository.create(
        name: '根位置物品',
        locationId: bedroomId,
      );
      final childItemId = await repository.create(
        name: '抽屉物品',
        locationId: deskId,
      );

      expect((await repository.getById(rootItemId)).id, rootItemId);
      expect(
        (await repository.listByLocation(bedroomId)).map((item) => item.id),
        [rootItemId],
      );
      expect((await repository.listByLocation(deskId)).map((item) => item.id), [
        childItemId,
      ]);
      expect(await repository.fullLocationPath(childItemId), '卧室 / 书桌');
    },
  );

  test('searches by name with stable results and keeps item ids', () async {
    final locationId = await insertLocation('卧室');
    final firstId = await repository.create(
      name: '数据线',
      locationId: locationId,
    );
    final secondId = await repository.create(
      name: '旅行数据线',
      locationId: locationId,
    );
    final thirdId = await repository.create(name: '耳机', locationId: locationId);

    final firstSearch = await repository.searchByName('数据');
    final secondSearch = await repository.searchByName('数据');

    expect(firstSearch.map((item) => item.id), [firstId, secondId]);
    expect(
      secondSearch.map((item) => item.id),
      firstSearch.map((item) => item.id),
    );
    expect((await repository.searchByName('')).map((item) => item.id), [
      firstId,
      secondId,
      thirdId,
    ]);
  });

  test('updates name, quantity, location, category, and note', () async {
    final firstLocationId = await insertLocation('卧室');
    final secondLocationId = await insertLocation('书房');
    final itemId = await repository.create(
      name: '旧名称',
      quantity: 1,
      locationId: firstLocationId,
      category: '旧分类',
      note: '旧备注',
    );

    final updated = await repository.update(
      id: itemId,
      name: '  新名称  ',
      quantity: 3,
      locationId: secondLocationId,
      category: const Value('新分类'),
      note: const Value('新备注'),
    );

    expect(updated.id, itemId);
    expect(updated.name, '新名称');
    expect(updated.quantity, 3);
    expect(updated.locationId, secondLocationId);
    expect(updated.category, '新分类');
    expect(updated.note, '新备注');
    expect((await repository.listByLocation(firstLocationId)), isEmpty);
    expect(
      (await repository.listByLocation(secondLocationId)).single.id,
      itemId,
    );
  });

  test('can clear optional fields during an update', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await repository.create(
      name: '物品',
      locationId: locationId,
      category: '分类',
      note: '备注',
    );

    final updated = await repository.update(
      id: itemId,
      category: const Value(null),
      note: const Value(null),
    );

    expect(updated.category, isNull);
    expect(updated.note, isNull);
  });

  test('failed updates leave the original item unchanged', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await repository.create(
      name: '原名称',
      quantity: 2,
      locationId: locationId,
      category: '分类',
      note: '备注',
    );
    final original = await repository.getById(itemId);

    await expectLater(
      repository.update(id: itemId, name: '   '),
      itemError(ItemRepositoryErrorCode.invalidName),
    );
    await expectLater(
      repository.update(id: itemId, quantity: 0),
      itemError(ItemRepositoryErrorCode.invalidQuantity),
    );
    await expectLater(
      repository.update(id: itemId, locationId: 9999),
      itemError(ItemRepositoryErrorCode.locationNotFound),
    );

    expect(await repository.getById(itemId), original);
  });

  test(
    'reports template, in-progress, and completed deletion impact',
    () async {
      final locationId = await insertLocation('卧室');
      final itemId = await repository.create(
        name: '充电宝',
        locationId: locationId,
      );
      final templateId = await insertTemplate();
      final templateItemId = await insertTemplateItem(
        templateId: templateId,
        itemId: itemId,
      );
      final inProgressSessionId = await insertSession();
      final inProgressItemId = await insertSessionItem(
        sessionId: inProgressSessionId,
        itemId: itemId,
        nameSnapshot: '充电宝',
      );
      final completedSessionId = await insertSession(status: 'COMPLETED');
      final completedItemId = await insertSessionItem(
        sessionId: completedSessionId,
        itemId: itemId,
        nameSnapshot: '历史充电宝',
        locationSnapshot: '历史位置',
        checked: 1,
        checkedAt: 123,
      );

      final impact = await repository.queryDeletionImpact(itemId);

      expect(impact.item.id, itemId);
      expect(impact.hasReferences, isTrue);
      expect(impact.hasCompletedHistory, isTrue);
      expect(impact.templateReferences.single.item.id, templateItemId);
      expect(impact.templateReferences.single.template.id, templateId);
      expect(impact.inProgressReferences.single.item.id, inProgressItemId);
      expect(
        impact.inProgressReferences.single.session.id,
        inProgressSessionId,
      );
      expect(impact.completedReferences.single.item.id, completedItemId);
      expect(impact.completedReferences.single.session.id, completedSessionId);
    },
  );

  test('deletes an item with no references', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await repository.create(
      name: '无引用物品',
      locationId: locationId,
    );

    await repository.deleteById(itemId);

    expect(await repository.findById(itemId), isNull);
  });

  test(
    'converts template references to text and keeps quantity and order',
    () async {
      final locationId = await insertLocation('卧室');
      final itemId = await repository.create(
        name: '雨伞',
        locationId: locationId,
      );
      final templateId = await insertTemplate();
      final templateItemId = await insertTemplateItem(
        templateId: templateId,
        itemId: itemId,
        requiredQuantity: 4,
        sortOrder: 8,
      );

      await repository.deleteById(itemId);

      final entry = await (database.select(
        database.templateItems,
      )..where((table) => table.id.equals(templateItemId))).getSingle();
      expect(entry.itemType, 'TEXT_ITEM');
      expect(entry.itemId, isNull);
      expect(entry.textName, '雨伞');
      expect(entry.requiredQuantity, 4);
      expect(entry.sortOrder, 8);
    },
  );

  test('converts in-progress references and preserves checked state', () async {
    final rootId = await insertLocation('卧室');
    final childId = await insertLocation('玄关柜', parentId: rootId);
    final itemId = await repository.create(name: '钥匙', locationId: childId);
    final sessionId = await insertSession();
    final sessionItemId = await insertSessionItem(
      sessionId: sessionId,
      itemId: itemId,
      nameSnapshot: '创建时名称',
      locationSnapshot: '创建时路径',
      requiredQuantity: 3,
      checked: 1,
      checkedAt: 456,
      sortOrder: 11,
    );

    await repository.deleteById(itemId);

    final entry = await (database.select(
      database.sessionItems,
    )..where((table) => table.id.equals(sessionItemId))).getSingle();
    expect(entry.itemType, 'TEXT_ITEM');
    expect(entry.itemId, isNull);
    expect(entry.textName, '钥匙');
    expect(entry.nameSnapshot, '钥匙');
    expect(entry.locationSnapshot, '卧室 / 玄关柜');
    expect(entry.requiredQuantity, 3);
    expect(entry.checked, 1);
    expect(entry.checkedAt, 456);
    expect(entry.sortOrder, 11);
  });

  test(
    'keeps completed history snapshots unchanged while clearing its item id',
    () async {
      final locationId = await insertLocation('卧室');
      final itemId = await repository.create(
        name: '当前名称',
        locationId: locationId,
      );
      final sessionId = await insertSession(status: 'COMPLETED');
      final sessionItemId = await insertSessionItem(
        sessionId: sessionId,
        itemId: itemId,
        nameSnapshot: '完成时名称',
        locationSnapshot: '卧室 / 历史抽屉',
        requiredQuantity: 2,
        checked: 1,
        checkedAt: 789,
        sortOrder: 5,
      );

      await repository.deleteById(itemId);

      final entry = await (database.select(
        database.sessionItems,
      )..where((table) => table.id.equals(sessionItemId))).getSingle();
      expect(entry.itemType, 'REGISTERED_ITEM');
      expect(entry.itemId, isNull);
      expect(entry.textName, isNull);
      expect(entry.nameSnapshot, '完成时名称');
      expect(entry.locationSnapshot, '卧室 / 历史抽屉');
      expect(entry.requiredQuantity, 2);
      expect(entry.checked, 1);
      expect(entry.checkedAt, 789);
      expect(entry.sortOrder, 5);
    },
  );

  test('converts all references without affecting another item', () async {
    final locationId = await insertLocation('卧室');
    final deletedItemId = await repository.create(
      name: '同名物品',
      locationId: locationId,
    );
    final keptItemId = await repository.create(
      name: '同名物品',
      locationId: locationId,
    );
    final firstTemplateId = await insertTemplate(name: '模板一');
    final secondTemplateId = await insertTemplate(name: '模板二');
    await insertTemplateItem(
      templateId: firstTemplateId,
      itemId: deletedItemId,
      requiredQuantity: 2,
      sortOrder: 3,
    );
    await insertTemplateItem(
      templateId: secondTemplateId,
      itemId: deletedItemId,
      requiredQuantity: 5,
      sortOrder: 7,
    );
    final firstSessionId = await insertSession();
    final secondSessionId = await insertSession();
    final keptSessionId = await insertSession();
    await insertSessionItem(
      sessionId: firstSessionId,
      itemId: deletedItemId,
      nameSnapshot: '同名物品',
      sortOrder: 1,
    );
    await insertSessionItem(
      sessionId: secondSessionId,
      itemId: deletedItemId,
      nameSnapshot: '同名物品',
      sortOrder: 2,
    );
    final keptSessionItemId = await insertSessionItem(
      sessionId: keptSessionId,
      itemId: keptItemId,
      nameSnapshot: '同名物品',
    );

    await repository.deleteById(deletedItemId);

    expect(await repository.findById(deletedItemId), isNull);
    expect((await repository.getById(keptItemId)).name, '同名物品');
    final keptEntry = await (database.select(
      database.sessionItems,
    )..where((table) => table.id.equals(keptSessionItemId))).getSingle();
    expect(keptEntry.itemType, 'REGISTERED_ITEM');
    expect(keptEntry.itemId, keptItemId);

    final templateEntries = await (database.select(
      database.templateItems,
    )..where((table) => table.itemType.equals('TEXT_ITEM'))).get();
    expect(templateEntries, hasLength(2));
    final sessionEntries = await (database.select(
      database.sessionItems,
    )..where((table) => table.itemType.equals('TEXT_ITEM'))).get();
    expect(sessionEntries, hasLength(2));
  });

  test('rolls back all conversions when a later conversion fails', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await repository.create(
      name: '事务物品',
      locationId: locationId,
    );
    final templateId = await insertTemplate();
    final templateItemId = await insertTemplateItem(
      templateId: templateId,
      itemId: itemId,
    );
    final sessionId = await insertSession();
    final sessionItemId = await insertSessionItem(
      sessionId: sessionId,
      itemId: itemId,
      nameSnapshot: '事务物品',
    );

    await database.customStatement('''
      CREATE TRIGGER fail_session_conversion
      BEFORE UPDATE OF item_id, item_type, text_name ON session_items
      WHEN NEW.item_type = 'TEXT_ITEM' AND NEW.item_id IS NULL
      BEGIN
        SELECT RAISE(ABORT, 'forced conversion failure');
      END
    ''');

    await expectLater(
      repository.deleteById(itemId),
      itemError(ItemRepositoryErrorCode.dataInconsistency),
    );

    expect((await repository.getById(itemId)).name, '事务物品');
    final templateEntry = await (database.select(
      database.templateItems,
    )..where((table) => table.id.equals(templateItemId))).getSingle();
    expect(templateEntry.itemType, 'REGISTERED_ITEM');
    expect(templateEntry.itemId, itemId);
    final sessionEntry = await (database.select(
      database.sessionItems,
    )..where((table) => table.id.equals(sessionItemId))).getSingle();
    expect(sessionEntry.itemType, 'REGISTERED_ITEM');
    expect(sessionEntry.itemId, itemId);
    expect(sessionEntry.textName, isNull);
  });

  test('distinguishes missing and repeated deletes', () async {
    await expectLater(
      repository.deleteById(9999),
      itemError(ItemRepositoryErrorCode.itemNotFound),
    );

    final locationId = await insertLocation('卧室');
    final itemId = await repository.create(
      name: '一次性删除',
      locationId: locationId,
    );
    await repository.deleteById(itemId);

    await expectLater(
      repository.deleteById(itemId),
      itemError(ItemRepositoryErrorCode.itemNotFound),
    );
  });

  test(
    'updates active references through the item row without changing history',
    () async {
      final oldLocationId = await insertLocation('卧室');
      final newLocationId = await insertLocation('书房');
      final itemId = await repository.create(
        name: '旧名称',
        quantity: 1,
        locationId: oldLocationId,
      );
      final templateId = await insertTemplate();
      await insertTemplateItem(templateId: templateId, itemId: itemId);
      final activeSessionId = await insertSession();
      final activeItemId = await insertSessionItem(
        sessionId: activeSessionId,
        itemId: itemId,
        nameSnapshot: '创建时名称',
        locationSnapshot: '卧室',
      );
      final completedSessionId = await insertSession(status: 'COMPLETED');
      final completedItemId = await insertSessionItem(
        sessionId: completedSessionId,
        itemId: itemId,
        nameSnapshot: '完成时名称',
        locationSnapshot: '卧室 / 历史位置',
      );

      await repository.update(
        id: itemId,
        name: '新名称',
        quantity: 4,
        locationId: newLocationId,
      );

      final activeJoin = await (database.select(database.sessionItems).join([
        innerJoin(
          database.items,
          database.items.id.equalsExp(database.sessionItems.itemId),
        ),
      ])..where(database.sessionItems.id.equals(activeItemId))).getSingle();
      final activeItem = activeJoin.readTable(database.items);
      expect(activeItem.id, itemId);
      expect(activeItem.name, '新名称');
      expect(activeItem.locationId, newLocationId);

      final templateEntry = await (database.select(
        database.templateItems,
      )..where((table) => table.templateId.equals(templateId))).getSingle();
      expect(templateEntry.itemId, itemId);

      final completedEntry = await (database.select(
        database.sessionItems,
      )..where((table) => table.id.equals(completedItemId))).getSingle();
      expect(completedEntry.nameSnapshot, '完成时名称');
      expect(completedEntry.locationSnapshot, '卧室 / 历史位置');
      expect(completedEntry.requiredQuantity, 1);
    },
  );
}
