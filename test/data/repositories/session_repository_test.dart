import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_items_assistant/data/local/app_database.dart';
import 'package:personal_items_assistant/data/repositories/item_repository.dart';
import 'package:personal_items_assistant/data/repositories/location_repository.dart';
import 'package:personal_items_assistant/data/repositories/session_repository.dart';
import 'package:personal_items_assistant/data/repositories/template_repository.dart';

void main() {
  late AppDatabase database;
  late ItemRepository itemRepository;
  late LocationRepository locationRepository;
  late TemplateRepository templateRepository;
  late SessionRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    itemRepository = ItemRepository(database);
    locationRepository = LocationRepository(database);
    templateRepository = TemplateRepository(database);
    repository = SessionRepository(database);
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

  Future<int> insertEmptyTemplate({String name = '空模板'}) {
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

  Future<List<SessionItem>> readRawEntries(int sessionId) {
    final query = database.select(database.sessionItems)
      ..where((table) => table.sessionId.equals(sessionId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.sortOrder),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<int> sessionCount() async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS count FROM outgoing_sessions')
        .getSingle();
    return row.read<int>('count');
  }

  Future<int> sessionItemCount() async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS count FROM session_items')
        .getSingle();
    return row.read<int>('count');
  }

  Matcher sessionError(SessionRepositoryErrorCode code) {
    return throwsA(
      isA<SessionRepositoryException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
  }

  test('creates an independent task from a mixed template', () async {
    final locationId = await insertLocation('Bedroom');
    final itemId = await createItem(
      name: 'Power bank',
      quantity: 2,
      locationId: locationId,
    );
    final templateId = await templateRepository.create(
      name: 'Commute',
      entries: [
        TemplateEntryInput.registered(
          itemId: itemId,
          requiredQuantity: 5,
          sortOrder: 8,
        ),
        const TemplateEntryInput.text(
          textName: 'Tissues',
          requiredQuantity: 2,
          sortOrder: 3,
        ),
      ],
    );

    final sessionId = await repository.createFromTemplate(templateId);
    final session = await repository.getById(sessionId);
    final entries = await repository.listEntries(sessionId);

    expect(session.templateId, templateId);
    expect(session.title, 'Commute');
    expect(session.status, 'IN_PROGRESS');
    expect(session.completedAt, isNull);
    expect(entries.map((entry) => entry.displayName), [
      'Tissues',
      'Power bank',
    ]);
    expect(entries.map((entry) => entry.entry.requiredQuantity), [2, 5]);
    expect(entries.map((entry) => entry.entry.sortOrder), [3, 8]);
    expect(entries.every((entry) => entry.entry.checked == 0), isTrue);
    expect(entries.every((entry) => entry.entry.checkedAt == null), isTrue);
    expect(
      entries.map((entry) => entry.entry.id).toSet().length,
      entries.length,
    );
    expect(
      entries.every((entry) => entry.entry.sessionId == sessionId),
      isTrue,
    );
    expect(await templateRepository.listEntries(templateId), hasLength(2));
  });

  test(
    'creates a task from a text-only template with an override title',
    () async {
      final templateId = await templateRepository.create(
        name: 'Default title',
        entries: const [
          TemplateEntryInput.text(
            textName: 'Passport',
            requiredQuantity: 1,
            sortOrder: 2,
          ),
          TemplateEntryInput.text(
            textName: 'Notebook',
            requiredQuantity: 3,
            sortOrder: 1,
          ),
        ],
      );

      final sessionId = await repository.createFromTemplate(
        templateId,
        title: 'Business trip',
      );
      final detail = await repository.getDetail(sessionId);

      expect(detail.session.title, 'Business trip');
      expect(detail.entries.map((entry) => entry.displayName), [
        'Notebook',
        'Passport',
      ]);
      expect(detail.entries.map((entry) => entry.registeredItem), [
        isNull,
        isNull,
      ]);
      expect(detail.entries.map((entry) => entry.locationPath), [
        isNull,
        isNull,
      ]);
    },
  );

  test('creates a direct mixed task without a template', () async {
    final locationId = await insertLocation('Hallway');
    final itemId = await createItem(name: 'Keys', locationId: locationId);

    final sessionId = await repository.createDirect(
      title: '  Quick trip  ',
      entries: [
        const SessionEntryInput.text(textName: 'Umbrella', requiredQuantity: 2),
        SessionEntryInput.registered(itemId: itemId),
      ],
    );
    final detail = await repository.getDetail(sessionId);

    expect(detail.session.templateId, isNull);
    expect(detail.session.title, 'Quick trip');
    expect(detail.entries.map((entry) => entry.displayName), [
      'Umbrella',
      'Keys',
    ]);
    expect(
      detail.entries
          .singleWhere((entry) => entry.displayName == 'Keys')
          .locationPath,
      'Hallway',
    );
    expect(detail.uncheckedCount, 2);
  });

  test(
    'rejects empty, blank, invalid, and duplicate task entries atomically',
    () async {
      final locationId = await insertLocation('Bedroom');
      final itemId = await createItem(name: 'Keys', locationId: locationId);

      await expectLater(
        repository.createDirect(title: '   ', entries: const []),
        sessionError(SessionRepositoryErrorCode.invalidTitle),
      );
      await expectLater(
        repository.createDirect(title: 'Empty', entries: const []),
        sessionError(SessionRepositoryErrorCode.emptySession),
      );
      await expectLater(
        repository.createDirect(
          title: 'Invalid quantity',
          entries: const [
            SessionEntryInput.text(textName: 'Tissues', requiredQuantity: 0),
          ],
        ),
        sessionError(SessionRepositoryErrorCode.invalidRequiredQuantity),
      );
      await expectLater(
        repository.createDirect(
          title: 'Invalid name',
          entries: const [SessionEntryInput.text(textName: '   ')],
        ),
        sessionError(SessionRepositoryErrorCode.invalidItemName),
      );
      await expectLater(
        repository.createDirect(
          title: 'Missing item',
          entries: const [SessionEntryInput.registered(itemId: 9999)],
        ),
        sessionError(SessionRepositoryErrorCode.itemNotFound),
      );
      await expectLater(
        repository.createDirect(
          title: 'Duplicate item',
          entries: [
            SessionEntryInput.registered(itemId: itemId),
            SessionEntryInput.registered(itemId: itemId),
          ],
        ),
        sessionError(SessionRepositoryErrorCode.duplicateRegisteredItem),
      );
      await expectLater(
        repository.createDirect(
          title: 'Invalid combination',
          entries: const [
            SessionEntryInput.raw(
              itemType: textSessionItemType,
              itemId: 1,
              textName: 'Invalid',
            ),
          ],
        ),
        sessionError(SessionRepositoryErrorCode.invalidItem),
      );

      expect(await sessionCount(), 0);
      expect(await sessionItemCount(), 0);
    },
  );

  test(
    'rejects a corrupt empty template without changing last used time',
    () async {
      final templateId = await insertEmptyTemplate();

      await expectLater(
        repository.createFromTemplate(templateId),
        sessionError(SessionRepositoryErrorCode.emptySession),
      );

      final template = await templateRepository.getById(templateId);
      expect(template.lastUsedAt, isNull);
      expect(await sessionCount(), 0);
    },
  );

  test(
    'updates last used time only after a successful template creation',
    () async {
      final locationId = await insertLocation('Bedroom');
      final itemId = await createItem(name: 'Keys', locationId: locationId);
      final templateId = await templateRepository.create(
        name: 'Reusable',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );

      expect((await templateRepository.getById(templateId)).lastUsedAt, isNull);
      await repository.getDetail(
        await repository.createFromTemplate(templateId, title: 'First use'),
      );
      final usedTemplate = await templateRepository.getById(templateId);
      expect(usedTemplate.lastUsedAt, isNotNull);

      final lastUsedAt = usedTemplate.lastUsedAt;
      await templateRepository.updateTemplate(id: templateId, name: 'Renamed');
      await templateRepository.listEntries(templateId);
      expect(
        (await templateRepository.getById(templateId)).lastUsedAt,
        lastUsedAt,
      );
    },
  );

  test(
    'rolls back task creation and last used time when entry insertion fails',
    () async {
      final locationId = await insertLocation('Bedroom');
      final itemId = await createItem(name: 'Keys', locationId: locationId);
      final templateId = await templateRepository.create(
        name: 'Broken creation',
        entries: [TemplateEntryInput.registered(itemId: itemId)],
      );

      await database.customStatement('''
      CREATE TRIGGER fail_session_insert
      BEFORE INSERT ON session_items
      BEGIN
        SELECT RAISE(ABORT, 'forced session insert failure');
      END
    ''');

      await expectLater(
        repository.createFromTemplate(templateId),
        sessionError(SessionRepositoryErrorCode.dataInconsistency),
      );

      await database.customStatement('DROP TRIGGER fail_session_insert');
      expect(await sessionCount(), 0);
      expect(await sessionItemCount(), 0);
      expect((await templateRepository.getById(templateId)).lastUsedAt, isNull);
    },
  );

  test('template edits and deletion do not affect a generated task', () async {
    final locationId = await insertLocation('Bedroom');
    final firstItemId = await createItem(name: 'Keys', locationId: locationId);
    final secondItemId = await createItem(
      name: 'Wallet',
      locationId: locationId,
    );
    final templateId = await templateRepository.create(
      name: 'Before edit',
      entries: [
        TemplateEntryInput.registered(itemId: firstItemId, requiredQuantity: 2),
      ],
    );
    final sessionId = await repository.createFromTemplate(templateId);
    final originalEntries = await readRawEntries(sessionId);

    await templateRepository.replaceEntries(
      templateId: templateId,
      entries: [
        TemplateEntryInput.registered(
          itemId: secondItemId,
          requiredQuantity: 9,
        ),
        const TemplateEntryInput.text(textName: 'Umbrella'),
      ],
    );
    await templateRepository.deleteById(templateId);

    final session = await repository.getById(sessionId);
    final entries = await readRawEntries(sessionId);
    expect(session.templateId, isNull);
    expect(entries, originalEntries);
    expect(
      (await repository.listEntries(sessionId)).single.displayName,
      'Keys',
    );
    expect(await itemRepository.getById(firstItemId), isA<Item>());
    expect(await templateRepository.findById(templateId), isNull);
  });

  test('lists multiple active tasks in stable recent-update order', () async {
    final firstId = await repository.createDirect(
      title: 'First',
      entries: const [SessionEntryInput.text(textName: 'A')],
    );
    final secondId = await repository.createDirect(
      title: 'Second',
      entries: const [SessionEntryInput.text(textName: 'B')],
    );
    await (database.update(database.outgoingSessions)
          ..where((table) => table.id.equals(firstId)))
        .write(const OutgoingSessionsCompanion(updatedAt: Value(100)));
    await (database.update(database.outgoingSessions)
          ..where((table) => table.id.equals(secondId)))
        .write(const OutgoingSessionsCompanion(updatedAt: Value(200)));

    final active = await repository.listActive();
    expect(active.map((session) => session.id), [secondId, firstId]);
    expect((await repository.listInProgress()).map((session) => session.id), [
      secondId,
      firstId,
    ]);
    expect(await repository.getStatus(firstId), 'IN_PROGRESS');
  });

  test('reads current item name and location for an active task', () async {
    final bedroomId = await insertLocation('Bedroom');
    final deskId = await insertLocation('Desk', parentId: bedroomId);
    final livingRoomId = await insertLocation('Living room');
    final itemId = await createItem(
      name: 'Old name',
      locationId: deskId,
      quantity: 2,
    );
    final sessionId = await repository.createDirect(
      title: 'Current data',
      entries: [
        SessionEntryInput.registered(itemId: itemId, requiredQuantity: 5),
      ],
    );

    var entry = (await repository.listEntries(sessionId)).single;
    expect(entry.displayName, 'Old name');
    expect(entry.locationPath, 'Bedroom / Desk');
    expect(entry.entry.requiredQuantity, 5);

    await itemRepository.update(id: itemId, name: 'New name');
    await locationRepository.move(id: deskId, targetParentId: livingRoomId);

    entry = (await repository.listEntries(sessionId)).single;
    expect(entry.displayName, 'New name');
    expect(entry.locationPath, 'Living room / Desk');
    expect(entry.entry.requiredQuantity, 5);
  });

  test(
    'reports shortages without blocking creation and excludes text entries',
    () async {
      final locationId = await insertLocation('Bedroom');
      final lowStockId = await createItem(
        name: 'Mask',
        quantity: 2,
        locationId: locationId,
      );
      final enoughId = await createItem(
        name: 'Keys',
        quantity: 5,
        locationId: locationId,
      );
      final sessionId = await repository.createDirect(
        title: 'Shortage',
        entries: [
          SessionEntryInput.registered(itemId: lowStockId, requiredQuantity: 4),
          SessionEntryInput.registered(itemId: enoughId, requiredQuantity: 2),
          const SessionEntryInput.text(
            textName: 'Tissues',
            requiredQuantity: 99,
          ),
        ],
      );

      final shortages = await repository.listQuantityShortages(sessionId);
      expect(shortages, hasLength(1));
      expect(shortages.single.itemId, lowStockId);
      expect(shortages.single.currentQuantity, 2);
      expect(shortages.single.requiredQuantity, 4);
      expect(shortages.single.shortage, 2);
      expect((await itemRepository.getById(lowStockId)).quantity, 2);
    },
  );

  test('persists checking and unchecking without changing the item', () async {
    final locationId = await insertLocation('Bedroom');
    final itemId = await createItem(
      name: 'Keys',
      quantity: 3,
      locationId: locationId,
    );
    final sessionId = await repository.createDirect(
      title: 'Check state',
      entries: [SessionEntryInput.registered(itemId: itemId)],
    );
    final before = await itemRepository.getById(itemId);
    final sessionBefore = await repository.getById(sessionId);

    await repository.setChecked(
      sessionId,
      (await readRawEntries(sessionId)).single.id,
      true,
    );
    var raw = (await readRawEntries(sessionId)).single;
    expect(raw.checked, 1);
    expect(raw.checkedAt, isNotNull);
    expect(await itemRepository.getById(itemId), before);
    expect(await repository.getDetail(sessionId), isNotNull);

    await repository.setChecked(sessionId, raw.id, false);
    raw = (await readRawEntries(sessionId)).single;
    expect(raw.checked, 0);
    expect(raw.checkedAt, isNull);
    expect((await repository.getById(sessionId)).status, sessionBefore.status);
    expect(await itemRepository.getById(itemId), before);
  });

  test(
    'resets checked state only when an entry meaningfully changes',
    () async {
      final locationId = await insertLocation('Bedroom');
      final firstItemId = await createItem(
        name: 'First item',
        locationId: locationId,
      );
      final secondItemId = await createItem(
        name: 'Second item',
        locationId: locationId,
      );
      final sessionId = await repository.createDirect(
        title: 'Edit check state',
        entries: [
          SessionEntryInput.registered(
            itemId: firstItemId,
            requiredQuantity: 2,
          ),
          const SessionEntryInput.text(textName: 'Original note'),
        ],
      );
      final initialEntries = await readRawEntries(sessionId);
      final registeredEntryId = initialEntries
          .singleWhere((entry) => entry.itemId == firstItemId)
          .id;
      final textEntryId = initialEntries
          .singleWhere((entry) => entry.itemType == textSessionItemType)
          .id;

      await repository.setChecked(sessionId, registeredEntryId, true);
      await repository.updateEntry(
        sessionId: sessionId,
        entryId: registeredEntryId,
        entry: SessionEntryInput.registered(
          itemId: secondItemId,
          requiredQuantity: 2,
        ),
      );
      var registeredEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(registeredEntry.itemId, secondItemId);
      expect(registeredEntry.checked, 0);
      expect(registeredEntry.checkedAt, isNull);

      await repository.setChecked(sessionId, registeredEntryId, true);
      await repository.updateEntry(
        sessionId: sessionId,
        entryId: registeredEntryId,
        entry: const SessionEntryInput.text(
          textName: 'Converted note',
          requiredQuantity: 2,
        ),
      );
      var convertedEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(convertedEntry.itemType, textSessionItemType);
      expect(convertedEntry.checked, 0);
      expect(convertedEntry.checkedAt, isNull);

      await repository.setChecked(sessionId, registeredEntryId, true);
      await repository.renameTextEntry(
        sessionId: sessionId,
        entryId: registeredEntryId,
        name: 'Renamed note',
      );
      convertedEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(convertedEntry.textName, 'Renamed note');
      expect(convertedEntry.checked, 0);
      expect(convertedEntry.checkedAt, isNull);

      await repository.setChecked(sessionId, registeredEntryId, true);
      await repository.updateEntryQuantity(
        sessionId: sessionId,
        entryId: registeredEntryId,
        requiredQuantity: 3,
      );
      convertedEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(convertedEntry.requiredQuantity, 3);
      expect(convertedEntry.checked, 0);
      expect(convertedEntry.checkedAt, isNull);

      await repository.setChecked(sessionId, registeredEntryId, true);
      final checkedBeforeSameQuantity = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      await repository.updateEntryQuantity(
        sessionId: sessionId,
        entryId: registeredEntryId,
        requiredQuantity: 3,
      );
      var unchangedEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(unchangedEntry.checked, 1);
      expect(unchangedEntry.checkedAt, checkedBeforeSameQuantity.checkedAt);

      await repository.updateEntry(
        sessionId: sessionId,
        entryId: registeredEntryId,
        entry: SessionEntryInput.text(
          textName: 'Renamed note',
          requiredQuantity: 3,
          sortOrder: unchangedEntry.sortOrder,
        ),
      );
      unchangedEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(unchangedEntry.checked, 1);
      expect(unchangedEntry.checkedAt, checkedBeforeSameQuantity.checkedAt);

      await repository.renameTextEntry(
        sessionId: sessionId,
        entryId: registeredEntryId,
        name: '  Renamed note  ',
      );
      unchangedEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(unchangedEntry.checked, 1);
      expect(unchangedEntry.checkedAt, checkedBeforeSameQuantity.checkedAt);

      expect(
        (await readRawEntries(sessionId))
            .singleWhere((entry) => entry.id == textEntryId)
            .checked,
        0,
      );
    },
  );

  test(
    'preserves checked state across reorder and live item changes',
    () async {
      final bedroomId = await insertLocation('Bedroom');
      final deskId = await insertLocation('Desk', parentId: bedroomId);
      final livingRoomId = await insertLocation('Living room');
      final itemId = await createItem(
        name: 'Old charger',
        quantity: 1,
        locationId: deskId,
      );
      final sessionId = await repository.createDirect(
        title: 'Keep checked state',
        entries: [
          SessionEntryInput.registered(itemId: itemId),
          const SessionEntryInput.text(textName: 'Tissues'),
        ],
      );
      final entries = await readRawEntries(sessionId);
      final registeredEntryId = entries
          .singleWhere((entry) => entry.itemId == itemId)
          .id;
      final textEntryId = entries
          .singleWhere((entry) => entry.itemType == textSessionItemType)
          .id;

      await repository.setChecked(sessionId, registeredEntryId, true);
      final checkedBefore = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);

      await itemRepository.update(id: itemId, name: 'New charger', quantity: 4);
      await locationRepository.move(id: deskId, targetParentId: livingRoomId);

      var activeEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(activeEntry.checked, 1);
      expect(activeEntry.checkedAt, checkedBefore.checkedAt);
      final detail = await repository.listEntries(sessionId);
      final registeredDetail = detail.singleWhere(
        (entry) => entry.entry.id == registeredEntryId,
      );
      expect(registeredDetail.displayName, 'New charger');
      expect(registeredDetail.locationPath, 'Living room / Desk');

      await repository.reorderEntries(
        sessionId: sessionId,
        orderedEntryIds: [textEntryId, registeredEntryId],
      );
      activeEntry = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.id == registeredEntryId);
      expect(activeEntry.checked, 1);
      expect(activeEntry.checkedAt, checkedBefore.checkedAt);
    },
  );

  test(
    'edits, reorders, and removes active entries without emptying the task',
    () async {
      final locationId = await insertLocation('Bedroom');
      final firstItemId = await createItem(
        name: 'Keys',
        locationId: locationId,
      );
      final secondItemId = await createItem(
        name: 'Wallet',
        locationId: locationId,
      );
      final thirdItemId = await createItem(
        name: 'Phone',
        locationId: locationId,
      );
      final sessionId = await repository.createDirect(
        title: 'Editable',
        entries: [
          SessionEntryInput.registered(itemId: firstItemId),
          const SessionEntryInput.text(textName: 'Tissues'),
        ],
      );
      final firstEntryId = (await readRawEntries(sessionId))[0].id;
      final textEntryId = (await readRawEntries(sessionId))[1].id;
      final secondEntryId = await repository.addEntry(
        sessionId: sessionId,
        entry: SessionEntryInput.registered(itemId: secondItemId),
      );

      await repository.updateEntryQuantity(
        sessionId: sessionId,
        entryId: textEntryId,
        requiredQuantity: 3,
      );
      await repository.renameTextEntry(
        sessionId: sessionId,
        entryId: textEntryId,
        name: '  Wipes  ',
      );
      await repository.updateEntry(
        sessionId: sessionId,
        entryId: firstEntryId,
        entry: SessionEntryInput.registered(itemId: thirdItemId),
      );
      final convertedEntry = await repository.updateEntry(
        sessionId: sessionId,
        entryId: firstEntryId,
        entry: const SessionEntryInput.text(textName: 'Loose note'),
      );
      expect(convertedEntry.itemType, textSessionItemType);
      expect(convertedEntry.itemId, isNull);
      expect(convertedEntry.locationSnapshot, isNull);
      await repository.updateEntry(
        sessionId: sessionId,
        entryId: firstEntryId,
        entry: SessionEntryInput.registered(itemId: thirdItemId),
      );
      await repository.reorderEntries(
        sessionId: sessionId,
        orderedEntryIds: [textEntryId, secondEntryId, firstEntryId],
      );

      var entries = await repository.listEntries(sessionId);
      expect(entries.map((entry) => entry.displayName), [
        'Wipes',
        'Wallet',
        'Phone',
      ]);
      expect(entries.map((entry) => entry.entry.requiredQuantity), [3, 1, 1]);

      await repository.removeEntry(
        sessionId: sessionId,
        entryId: secondEntryId,
      );
      entries = await repository.listEntries(sessionId);
      expect(entries.map((entry) => entry.displayName), ['Wipes', 'Phone']);

      await repository.removeEntry(sessionId: sessionId, entryId: textEntryId);
      await expectLater(
        repository.removeEntry(sessionId: sessionId, entryId: firstEntryId),
        sessionError(SessionRepositoryErrorCode.emptySession),
      );
      expect(await repository.listEntries(sessionId), hasLength(1));
    },
  );

  test('rejects invalid active edits and preserves original rows', () async {
    final locationId = await insertLocation('Bedroom');
    final firstItemId = await createItem(name: 'Keys', locationId: locationId);
    final secondItemId = await createItem(
      name: 'Wallet',
      locationId: locationId,
    );
    final sessionId = await repository.createDirect(
      title: 'Original',
      entries: [
        SessionEntryInput.registered(itemId: firstItemId),
        SessionEntryInput.registered(itemId: secondItemId),
      ],
    );
    final original = await readRawEntries(sessionId);

    await expectLater(
      repository.renameActive(sessionId: sessionId, title: '   '),
      sessionError(SessionRepositoryErrorCode.invalidTitle),
    );
    await expectLater(
      repository.updateEntryQuantity(
        sessionId: sessionId,
        entryId: original.first.id,
        requiredQuantity: 0,
      ),
      sessionError(SessionRepositoryErrorCode.invalidRequiredQuantity),
    );
    await expectLater(
      repository.addEntry(
        sessionId: sessionId,
        entry: SessionEntryInput.registered(itemId: firstItemId),
      ),
      sessionError(SessionRepositoryErrorCode.duplicateRegisteredItem),
    );
    await expectLater(
      repository.updateEntry(
        sessionId: sessionId,
        entryId: original.last.id,
        entry: SessionEntryInput.registered(itemId: firstItemId),
      ),
      sessionError(SessionRepositoryErrorCode.duplicateRegisteredItem),
    );
    await expectLater(
      repository.reorderEntries(
        sessionId: sessionId,
        orderedEntryIds: [original.first.id],
      ),
      sessionError(SessionRepositoryErrorCode.sessionItemNotFound),
    );

    expect(await readRawEntries(sessionId), original);
    expect((await repository.getById(sessionId)).title, 'Original');
  });

  test(
    'converts deleted active items to text while preserving task state',
    () async {
      final rootId = await insertLocation('Bedroom');
      final childId = await insertLocation('Desk', parentId: rootId);
      final itemId = await createItem(name: 'Charger', locationId: childId);
      final sessionId = await repository.createDirect(
        title: 'Delete conversion',
        entries: [
          SessionEntryInput.registered(
            itemId: itemId,
            requiredQuantity: 4,
            sortOrder: 7,
          ),
          const SessionEntryInput.text(textName: 'Tissues', sortOrder: 2),
        ],
      );
      final rawBefore = await readRawEntries(sessionId);
      final deletedEntry = rawBefore.singleWhere(
        (entry) => entry.itemId == itemId,
      );
      await repository.setChecked(sessionId, deletedEntry.id, true);

      await itemRepository.deleteById(itemId);

      final raw = await readRawEntries(sessionId);
      final converted = raw.singleWhere((entry) => entry.id == deletedEntry.id);
      expect(converted.itemType, textSessionItemType);
      expect(converted.itemId, isNull);
      expect(converted.textName, 'Charger');
      expect(converted.nameSnapshot, 'Charger');
      expect(converted.locationSnapshot, 'Bedroom / Desk');
      expect(converted.requiredQuantity, 4);
      expect(converted.checked, 1);
      expect(converted.checkedAt, isNotNull);
      expect(converted.sortOrder, 7);
      expect(
        (await repository.listEntries(sessionId)).first.displayName,
        'Tissues',
      );
    },
  );

  test(
    'keeps checked state independent across multiple active tasks',
    () async {
      final locationId = await insertLocation('Bedroom');
      final itemId = await createItem(name: 'Keys', locationId: locationId);
      final firstSessionId = await repository.createDirect(
        title: 'First task',
        entries: [SessionEntryInput.registered(itemId: itemId)],
      );
      final secondSessionId = await repository.createDirect(
        title: 'Second task',
        entries: const [SessionEntryInput.text(textName: 'Umbrella')],
      );
      final firstEntryId = (await readRawEntries(firstSessionId)).single.id;
      final secondEntryId = (await readRawEntries(secondSessionId)).single.id;

      await repository.setChecked(firstSessionId, firstEntryId, true);

      expect((await readRawEntries(firstSessionId)).single.checked, 1);
      expect((await readRawEntries(secondSessionId)).single.checked, 0);
      expect(
        (await repository.listEntries(firstSessionId)).single.isChecked,
        isTrue,
      );
      expect(
        (await repository.listEntries(secondSessionId)).single.isChecked,
        isFalse,
      );

      await repository.setChecked(secondSessionId, secondEntryId, true);
      expect((await readRawEntries(firstSessionId)).single.checked, 1);
      expect((await readRawEntries(secondSessionId)).single.checked, 1);
    },
  );

  test('keeps same-name item references independent across tasks', () async {
    final locationId = await insertLocation('Bedroom');
    final firstItemId = await createItem(
      name: 'Data cable',
      locationId: locationId,
    );
    final secondItemId = await createItem(
      name: 'Data cable',
      locationId: locationId,
    );
    final templateId = await templateRepository.create(
      name: 'Cables',
      entries: [
        TemplateEntryInput.registered(itemId: firstItemId),
        TemplateEntryInput.registered(itemId: secondItemId),
      ],
    );
    final firstSessionId = await repository.createFromTemplate(templateId);
    final secondSessionId = await repository.createDirect(
      title: 'Second task',
      entries: [SessionEntryInput.registered(itemId: secondItemId)],
    );

    await itemRepository.deleteById(firstItemId);

    final firstEntries = await repository.listEntries(firstSessionId);
    final secondEntries = await repository.listEntries(secondSessionId);
    expect(
      firstEntries.where(
        (entry) => entry.entry.itemType == textSessionItemType,
      ),
      hasLength(1),
    );
    expect(
      firstEntries.where((entry) => entry.entry.itemId == secondItemId),
      hasLength(1),
    );
    expect(secondEntries.single.entry.itemId, secondItemId);
    expect(await itemRepository.getById(secondItemId), isA<Item>());
  });

  test(
    'completes with confirmation and freezes final item snapshots',
    () async {
      final bedroomId = await insertLocation('Bedroom');
      final deskId = await insertLocation('Desk', parentId: bedroomId);
      final livingRoomId = await insertLocation('Living room');
      final itemId = await createItem(
        name: 'Old charger',
        locationId: deskId,
        quantity: 1,
      );
      final sessionId = await repository.createDirect(
        title: 'Freeze history',
        entries: [
          SessionEntryInput.registered(itemId: itemId, requiredQuantity: 2),
          const SessionEntryInput.text(textName: 'Tissues'),
        ],
      );
      final registeredEntryId = (await readRawEntries(sessionId))
          .singleWhere((entry) => entry.itemId == itemId)
          .id;
      await repository.setChecked(sessionId, registeredEntryId, true);

      await expectLater(
        repository.complete(sessionId),
        sessionError(
          SessionRepositoryErrorCode.incompleteItemsConfirmationRequired,
        ),
      );
      expect((await repository.getById(sessionId)).status, 'IN_PROGRESS');
      expect(
        (await readRawEntries(sessionId))
            .firstWhere((entry) => entry.id == registeredEntryId)
            .nameSnapshot,
        'Old charger',
      );

      await repository.complete(sessionId, confirmedUnchecked: true);
      var completed = await repository.getById(sessionId);
      expect(completed.status, 'COMPLETED');
      expect(completed.completedAt, isNotNull);
      var entries = await repository.listEntries(sessionId);
      final completedRegistered = entries.singleWhere(
        (entry) => entry.entry.id == registeredEntryId,
      );
      expect(completedRegistered.displayName, 'Old charger');
      expect(completedRegistered.locationPath, 'Bedroom / Desk');
      expect(completedRegistered.registeredItem, isNull);
      expect(entries.any((entry) => !entry.isChecked), isTrue);

      await itemRepository.update(id: itemId, name: 'New charger');
      await locationRepository.move(id: deskId, targetParentId: livingRoomId);
      await locationRepository.rename(deskId, 'Cabinet');
      await itemRepository.deleteById(itemId);

      completed = await repository.getById(sessionId);
      entries = await repository.listEntries(sessionId);
      final history = entries.singleWhere(
        (entry) => entry.entry.id == registeredEntryId,
      );
      expect(completed.status, 'COMPLETED');
      expect(history.displayName, 'Old charger');
      expect(history.locationPath, 'Bedroom / Desk');
      expect(history.entry.requiredQuantity, 2);
      expect(history.entry.checked, 1);
      expect(history.entry.nameSnapshot, 'Old charger');
      expect(history.entry.locationSnapshot, 'Bedroom / Desk');
      expect(history.entry.itemId, isNull);
    },
  );

  test(
    'completed registered and text entries display frozen name snapshots',
    () async {
      final bedroomId = await insertLocation('Bedroom');
      final deskId = await insertLocation('Desk', parentId: bedroomId);
      final livingRoomId = await insertLocation('Living room');
      final itemId = await createItem(
        name: 'Original charger',
        locationId: deskId,
      );
      final sessionId = await repository.createDirect(
        title: 'Snapshot names',
        entries: [
          SessionEntryInput.registered(itemId: itemId),
          const SessionEntryInput.text(textName: 'Original text'),
        ],
      );
      final rawEntries = await readRawEntries(sessionId);
      final registeredEntry = rawEntries.singleWhere(
        (entry) => entry.itemType == registeredSessionItemType,
      );
      final textEntry = rawEntries.singleWhere(
        (entry) => entry.itemType == textSessionItemType,
      );

      await repository.complete(sessionId, confirmedUnchecked: true);
      await itemRepository.update(id: itemId, name: 'Current charger');
      await locationRepository.move(id: deskId, targetParentId: livingRoomId);
      await locationRepository.rename(deskId, 'Cabinet');
      await (database.update(database.sessionItems)
            ..where((table) => table.id.equals(textEntry.id)))
          .write(const SessionItemsCompanion(textName: Value('Current text')));

      final entries = await repository.listEntries(sessionId);
      final registeredHistory = entries.singleWhere(
        (entry) => entry.entry.id == registeredEntry.id,
      );
      final textHistory = entries.singleWhere(
        (entry) => entry.entry.id == textEntry.id,
      );

      expect(registeredHistory.isCompleted, isTrue);
      expect(registeredHistory.displayName, 'Original charger');
      expect(registeredHistory.locationPath, 'Bedroom / Desk');
      expect(registeredHistory.registeredItem, isNull);
      expect(textHistory.isCompleted, isTrue);
      expect(textHistory.displayName, 'Original text');
      expect(textHistory.locationPath, isNull);
    },
  );

  test('completes a fully checked task without confirmation and preserves checked times', () async {
    final sessionId = await repository.createDirect(
      title: 'All checked',
      entries: const [
        SessionEntryInput.text(textName: 'A'),
        SessionEntryInput.text(textName: 'B'),
      ],
    );
    final entries = await readRawEntries(sessionId);
    await repository.setChecked(sessionId, entries[0].id, true);
    await repository.setChecked(sessionId, entries[1].id, true);
    final checkedBefore = await readRawEntries(sessionId);

    await repository.complete(sessionId);

    final checkedAfter = await readRawEntries(sessionId);
    expect((await repository.getById(sessionId)).status, 'COMPLETED');
    expect(checkedAfter.map((entry) => entry.checked), [1, 1]);
    expect(checkedAfter.map((entry) => entry.checkedAt), [
      checkedBefore[0].checkedAt,
      checkedBefore[1].checkedAt,
    ]);
  });

  test('rolls back snapshot updates when completion fails', () async {
    final locationId = await insertLocation('Bedroom');
    final itemId = await createItem(name: 'Old name', locationId: locationId);
    final sessionId = await repository.createDirect(
      title: 'Failed completion',
      entries: [SessionEntryInput.registered(itemId: itemId)],
    );
    final before = (await readRawEntries(sessionId)).single;

    await database.customStatement('''
      CREATE TRIGGER fail_session_completion
      BEFORE UPDATE OF status ON outgoing_sessions
      WHEN NEW.status = 'COMPLETED'
      BEGIN
        SELECT RAISE(ABORT, 'forced completion failure');
      END
    ''');

    await expectLater(
      repository.complete(sessionId, confirmedUnchecked: true),
      sessionError(SessionRepositoryErrorCode.dataInconsistency),
    );

    await database.customStatement('DROP TRIGGER fail_session_completion');
    final after = (await readRawEntries(sessionId)).single;
    expect((await repository.getById(sessionId)).status, 'IN_PROGRESS');
    expect(after.nameSnapshot, before.nameSnapshot);
    expect(after.locationSnapshot, before.locationSnapshot);
    expect(after.checked, before.checked);
  });

  test(
    'allows editing tasks, but rejects every mutation after completion',
    () async {
      final sessionId = await repository.createDirect(
        title: 'Read only',
        entries: const [SessionEntryInput.text(textName: 'A')],
      );
      final entryId = (await readRawEntries(sessionId)).single.id;
      await repository.setChecked(sessionId, entryId, true);
      await repository.complete(sessionId);

      await expectLater(
        repository.renameActive(sessionId: sessionId, title: 'Changed'),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.addEntry(
          sessionId: sessionId,
          entry: const SessionEntryInput.text(textName: 'B'),
        ),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.updateEntry(
          sessionId: sessionId,
          entryId: entryId,
          entry: const SessionEntryInput.text(textName: 'Changed'),
        ),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.updateEntryQuantity(
          sessionId: sessionId,
          entryId: entryId,
          requiredQuantity: 2,
        ),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.renameTextEntry(
          sessionId: sessionId,
          entryId: entryId,
          name: 'Changed',
        ),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.removeEntry(sessionId: sessionId, entryId: entryId),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.reorderEntries(
          sessionId: sessionId,
          orderedEntryIds: [entryId],
        ),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.setChecked(sessionId, entryId, false),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.complete(sessionId),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );
      await expectLater(
        repository.deleteActiveConfirmed(sessionId),
        sessionError(SessionRepositoryErrorCode.completedSessionReadOnly),
      );

      final entry = (await repository.listEntries(sessionId)).single;
      expect(entry.displayName, 'A');
      expect(entry.isChecked, isTrue);
    },
  );

  test('deletes an active task and cascades only its entries', () async {
    final locationId = await insertLocation('Bedroom');
    final itemId = await createItem(name: 'Keys', locationId: locationId);
    final templateId = await templateRepository.create(
      name: 'Keep me',
      entries: [TemplateEntryInput.registered(itemId: itemId)],
    );
    final sessionId = await repository.createFromTemplate(templateId);
    await repository.deleteActiveConfirmed(sessionId);

    expect(await repository.findById(sessionId), isNull);
    expect(
      await (database.select(
        database.sessionItems,
      )..where((table) => table.sessionId.equals(sessionId))).get(),
      isEmpty,
    );
    expect(await itemRepository.getById(itemId), isA<Item>());
    expect(
      await templateRepository.getById(templateId),
      isA<OutgoingTemplate>(),
    );
  });

  test(
    'does not leave orphan session items after failures or deletes',
    () async {
      final sessionId = await repository.createDirect(
        title: 'No orphans',
        entries: const [SessionEntryInput.text(textName: 'A')],
      );

      await database.customStatement('''
      CREATE TRIGGER fail_direct_session_insert
      BEFORE INSERT ON session_items
      BEGIN
        SELECT RAISE(ABORT, 'forced direct insert failure');
      END
    ''');
      await expectLater(
        repository.createDirect(
          title: 'Failed direct create',
          entries: const [SessionEntryInput.text(textName: 'B')],
        ),
        sessionError(SessionRepositoryErrorCode.dataInconsistency),
      );
      await database.customStatement('DROP TRIGGER fail_direct_session_insert');

      await repository.deleteActiveConfirmed(sessionId);

      final orphanRows = await database.customSelect('''
      SELECT si.id
      FROM session_items si
      LEFT JOIN outgoing_sessions s ON s.id = si.session_id
      WHERE s.id IS NULL
    ''').get();
      final foreignKeyProblems = await database
          .customSelect('PRAGMA foreign_key_check')
          .get();

      expect(orphanRows, isEmpty);
      expect(foreignKeyProblems, isEmpty);
    },
  );

  test('distinguishes missing task and missing task entry errors', () async {
    await expectLater(
      repository.getById(9999),
      sessionError(SessionRepositoryErrorCode.sessionNotFound),
    );
    await expectLater(
      repository.listEntries(9999),
      sessionError(SessionRepositoryErrorCode.sessionNotFound),
    );

    final sessionId = await repository.createDirect(
      title: 'Existing',
      entries: const [SessionEntryInput.text(textName: 'A')],
    );
    await expectLater(
      repository.setChecked(sessionId, 9999, true),
      sessionError(SessionRepositoryErrorCode.sessionItemNotFound),
    );
    expect(await repository.listEntries(sessionId), hasLength(1));
  });
}
