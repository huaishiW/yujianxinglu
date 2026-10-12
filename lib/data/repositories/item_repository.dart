import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../local/app_database.dart';

enum ItemRepositoryErrorCode {
  invalidName,
  invalidQuantity,
  itemNotFound,
  locationNotFound,
  dataInconsistency,
}

class ItemRepositoryException extends AppException {
  const ItemRepositoryException(this.code, String message, {super.cause})
    : super(message);

  final ItemRepositoryErrorCode code;

  @override
  String toString() {
    final causeText = cause == null ? '' : ': $cause';
    return '$message$causeText';
  }
}

class ItemTemplateReference {
  const ItemTemplateReference({required this.template, required this.item});

  final OutgoingTemplate template;
  final TemplateItem item;
}

class ItemSessionReference {
  const ItemSessionReference({required this.session, required this.item});

  final OutgoingSession session;
  final SessionItem item;
}

class ItemDeletionImpact {
  const ItemDeletionImpact({
    required this.item,
    required this.templateReferences,
    required this.inProgressReferences,
    required this.completedReferences,
  });

  final Item item;
  final List<ItemTemplateReference> templateReferences;
  final List<ItemSessionReference> inProgressReferences;
  final List<ItemSessionReference> completedReferences;

  bool get hasReferences =>
      templateReferences.isNotEmpty ||
      inProgressReferences.isNotEmpty ||
      completedReferences.isNotEmpty;

  bool get hasCompletedHistory => completedReferences.isNotEmpty;
}

class ItemRepository {
  ItemRepository(this.db);

