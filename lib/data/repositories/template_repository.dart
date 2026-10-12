import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../local/app_database.dart';

const registeredTemplateItemType = 'REGISTERED_ITEM';
const textTemplateItemType = 'TEXT_ITEM';

enum TemplateRepositoryErrorCode {
  templateNotFound,
  invalidTemplateName,
  emptyTemplate,
  templateItemNotFound,
  invalidItemName,
  invalidRequiredQuantity,
  itemNotFound,
  duplicateRegisteredItem,
  invalidItem,
  dataInconsistency,
}

class TemplateRepositoryException extends AppException {
  const TemplateRepositoryException(this.code, String message, {super.cause})
    : super(message);

  final TemplateRepositoryErrorCode code;

  @override
  String toString() {
    final causeText = cause == null ? '' : ': $cause';
    return '$message$causeText';
  }
}

class TemplateEntryInput {
  const TemplateEntryInput.registered({
    required this.itemId,
    this.requiredQuantity = 1,
    this.sortOrder,
  }) : itemType = registeredTemplateItemType,
       textName = null;

  const TemplateEntryInput.text({
    required this.textName,
    this.requiredQuantity = 1,
    this.sortOrder,
  }) : itemType = textTemplateItemType,
       itemId = null;

  const TemplateEntryInput.raw({
    required this.itemType,
    this.itemId,
    this.textName,
    this.requiredQuantity = 1,
    this.sortOrder,
  });

  final String itemType;
  final int? itemId;
  final String? textName;
  final int requiredQuantity;
  final int? sortOrder;
}

class TemplateDetail {
  const TemplateDetail({required this.template, required this.entries});

  final OutgoingTemplate template;
  final List<TemplateEntryDetail> entries;
}

class TemplateEntryDetail {
  const TemplateEntryDetail({
    required this.entry,
    this.registeredItem,
    this.locationPath,
  });

  final TemplateItem entry;
  final Item? registeredItem;
  final String? locationPath;

  bool get isRegisteredItem => entry.itemType == registeredTemplateItemType;

  String get displayName {
    if (isRegisteredItem) {
      return registeredItem!.name;
    }
    return entry.textName!;
  }
}

class TemplateQuantityShortage {
  const TemplateQuantityShortage({required this.entry, required this.item});

  final TemplateItem entry;
  final Item item;

  int get itemId => item.id;
  int get currentQuantity => item.quantity;
  int get requiredQuantity => entry.requiredQuantity;
  int get shortage => entry.requiredQuantity - item.quantity;
}

class TemplateRepository {
  TemplateRepository(this.db);

