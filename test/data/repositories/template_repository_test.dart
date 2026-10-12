import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';
import 'package:personal_items_assistant/data/repositories/item_repository.dart';
import 'package:personal_items_assistant/data/repositories/template_repository.dart';

void main() {
  late AppDatabase database;
  late ItemRepository itemRepository;
  late TemplateRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    itemRepository = ItemRepository(database);
    repository = TemplateRepository(database);
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

  Future<int> createItem({
    required String name,
    required int locationId,
    int quantity = 1,
  }) {
    return itemRepository.create(
      name: name,
      locationId: locationId,
      quantity: quantity,
    );
  }

  Future<int> insertSession({
    int? templateId,
    String status = 'IN_PROGRESS',
    String title = '本次出门',
  }) {
    final timestamp = now();
    return database
        .into(database.outgoingSessions)
        .insert(
          OutgoingSessionsCompanion(
            templateId: Value(templateId),
            title: Value(title),
            status: Value(status),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
            completedAt: Value(status == 'COMPLETED' ? timestamp : null),
          ),
        );
  }

  Future<int> insertSessionItem({
    required int sessionId,
    required String itemType,
    int? itemId,
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

  Future<List<TemplateItem>> readRawEntries(int templateId) {
    final query = database.select(database.templateItems)
      ..where((table) => table.templateId.equals(templateId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.sortOrder),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<TemplateItem> readRawEntry(int entryId) {
    return (database.select(
      database.templateItems,
    )..where((table) => table.id.equals(entryId))).getSingle();
  }

  Future<int> templateCount() async {
    final row = await database.customSelect('''
      SELECT COUNT(*) AS template_count
      FROM outgoing_templates
    ''').getSingle();
    return row.read<int>('template_count');
  }

  Matcher templateError(TemplateRepositoryErrorCode code) {
    return throwsA(
      isA<TemplateRepositoryException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
  }

  test(
    'creates a template with a registered item and reads it by id',
    () async {
      final locationId = await insertLocation('卧室');
      final itemId = await createItem(
        name: '充电宝',
        quantity: 2,
        locationId: locationId,
      );

      final templateId = await repository.create(
        name: '  通勤  ',
        description: '工作日',
        entries: [
          TemplateEntryInput.registered(itemId: itemId, requiredQuantity: 1),
        ],
      );

      final template = await repository.getById(templateId);
      final detail = await repository.getDetail(templateId);

      expect(template.name, '通勤');
      expect(template.description, '工作日');
      expect(detail.template.id, templateId);
      expect(detail.entries, hasLength(1));
      expect(detail.entries.single.entry.itemType, registeredTemplateItemType);
      expect(detail.entries.single.entry.itemId, itemId);
      expect(detail.entries.single.registeredItem!.name, '充电宝');
      expect(detail.entries.single.locationPath, '卧室');
    },
  );

  test('creates text and mixed templates with sorted entries', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await createItem(name: '钥匙', locationId: locationId);

    final textTemplateId = await repository.create(
      name: '纯文本模板',
      entries: const [
        TemplateEntryInput.text(
          textName: '  纸巾  ',
          requiredQuantity: 2,
          sortOrder: 2,
        ),
        TemplateEntryInput.text(
          textName: '纸巾',
          requiredQuantity: 1,
          sortOrder: 1,
        ),
      ],
    );
    final mixedTemplateId = await repository.create(
      name: '混合模板',
      entries: [
        const TemplateEntryInput.text(textName: '门禁卡', sortOrder: 4),
        TemplateEntryInput.registered(itemId: itemId, sortOrder: 3),
      ],
    );

    final textEntries = await repository.listEntries(textTemplateId);
    expect(textEntries.map((entry) => entry.displayName), ['纸巾', '纸巾']);
    expect(textEntries.map((entry) => entry.entry.requiredQuantity), [1, 2]);

    final mixedEntries = await repository.listEntries(mixedTemplateId);
    expect(mixedEntries.map((entry) => entry.displayName), ['钥匙', '门禁卡']);
    expect(mixedEntries.first.registeredItem!.id, itemId);
    expect(mixedEntries.last.registeredItem, isNull);
  });

  test(
    'allows duplicate template names and keeps same-name templates separate',
    () async {
      final locationId = await insertLocation('卧室');
      final firstItemId = await createItem(name: '数据线', locationId: locationId);
      final secondItemId = await createItem(name: '耳机', locationId: locationId);

      final firstTemplateId = await repository.create(
        name: '通勤',
        entries: [TemplateEntryInput.registered(itemId: firstItemId)],
      );
      final secondTemplateId = await repository.create(
        name: '通勤',
        entries: [TemplateEntryInput.registered(itemId: secondItemId)],
      );

      expect(firstTemplateId, isNot(secondTemplateId));
      final templates = await repository.searchByName('通勤');
      expect(templates.map((template) => template.id), [
        firstTemplateId,
        secondTemplateId,
      ]);

      await repository.deleteById(firstTemplateId);

      expect(await repository.findById(firstTemplateId), isNull);
      expect(
        await repository.getById(secondTemplateId),
        isA<OutgoingTemplate>(),
      );
      expect(
        (await repository.listEntries(secondTemplateId)).single.entry.itemId,
        secondItemId,
      );
    },
  );

  test('rejects invalid template names and empty templates', () async {
    await expectLater(
      repository.create(name: '   ', entries: const []),
      templateError(TemplateRepositoryErrorCode.invalidTemplateName),
    );

    await expectLater(
      repository.create(name: '空模板', entries: const []),
      templateError(TemplateRepositoryErrorCode.emptyTemplate),
    );

    expect(await templateCount(), 0);
  });

  test(
    'rolls back the entire create transaction when an entry fails',
    () async {
      final locationId = await insertLocation('卧室');
      final itemId = await createItem(name: '雨伞', locationId: locationId);

      await expectLater(
        repository.create(
          name: '失败模板',
          entries: [
            TemplateEntryInput.registered(itemId: itemId),
            const TemplateEntryInput.registered(itemId: 9999),
          ],
        ),
        templateError(TemplateRepositoryErrorCode.itemNotFound),
      );

      expect(await templateCount(), 0);
      expect(await (database.select(database.templateItems)).get(), isEmpty);
    },
  );

  test('adds, updates, deletes, and changes template entries', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await createItem(name: '钥匙', locationId: locationId);
    final secondItemId = await createItem(name: '钱包', locationId: locationId);
    final templateId = await repository.create(
      name: '编辑模板',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );

    final textEntryId = await repository.addEntry(
      templateId: templateId,
      entry: const TemplateEntryInput.text(textName: '纸巾', requiredQuantity: 2),
    );
    final updatedQuantity = await repository.updateEntryQuantity(
      entryId: textEntryId,
      requiredQuantity: 3,
    );
    final changedEntry = await repository.updateEntry(
      entryId: textEntryId,
      entry: TemplateEntryInput.registered(
        itemId: secondItemId,
        requiredQuantity: 4,
      ),
    );

    expect(updatedQuantity.requiredQuantity, 3);
    expect(changedEntry.itemType, registeredTemplateItemType);
    expect(changedEntry.itemId, secondItemId);
    expect(changedEntry.requiredQuantity, 4);

    await repository.removeEntry(textEntryId);

    final entries = await repository.listEntries(templateId);
    expect(entries, hasLength(1));
    expect(entries.single.entry.itemId, itemId);
  });

  test('rejects deleting the last entry', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await createItem(name: '钥匙', locationId: locationId);
    final templateId = await repository.create(
      name: '不可空',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );
    final entryId = (await readRawEntries(templateId)).single.id;

    await expectLater(
      repository.removeEntry(entryId),
      templateError(TemplateRepositoryErrorCode.emptyTemplate),
    );

    expect(await readRawEntries(templateId), hasLength(1));
  });

  test(
    'replaces all entries atomically and rejects an invalid replacement',
    () async {
      final locationId = await insertLocation('卧室');
      final firstItemId = await createItem(name: '钥匙', locationId: locationId);
      final secondItemId = await createItem(name: '钱包', locationId: locationId);
      final templateId = await repository.create(
        name: '批量编辑模板',
        entries: [
          TemplateEntryInput.registered(itemId: firstItemId),
          const TemplateEntryInput.text(textName: '纸巾'),
        ],
      );

      final replaced = await repository.replaceEntries(
        templateId: templateId,
        entries: [
          TemplateEntryInput.registered(
            itemId: secondItemId,
            requiredQuantity: 3,
          ),
          const TemplateEntryInput.text(textName: '雨伞', requiredQuantity: 2),
        ],
      );
      expect(replaced.entries.map((entry) => entry.displayName), ['钱包', '雨伞']);
      expect(replaced.entries.map((entry) => entry.entry.sortOrder), [0, 1]);

      final replacedEntries = await readRawEntries(templateId);
      await expectLater(
        repository.replaceEntries(
          templateId: templateId,
          entries: [
            const TemplateEntryInput.text(textName: '新条目'),
            const TemplateEntryInput.registered(itemId: 9999),
          ],
        ),
        templateError(TemplateRepositoryErrorCode.itemNotFound),
      );

      expect(await readRawEntries(templateId), replacedEntries);
      expect(
        (await repository.listEntries(templateId))
            .map((entry) => entry.displayName),
        ['钱包', '雨伞'],
      );
    },
  );

  test(
    'reorders entries atomically and keeps ids under the same template',
    () async {
      final locationId = await insertLocation('卧室');
      final firstItemId = await createItem(name: 'A', locationId: locationId);
      final secondItemId = await createItem(name: 'B', locationId: locationId);
      final templateId = await repository.create(
        name: '排序模板',
        entries: [
          TemplateEntryInput.registered(itemId: firstItemId),
          TemplateEntryInput.registered(itemId: secondItemId),
          const TemplateEntryInput.text(textName: 'C'),
        ],
      );
      final entryIds = (await readRawEntries(templateId))
          .map((entry) => entry.id)
          .toList();

      await repository.reorderEntries(
        templateId: templateId,
        orderedEntryIds: [entryIds[2], entryIds[0], entryIds[1]],
      );

      final entries = await repository.listEntries(templateId);
      expect(entries.map((entry) => entry.entry.id), [
        entryIds[2],
        entryIds[0],
        entryIds[1],
      ]);
      expect(entries.map((entry) => entry.entry.sortOrder), [0, 1, 2]);
      expect(entries.map((entry) => entry.entry.templateId).toSet(), {
        templateId,
      });
    },
  );

  test('rejects invalid entry quantity, missing item, duplicate item, and bad combos', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await createItem(name: '钥匙', locationId: locationId);
    final templateId = await repository.create(
      name: '校验模板',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );

    await expectLater(
      repository.addEntry(
        templateId: templateId,
        entry: const TemplateEntryInput.text(
          textName: '纸巾',
          requiredQuantity: 0,
        ),
      ),
      templateError(TemplateRepositoryErrorCode.invalidRequiredQuantity),
    );
    await expectLater(
      repository.addEntry(
        templateId: templateId,
        entry: const TemplateEntryInput.text(
          textName: '纸巾',
          requiredQuantity: -1,
        ),
      ),
      templateError(TemplateRepositoryErrorCode.invalidRequiredQuantity),
    );
    await expectLater(
      repository.addEntry(
        templateId: templateId,
        entry: const TemplateEntryInput.text(textName: '   '),
      ),
      templateError(TemplateRepositoryErrorCode.invalidItemName),
    );
    await expectLater(
      repository.addEntry(
        templateId: templateId,
        entry: const TemplateEntryInput.registered(itemId: 9999),
      ),
      templateError(TemplateRepositoryErrorCode.itemNotFound),
    );
    await expectLater(
      repository.addEntry(
        templateId: templateId,
        entry: TemplateEntryInput.registered(itemId: itemId),
      ),
      templateError(TemplateRepositoryErrorCode.duplicateRegisteredItem),
    );
    await expectLater(
      repository.addEntry(
        templateId: templateId,
        entry: const TemplateEntryInput.raw(
          itemType: textTemplateItemType,
          itemId: 1,
          textName: '非法',
        ),
      ),
      templateError(TemplateRepositoryErrorCode.invalidItem),
    );

    expect(await readRawEntries(templateId), hasLength(1));
  });

  test('allows different templates to reference the same item', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await createItem(name: '口罩', locationId: locationId);

    final firstTemplateId = await repository.create(
      name: '模板一',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );
    final secondTemplateId = await repository.create(
      name: '模板二',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );

    expect((await readRawEntries(firstTemplateId)).single.itemId, itemId);
    expect((await readRawEntries(secondTemplateId)).single.itemId, itemId);
  });

  test('allows same-name items with different ids in one template', () async {
    final locationId = await insertLocation('卧室');
    final firstItemId = await createItem(name: '数据线', locationId: locationId);
    final secondItemId = await createItem(name: '数据线', locationId: locationId);

    final templateId = await repository.create(
      name: '同名物品模板',
      entries: [
        TemplateEntryInput.registered(itemId: firstItemId),
        TemplateEntryInput.registered(itemId: secondItemId),
      ],
    );

    expect((await readRawEntries(templateId)).map((entry) => entry.itemId), [
      firstItemId,
      secondItemId,
    ]);
  });

  test('allows shortage and reports only registered item shortages', () async {
    final locationId = await insertLocation('卧室');
    final lowStockItemId = await createItem(
      name: '口罩',
      quantity: 2,
      locationId: locationId,
    );
    final enoughItemId = await createItem(
      name: '湿巾',
      quantity: 10,
      locationId: locationId,
    );
    final templateId = await repository.create(
      name: '数量不足模板',
      entries: [
        TemplateEntryInput.registered(
          itemId: lowStockItemId,
          requiredQuantity: 5,
        ),
        TemplateEntryInput.registered(
          itemId: enoughItemId,
          requiredQuantity: 3,
        ),
        const TemplateEntryInput.text(textName: '纸巾', requiredQuantity: 99),
      ],
    );

    final shortages = await repository.listQuantityShortages(templateId);

    expect(shortages, hasLength(1));
    expect(shortages.single.itemId, lowStockItemId);
    expect(shortages.single.currentQuantity, 2);
    expect(shortages.single.requiredQuantity, 5);
    expect(shortages.single.shortage, 3);
  });

  test('reads current registered item information after item edits', () async {
    final oldLocationId = await insertLocation('卧室');
    final newLocationId = await insertLocation('书房');
    final itemId = await createItem(
      name: '旧名称',
      quantity: 2,
      locationId: oldLocationId,
    );
    final templateId = await repository.create(
      name: '当前信息模板',
      entries: [
        TemplateEntryInput.registered(itemId: itemId, requiredQuantity: 5),
      ],
    );

    await itemRepository.update(
      id: itemId,
      name: '新名称',
      quantity: 10,
      locationId: newLocationId,
    );

    final entry = (await repository.listEntries(templateId)).single;
    expect(entry.displayName, '新名称');
    expect(entry.registeredItem!.quantity, 10);
    expect(entry.locationPath, '书房');
    expect(entry.entry.requiredQuantity, 5);
  });

  test('reads templates normally after ItemRepository converts deleted items to text', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await createItem(name: '雨伞', locationId: locationId);
    final templateId = await repository.create(
      name: '删除物品模板',
      entries: [
        TemplateEntryInput.registered(
          itemId: itemId,
          requiredQuantity: 3,
          sortOrder: 7,
        ),
      ],
    );

    await itemRepository.deleteById(itemId);

    final entry = (await repository.listEntries(templateId)).single;
    expect(entry.entry.itemType, textTemplateItemType);
    expect(entry.entry.itemId, isNull);
    expect(entry.entry.textName, '雨伞');
    expect(entry.entry.requiredQuantity, 3);
    expect(entry.entry.sortOrder, 7);
    expect(entry.displayName, '雨伞');

    final addedEntryId = await repository.addEntry(
      templateId: templateId,
      entry: const TemplateEntryInput.text(textName: '纸巾'),
    );
    expect(await readRawEntry(addedEntryId), isA<TemplateItem>());
  });

  test(
    'deletes a template without affecting items or generated sessions',
    () async {
      final locationId = await insertLocation('卧室');
      final itemId = await createItem(name: '充电宝', locationId: locationId);
      final templateId = await repository.create(
        name: '可删除模板',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );
      final inProgressSessionId = await insertSession(templateId: templateId);
      final inProgressItemId = await insertSessionItem(
        sessionId: inProgressSessionId,
        itemType: registeredTemplateItemType,
        itemId: itemId,
        nameSnapshot: '充电宝',
        locationSnapshot: '卧室',
      );
      final completedSessionId = await insertSession(
        templateId: templateId,
        status: 'COMPLETED',
        title: '历史出门',
      );
      final completedItemId = await insertSessionItem(
        sessionId: completedSessionId,
        itemType: registeredTemplateItemType,
        itemId: itemId,
        nameSnapshot: '历史充电宝',
        locationSnapshot: '卧室',
        checked: 1,
        checkedAt: 123,
      );

      await repository.deleteById(templateId);

      expect(await repository.findById(templateId), isNull);
      expect(await itemRepository.getById(itemId), isA<Item>());
      final inProgressSession = await (database.select(
        database.outgoingSessions,
      )..where((table) => table.id.equals(inProgressSessionId))).getSingle();
      final completedSession = await (database.select(
        database.outgoingSessions,
      )..where((table) => table.id.equals(completedSessionId))).getSingle();
      expect(inProgressSession.templateId, isNull);
      expect(completedSession.templateId, isNull);
      expect(await readRawEntries(templateId), isEmpty);

      expect(
        await (database.select(
          database.sessionItems,
        )..where((table) => table.id.equals(inProgressItemId))).getSingle(),
        isA<SessionItem>(),
      );
      final completedItem = await (database.select(
        database.sessionItems,
      )..where((table) => table.id.equals(completedItemId))).getSingle();
      expect(completedItem.nameSnapshot, '历史充电宝');
      expect(completedItem.checked, 1);
    },
  );

  test('keeps original data after failed template edits', () async {
    final locationId = await insertLocation('卧室');
    final firstItemId = await createItem(name: '钥匙', locationId: locationId);
    final secondItemId = await createItem(name: '钱包', locationId: locationId);
    final templateId = await repository.create(
      name: '原模板',
      entries: [
        TemplateEntryInput.registered(itemId: firstItemId),
        TemplateEntryInput.registered(itemId: secondItemId),
      ],
    );
    final originalTemplate = await repository.getById(templateId);
    final originalEntries = await readRawEntries(templateId);

    await expectLater(
      repository.updateTemplate(id: templateId, name: '   '),
      templateError(TemplateRepositoryErrorCode.invalidTemplateName),
    );
    await expectLater(
      repository.updateEntry(
        entryId: originalEntries.last.id,
        entry: TemplateEntryInput.registered(itemId: firstItemId),
      ),
      templateError(TemplateRepositoryErrorCode.duplicateRegisteredItem),
    );
    await expectLater(
      repository.reorderEntries(
        templateId: templateId,
        orderedEntryIds: [originalEntries.first.id],
      ),
      templateError(TemplateRepositoryErrorCode.templateItemNotFound),
    );

    expect(await repository.getById(templateId), originalTemplate);
    expect(await readRawEntries(templateId), originalEntries);
  });

  test(
    'lists templates by recent use without changing last used on edit',
    () async {
      final locationId = await insertLocation('卧室');
      final itemId = await createItem(name: '钥匙', locationId: locationId);
      final unusedId = await repository.create(
        name: 'unused',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );
      final olderId = await repository.create(
        name: 'older',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );
      final newerId = await repository.create(
        name: 'newer',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );

      await (database.update(database.outgoingTemplates)
            ..where((table) => table.id.equals(olderId)))
          .write(const OutgoingTemplatesCompanion(lastUsedAt: Value(1000)));
      await (database.update(database.outgoingTemplates)
            ..where((table) => table.id.equals(newerId)))
          .write(const OutgoingTemplatesCompanion(lastUsedAt: Value(2000)));

      await repository.updateTemplate(id: olderId, name: 'older renamed');

      final recent = await repository.listRecentlyUsed();
      expect(recent.map((template) => template.id), [
        newerId,
        olderId,
        unusedId,
      ]);
      expect((await repository.getById(olderId)).lastUsedAt, 1000);

      final limited = await repository.listRecentlyUsed(limit: 2);
      expect(limited.map((template) => template.id), [newerId, olderId]);
    },
  );

  test('lists all templates with stable name and id ordering', () async {
    final locationId = await insertLocation('卧室');
    final itemId = await createItem(name: '钥匙', locationId: locationId);
    final bId = await repository.create(
      name: 'B',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );
    final a1Id = await repository.create(
      name: 'A',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );
    final a2Id = await repository.create(
      name: 'A',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );

    expect((await repository.listAll()).map((template) => template.id), [
      a1Id,
      a2Id,
      bId,
    ]);
  });
}