  final AppDatabase db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  String _normalizeName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const ItemRepositoryException(
        ItemRepositoryErrorCode.invalidName,
        '物品名称不能为空',
      );
    }
    return normalized;
  }

  void _validateQuantity(int quantity) {
    if (quantity < 1) {
      throw const ItemRepositoryException(
        ItemRepositoryErrorCode.invalidQuantity,
        '物品数量必须是正整数',
      );
    }
  }

  Future<Item?> findById(int id) {
    return (db.select(
      db.items,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<Item> getById(int id) async {
    final item = await findById(id);
    if (item == null) {
      throw const ItemRepositoryException(
        ItemRepositoryErrorCode.itemNotFound,
        '物品不存在',
      );
    }
    return item;
  }

  Future<int> create({
    required String name,
    int quantity = 1,
    required int locationId,
    String? category,
    String? note,
  }) async {
    final normalizedName = _normalizeName(name);
    _validateQuantity(quantity);

    return db.transaction(() async {
      await _requireLocation(locationId);
      final timestamp = _now();
      return db
          .into(db.items)
          .insert(
            ItemsCompanion(
              name: Value(normalizedName),
              quantity: Value(quantity),
              locationId: Value(locationId),
              category: Value(category),
              note: Value(note),
              createdAt: Value(timestamp),
              updatedAt: Value(timestamp),
            ),
          );
    });
  }

  Future<List<Item>> listByLocation(int locationId) async {
    await _requireLocation(locationId);

    final query = db.select(db.items)
      ..where((table) => table.locationId.equals(locationId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.name),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<List<Item>> searchByName(String keyword) {
    final normalizedKeyword = keyword.trim();
    final query = db.select(db.items)
      ..orderBy([
        (table) => OrderingTerm(expression: table.name),
        (table) => OrderingTerm(expression: table.id),
      ]);
    if (normalizedKeyword.isNotEmpty) {
      query.where((table) => table.name.contains(normalizedKeyword));
    }
    return query.get();
  }

  Future<String> fullLocationPath(int itemId) {
    return db.transaction(() async {
      final item = await _requireItem(itemId);
      return _fullLocationPath(item.locationId);
    });
  }

  Future<Item> update({
    required int id,
    String? name,
    int? quantity,
    int? locationId,
    Value<String?> category = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) async {
    final normalizedName = name == null ? null : _normalizeName(name);
    if (quantity != null) {
      _validateQuantity(quantity);
    }

    return db.transaction(() async {
      final current = await _requireItem(id);
      if (locationId != null) {
        await _requireLocation(locationId);
      }

      final hasChanges =
          name != null ||
          quantity != null ||
          locationId != null ||
          category.present ||
          note.present;
      if (!hasChanges) {
        return current;
      }

      final updated =
          await (db.update(
            db.items,
          )..where((table) => table.id.equals(id))).write(
            ItemsCompanion(
              name: normalizedName == null
                  ? const Value.absent()
                  : Value(normalizedName),
              quantity: quantity == null
                  ? const Value.absent()
                  : Value(quantity),
              locationId: locationId == null
                  ? const Value.absent()
                  : Value(locationId),
              category: category,
              note: note,
              updatedAt: Value(_now()),
            ),
          );
      if (updated != 1) {
        throw const ItemRepositoryException(
          ItemRepositoryErrorCode.dataInconsistency,
          '更新物品时数据状态发生变化',
        );
      }

      return _requireItem(id);
    });
  }

  Future<ItemDeletionImpact> queryDeletionImpact(int itemId) {
    return db.transaction(() async {
      final item = await _requireItem(itemId);

      final templateRows =
          await (db.select(db.templateItems).join([
                  innerJoin(
                    db.outgoingTemplates,
                    db.outgoingTemplates.id.equalsExp(
                      db.templateItems.templateId,
                    ),
                  ),
                ])
                ..where(db.templateItems.itemId.equals(itemId))
                ..orderBy([OrderingTerm(expression: db.templateItems.id)]))
              .get();
      final templateReferences = templateRows
          .map(
            (row) => ItemTemplateReference(
              template: row.readTable(db.outgoingTemplates),
              item: row.readTable(db.templateItems),
            ),
          )
          .toList(growable: false);

      final sessionRows =
          await (db.select(db.sessionItems).join([
                  innerJoin(
                    db.outgoingSessions,
                    db.outgoingSessions.id.equalsExp(db.sessionItems.sessionId),
                  ),
                ])
                ..where(db.sessionItems.itemId.equals(itemId))
                ..orderBy([OrderingTerm(expression: db.sessionItems.id)]))
              .get();

      final inProgressReferences = <ItemSessionReference>[];
      final completedReferences = <ItemSessionReference>[];
      for (final row in sessionRows) {
        final reference = ItemSessionReference(
          session: row.readTable(db.outgoingSessions),
          item: row.readTable(db.sessionItems),
        );
        switch (reference.session.status) {
          case 'IN_PROGRESS':
            inProgressReferences.add(reference);
          case 'COMPLETED':
            completedReferences.add(reference);
          default:
            throw const ItemRepositoryException(
              ItemRepositoryErrorCode.dataInconsistency,
              '出门记录包含未知状态',
            );
        }
      }

      return ItemDeletionImpact(
        item: item,
        templateReferences: templateReferences,
        inProgressReferences: List.unmodifiable(inProgressReferences),
        completedReferences: List.unmodifiable(completedReferences),
      );
    });
  }

  Future<void> deleteById(int itemId) async {
    try {
      await db.transaction(() async {
        final item = await _requireItem(itemId);
        final locationPath = await _fullLocationPath(item.locationId);

        final templateItems = await (db.select(
          db.templateItems,
        )..where((table) => table.itemId.equals(itemId))).get();
        for (final templateItem in templateItems) {
          final updated =
              await (db.update(
                db.templateItems,
              )..where((table) => table.id.equals(templateItem.id))).write(
                TemplateItemsCompanion(
                  itemType: const Value('TEXT_ITEM'),
                  itemId: const Value(null),
                  textName: Value(item.name),
                ),
              );
          _ensureUpdated(updated, expected: 1, message: '转换模板条目失败');
        }

        final sessionRows =
            await (db.select(db.sessionItems).join([
                  innerJoin(
                    db.outgoingSessions,
                    db.outgoingSessions.id.equalsExp(db.sessionItems.sessionId),
                  ),
                ])..where(
                  db.sessionItems.itemId.equals(itemId) &
                      db.outgoingSessions.status.equals('IN_PROGRESS'),
                ))
                .get();
        for (final row in sessionRows) {
          final sessionItem = row.readTable(db.sessionItems);
          final updated =
              await (db.update(
                db.sessionItems,
              )..where((table) => table.id.equals(sessionItem.id))).write(
                SessionItemsCompanion(
                  itemType: const Value('TEXT_ITEM'),
                  itemId: const Value(null),
                  textName: Value(item.name),
                  nameSnapshot: Value(item.name),
                  locationSnapshot: Value(locationPath),
                ),
              );
          _ensureUpdated(updated, expected: 1, message: '转换进行中清单条目失败');
        }

        final deleted = await (db.delete(
          db.items,
        )..where((table) => table.id.equals(itemId))).go();
        _ensureUpdated(deleted, expected: 1, message: '删除物品失败');

        final remainingTemplateItems = await (db.select(
          db.templateItems,
        )..where((table) => table.itemId.equals(itemId))).get();
        final remainingSessionItems = await (db.select(
          db.sessionItems,
        )..where((table) => table.itemId.equals(itemId))).get();
        if (remainingTemplateItems.isNotEmpty ||
            remainingSessionItems.isNotEmpty) {
          throw const ItemRepositoryException(
            ItemRepositoryErrorCode.dataInconsistency,
            '物品删除后仍存在未解除的关联条目',
          );
        }
      });
    } on ItemRepositoryException {
      rethrow;
    } catch (error) {
      throw ItemRepositoryException(
        ItemRepositoryErrorCode.dataInconsistency,
        '删除物品及其关联条目转换失败',
        cause: error,
      );
    }
  }

  Future<Item> _requireItem(int id) async {
    final item = await (db.select(
      db.items,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (item == null) {
      throw const ItemRepositoryException(
        ItemRepositoryErrorCode.itemNotFound,
        '物品不存在',
      );
    }
    return item;
  }

  Future<void> _requireLocation(int id) async {
    final location = await (db.select(
      db.locations,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (location == null) {
      throw const ItemRepositoryException(
        ItemRepositoryErrorCode.locationNotFound,
        '收纳位置不存在',
      );
    }
  }

  Future<String> _fullLocationPath(int locationId) async {
    final segments = <String>[];
    final visited = <int>{};
    var current = await (db.select(
      db.locations,
    )..where((table) => table.id.equals(locationId))).getSingleOrNull();

    if (current == null) {
      throw const ItemRepositoryException(
        ItemRepositoryErrorCode.dataInconsistency,
        '物品关联的收纳位置不存在',
      );
    }

    while (current != null) {
      if (!visited.add(current.id)) {
        throw const ItemRepositoryException(
          ItemRepositoryErrorCode.dataInconsistency,
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
        throw const ItemRepositoryException(
          ItemRepositoryErrorCode.dataInconsistency,
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
      throw ItemRepositoryException(
        ItemRepositoryErrorCode.dataInconsistency,
        message,
      );
    }
  }
}