  final AppDatabase db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  String _normalizeTemplateName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.invalidTemplateName,
        '模板名称不能为空',
      );
    }
    return normalized;
  }

  String _normalizeItemName(String? name) {
    final normalized = name?.trim() ?? '';
    if (normalized.isEmpty) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.invalidItemName,
        '模板条目名称不能为空',
      );
    }
    return normalized;
  }

  void _validateRequiredQuantity(int requiredQuantity) {
    if (requiredQuantity < 1) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.invalidRequiredQuantity,
        '模板条目所需数量必须是正整数',
      );
    }
  }

  Future<OutgoingTemplate?> findById(int id) {
    return (db.select(
      db.outgoingTemplates,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<OutgoingTemplate> getById(int id) async {
    final template = await findById(id);
    if (template == null) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.templateNotFound,
        '出门模板不存在',
      );
    }
    return template;
  }

  Future<int> create({
    required String name,
    String? description,
    required List<TemplateEntryInput> entries,
  }) async {
    final normalizedName = _normalizeTemplateName(name);
    if (entries.isEmpty) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.emptyTemplate,
        '模板至少需要一个条目',
      );
    }

    return _runWithDataGuard('创建模板失败', () {
      return db.transaction(() async {
        final timestamp = _now();
        final templateId = await db
            .into(db.outgoingTemplates)
            .insert(
              OutgoingTemplatesCompanion(
                name: Value(normalizedName),
                description: Value(description),
                createdAt: Value(timestamp),
                updatedAt: Value(timestamp),
              ),
            );

        for (var index = 0; index < entries.length; index += 1) {
          final normalized = await _normalizeEntryInput(
            entries[index],
            templateId: templateId,
            fallbackSortOrder: index,
          );
          await db.into(db.templateItems).insert(normalized.toCompanion());
        }

        return templateId;
      });
    });
  }

  Future<List<OutgoingTemplate>> listAll() {
    final query = db.select(db.outgoingTemplates)
      ..orderBy([
        (table) => OrderingTerm(expression: table.name),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<List<OutgoingTemplate>> listRecentlyUsed({int? limit}) {
    final query = db.select(db.outgoingTemplates)
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.lastUsedAt, mode: OrderingMode.desc),
        (table) =>
            OrderingTerm(expression: table.createdAt, mode: OrderingMode.desc),
        (table) => OrderingTerm(expression: table.id, mode: OrderingMode.desc),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    return query.get();
  }

  Future<List<OutgoingTemplate>> searchByName(String keyword) {
    final normalizedKeyword = keyword.trim();
    final query = db.select(db.outgoingTemplates)
      ..orderBy([
        (table) => OrderingTerm(expression: table.name),
        (table) => OrderingTerm(expression: table.id),
      ]);
    if (normalizedKeyword.isNotEmpty) {
      query.where((table) => table.name.contains(normalizedKeyword));
    }
    return query.get();
  }

  Future<TemplateDetail> getDetail(int templateId) {
    return db.transaction(() async {
      final template = await _requireTemplate(templateId);
      final entries = await _readEntryDetails(templateId);
      return TemplateDetail(
        template: template,
        entries: List.unmodifiable(entries),
      );
    });
  }

  Future<List<TemplateEntryDetail>> listEntries(int templateId) {
    return db.transaction(() async {
      await _requireTemplate(templateId);
      return List.unmodifiable(await _readEntryDetails(templateId));
    });
  }

  Future<OutgoingTemplate> updateTemplate({
    required int id,
    String? name,
    Value<String?> description = const Value.absent(),
  }) async {
    final normalizedName = name == null ? null : _normalizeTemplateName(name);

    return _runWithDataGuard('更新模板失败', () {
      return db.transaction(() async {
        final current = await _requireTemplate(id);
        if (normalizedName == null && !description.present) {
          return current;
        }

        final updated =
            await (db.update(
              db.outgoingTemplates,
            )..where((table) => table.id.equals(id))).write(
              OutgoingTemplatesCompanion(
                name: normalizedName == null
                    ? const Value.absent()
                    : Value(normalizedName),
                description: description,
                updatedAt: Value(_now()),
              ),
            );
        _ensureUpdated(updated, expected: 1, message: '更新模板失败');
        return _requireTemplate(id);
      });
    });
  }

  Future<int> addEntry({
    required int templateId,
    required TemplateEntryInput entry,
  }) {
    return _runWithDataGuard('新增模板条目失败', () {
      return db.transaction(() async {
        await _requireTemplate(templateId);
        final normalized = await _normalizeEntryInput(
          entry,
          templateId: templateId,
          fallbackSortOrder: await _nextSortOrder(templateId),
        );
        final id = await db
            .into(db.templateItems)
            .insert(normalized.toCompanion());
        await _touchTemplate(templateId);
        return id;
      });
    });
  }

  Future<TemplateItem> updateEntry({
    required int entryId,
    required TemplateEntryInput entry,
  }) {
    return _runWithDataGuard('更新模板条目失败', () {
      return db.transaction(() async {
        final current = await _requireEntry(entryId);
        final normalized = await _normalizeEntryInput(
          entry,
          templateId: current.templateId,
          excludingEntryId: entryId,
          fallbackSortOrder: current.sortOrder,
        );

        final updated =
            await (db.update(db.templateItems)
                  ..where((table) => table.id.equals(entryId)))
                .write(normalized.toCompanion());
        _ensureUpdated(updated, expected: 1, message: '更新模板条目失败');
        await _touchTemplate(current.templateId);
        return _requireEntry(entryId);
      });
    });
  }

  Future<TemplateItem> updateEntryQuantity({
    required int entryId,
    required int requiredQuantity,
  }) async {
    _validateRequiredQuantity(requiredQuantity);

    return _runWithDataGuard('更新模板条目数量失败', () {
      return db.transaction(() async {
        final current = await _requireEntry(entryId);
        final updated =
            await (db.update(
              db.templateItems,
            )..where((table) => table.id.equals(entryId))).write(
              TemplateItemsCompanion(requiredQuantity: Value(requiredQuantity)),
            );
        _ensureUpdated(updated, expected: 1, message: '更新模板条目数量失败');
        await _touchTemplate(current.templateId);
        return _requireEntry(entryId);
      });
    });
  }

  Future<TemplateDetail> replaceEntries({
    required int templateId,
    required List<TemplateEntryInput> entries,
  }) {
    return _runWithDataGuard('保存模板条目失败', () {
      return db.transaction(() async {
        await _requireTemplate(templateId);
        if (entries.isEmpty) {
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.emptyTemplate,
            '模板至少需要一个条目',
          );
        }

        final normalizedEntries = <_NormalizedTemplateEntry>[];
        final registeredItemIds = <int>{};
        for (var index = 0; index < entries.length; index += 1) {
          final normalized = await _normalizeEntryInput(
            entries[index],
            templateId: templateId,
            fallbackSortOrder: index,
            checkExistingRegisteredItem: false,
          );
          final itemId = normalized.itemId;
          if (itemId != null && !registeredItemIds.add(itemId)) {
            throw const TemplateRepositoryException(
              TemplateRepositoryErrorCode.duplicateRegisteredItem,
              '同一模板中不能重复添加同一个登记物品',
            );
          }
          normalizedEntries.add(normalized);
        }

        final currentEntries = await _readEntries(templateId);
        final deleted = await (db.delete(
          db.templateItems,
        )..where((table) => table.templateId.equals(templateId))).go();
        _ensureUpdated(
          deleted,
          expected: currentEntries.length,
          message: '保存模板条目失败',
        );

        for (final normalized in normalizedEntries) {
          await db.into(db.templateItems).insert(normalized.toCompanion());
        }
        await _touchTemplate(templateId);

        return TemplateDetail(
          template: await _requireTemplate(templateId),
          entries: List.unmodifiable(await _readEntryDetails(templateId)),
        );
      });
    });
  }

  Future<void> removeEntry(int entryId) {
    return _runWithDataGuard('删除模板条目失败', () {
      return db.transaction(() async {
        final current = await _requireEntry(entryId);
        final count = await _entryCount(current.templateId);
        if (count <= 1) {
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.emptyTemplate,
            '不能删除模板的最后一个条目',
          );
        }

        final deleted = await (db.delete(
          db.templateItems,
        )..where((table) => table.id.equals(entryId))).go();
        _ensureUpdated(deleted, expected: 1, message: '删除模板条目失败');
        await _touchTemplate(current.templateId);
      });
    });
  }

  Future<void> reorderEntries({
    required int templateId,
    required List<int> orderedEntryIds,
  }) {
    return _runWithDataGuard('调整模板条目排序失败', () {
      return db.transaction(() async {
        await _requireTemplate(templateId);
        final currentEntries = await _readEntries(templateId);
        if (currentEntries.isEmpty) {
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.emptyTemplate,
            '模板至少需要一个条目',
          );
        }

        final currentIds = currentEntries.map((entry) => entry.id).toSet();
        final orderedIds = orderedEntryIds.toSet();
        if (orderedIds.length != orderedEntryIds.length ||
            orderedIds.length != currentIds.length ||
            !orderedIds.containsAll(currentIds)) {
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.templateItemNotFound,
            '排序列表必须包含模板的全部条目',
          );
        }

        for (var index = 0; index < orderedEntryIds.length; index += 1) {
          final updated =
              await (db.update(db.templateItems)
                    ..where((table) => table.id.equals(orderedEntryIds[index])))
                  .write(TemplateItemsCompanion(sortOrder: Value(index)));
          _ensureUpdated(updated, expected: 1, message: '调整模板条目排序失败');
        }
        await _touchTemplate(templateId);
      });
    });
  }

  Future<void> deleteById(int templateId) {
    return _runWithDataGuard('删除模板失败', () {
      return db.transaction(() async {
        await _requireTemplate(templateId);
        final deleted = await (db.delete(
          db.outgoingTemplates,
        )..where((table) => table.id.equals(templateId))).go();
        _ensureUpdated(deleted, expected: 1, message: '删除模板失败');
      });
    });
  }

  Future<List<TemplateQuantityShortage>> listQuantityShortages(int templateId) {
    return db.transaction(() async {
      await _requireTemplate(templateId);
      final rows =
          await (db.select(db.templateItems).join([
                  innerJoin(
                    db.items,
                    db.items.id.equalsExp(db.templateItems.itemId),
                  ),
                ])
                ..where(
                  db.templateItems.templateId.equals(templateId) &
                      db.templateItems.itemType.equals(
                        registeredTemplateItemType,
                      ) &
                      db.templateItems.requiredQuantity.isBiggerThan(
                        db.items.quantity,
                      ),
                )
                ..orderBy([
                  OrderingTerm(expression: db.templateItems.sortOrder),
                  OrderingTerm(expression: db.templateItems.id),
                ]))
              .get();

      return List.unmodifiable(
        rows.map((row) {
          return TemplateQuantityShortage(
            entry: row.readTable(db.templateItems),
            item: row.readTable(db.items),
          );
        }),
      );
    });
  }

  Future<T> _runWithDataGuard<T>(
    String message,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on TemplateRepositoryException {
      rethrow;
    } catch (error) {
      throw TemplateRepositoryException(
        TemplateRepositoryErrorCode.dataInconsistency,
        message,
        cause: error,
      );
    }
  }

  Future<OutgoingTemplate> _requireTemplate(int id) async {
    final template = await (db.select(
      db.outgoingTemplates,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (template == null) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.templateNotFound,
        '出门模板不存在',
      );
    }
    return template;
  }

  Future<TemplateItem> _requireEntry(int id) async {
    final entry = await (db.select(
      db.templateItems,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (entry == null) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.templateItemNotFound,
        '模板条目不存在',
      );
    }
    return entry;
  }

  Future<Item> _requireItem(int id) async {
    final item = await (db.select(
      db.items,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (item == null) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.itemNotFound,
        '登记物品不存在',
      );
    }
    return item;
  }

  Future<_NormalizedTemplateEntry> _normalizeEntryInput(
    TemplateEntryInput input, {
    required int templateId,
    required int fallbackSortOrder,
    int? excludingEntryId,
    bool checkExistingRegisteredItem = true,
  }) async {
    _validateRequiredQuantity(input.requiredQuantity);
    final sortOrder = input.sortOrder ?? fallbackSortOrder;
    if (sortOrder < 0) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.invalidItem,
        '模板条目排序值不能为负数',
      );
    }

    switch (input.itemType) {
      case registeredTemplateItemType:
        if (input.itemId == null || input.textName != null) {
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.invalidItem,
            '登记物品条目字段组合不合法',
          );
        }
        await _requireItem(input.itemId!);
        if (checkExistingRegisteredItem &&
            await _hasRegisteredItem(
              templateId: templateId,
              itemId: input.itemId!,
              excludingEntryId: excludingEntryId,
            )) {
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.duplicateRegisteredItem,
            '同一模板中不能重复添加同一个登记物品',
          );
        }
        return _NormalizedTemplateEntry(
          templateId: templateId,
          itemType: registeredTemplateItemType,
          itemId: input.itemId,
          textName: null,
          requiredQuantity: input.requiredQuantity,
          sortOrder: sortOrder,
        );
      case textTemplateItemType:
        if (input.itemId != null) {
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.invalidItem,
            '普通文本条目不能保存物品引用',
          );
        }
        return _NormalizedTemplateEntry(
          templateId: templateId,
          itemType: textTemplateItemType,
          itemId: null,
          textName: _normalizeItemName(input.textName),
          requiredQuantity: input.requiredQuantity,
          sortOrder: sortOrder,
        );
      default:
        throw const TemplateRepositoryException(
          TemplateRepositoryErrorCode.invalidItem,
          '模板条目类型不合法',
        );
    }
  }

  Future<bool> _hasRegisteredItem({
    required int templateId,
    required int itemId,
    int? excludingEntryId,
  }) async {
    final query = db.select(db.templateItems)
      ..where(
        (table) =>
            table.templateId.equals(templateId) &
            table.itemType.equals(registeredTemplateItemType) &
            table.itemId.equals(itemId),
      )
      ..limit(1);
    final rows = await query.get();
    return rows.any((entry) => entry.id != excludingEntryId);
  }

  Future<List<TemplateItem>> _readEntries(int templateId) {
    final query = db.select(db.templateItems)
      ..where((table) => table.templateId.equals(templateId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.sortOrder),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<List<TemplateEntryDetail>> _readEntryDetails(int templateId) async {
    final entries = await _readEntries(templateId);
    final details = <TemplateEntryDetail>[];
    for (final entry in entries) {
      switch (entry.itemType) {
        case registeredTemplateItemType:
          final itemId = entry.itemId;
          if (itemId == null || entry.textName != null) {
            throw const TemplateRepositoryException(
              TemplateRepositoryErrorCode.dataInconsistency,
              '登记物品条目字段组合不合法',
            );
          }
          final item = await _requireItem(itemId);
          details.add(
            TemplateEntryDetail(
              entry: entry,
              registeredItem: item,
              locationPath: await _fullLocationPath(item.locationId),
            ),
          );
        case textTemplateItemType:
          if (entry.itemId != null || entry.textName == null) {
            throw const TemplateRepositoryException(
              TemplateRepositoryErrorCode.dataInconsistency,
              '普通文本条目字段组合不合法',
            );
          }
          details.add(TemplateEntryDetail(entry: entry));
        default:
          throw const TemplateRepositoryException(
            TemplateRepositoryErrorCode.dataInconsistency,
            '模板条目包含未知类型',
          );
      }
    }
    return details;
  }

  Future<int> _entryCount(int templateId) async {
    final row = await db
        .customSelect(
          '''
          SELECT COUNT(*) AS entry_count
          FROM template_items
          WHERE template_id = ?
          ''',
          variables: [Variable.withInt(templateId)],
          readsFrom: {db.templateItems},
        )
        .getSingle();
    return row.read<int>('entry_count');
  }

  Future<int> _nextSortOrder(int templateId) async {
    final row = await db
        .customSelect(
          '''
          SELECT COALESCE(MAX(sort_order) + 1, 0) AS next_sort_order
          FROM template_items
          WHERE template_id = ?
          ''',
          variables: [Variable.withInt(templateId)],
          readsFrom: {db.templateItems},
        )
        .getSingle();
    return row.read<int>('next_sort_order');
  }

  Future<void> _touchTemplate(int templateId) async {
    final updated =
        await (db.update(db.outgoingTemplates)
              ..where((table) => table.id.equals(templateId)))
            .write(OutgoingTemplatesCompanion(updatedAt: Value(_now())));
    _ensureUpdated(updated, expected: 1, message: '更新模板修改时间失败');
  }

  Future<String> _fullLocationPath(int locationId) async {
    final segments = <String>[];
    final visited = <int>{};
    var current = await (db.select(
      db.locations,
    )..where((table) => table.id.equals(locationId))).getSingleOrNull();

    if (current == null) {
      throw const TemplateRepositoryException(
        TemplateRepositoryErrorCode.dataInconsistency,
        '物品关联的收纳位置不存在',
      );
    }

    while (current != null) {
      if (!visited.add(current.id)) {
        throw const TemplateRepositoryException(
          TemplateRepositoryErrorCode.dataInconsistency,
          '收纳位置存在循环引用',
        );
      }
      segments.insert(0, current.name);
      final parentId = current.parentId;
      if (parentId == null) {
        break;
      }
      current = await (db.select(
        db.locations,
      )..where((table) => table.id.equals(parentId))).getSingleOrNull();
      if (current == null) {
        throw const TemplateRepositoryException(
          TemplateRepositoryErrorCode.dataInconsistency,
          '收纳位置父级不存在',
        );
      }
    }

    return segments.join(' / ');
  }

  void _ensureUpdated(
    int actual, {
    required int expected,
    required String message,
  }) {
    if (actual != expected) {
      throw TemplateRepositoryException(
        TemplateRepositoryErrorCode.dataInconsistency,
        message,
      );
    }
  }
}

class _NormalizedTemplateEntry {
  const _NormalizedTemplateEntry({
    required this.templateId,
    required this.itemType,
    required this.itemId,
    required this.textName,
    required this.requiredQuantity,
    required this.sortOrder,
  });

  final int templateId;
  final String itemType;
  final int? itemId;
  final String? textName;
  final int requiredQuantity;
  final int sortOrder;

  TemplateItemsCompanion toCompanion() {
    return TemplateItemsCompanion(
      templateId: Value(templateId),
      itemType: Value(itemType),
      itemId: Value(itemId),
      textName: Value(textName),
      requiredQuantity: Value(requiredQuantity),
      sortOrder: Value(sortOrder),
    );
  }
}
