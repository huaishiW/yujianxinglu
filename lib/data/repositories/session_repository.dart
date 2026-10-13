import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../local/app_database.dart';
import 'template_repository.dart';

const registeredSessionItemType = registeredTemplateItemType;
const textSessionItemType = textTemplateItemType;

enum SessionRepositoryErrorCode {
  sessionNotFound,
  templateNotFound,
  invalidTitle,
  emptySession,
  sessionItemNotFound,
  invalidItemName,
  invalidRequiredQuantity,
  itemNotFound,
  duplicateRegisteredItem,
  invalidItem,
  completedSessionReadOnly,
  incompleteItemsConfirmationRequired,
  illegalStatusTransition,
  dataInconsistency,
}

class SessionRepositoryException extends AppException {
  const SessionRepositoryException(this.code, String message, {super.cause})
    : super(message);

  final SessionRepositoryErrorCode code;

  @override
  String toString() {
    final causeText = cause == null ? '' : ': $cause';
    return '$message$causeText';
  }
}

class SessionEntryInput {
  const SessionEntryInput.registered({
    required this.itemId,
    this.requiredQuantity = 1,
    this.sortOrder,
  }) : itemType = registeredSessionItemType,
       textName = null;

  const SessionEntryInput.text({
    required this.textName,
    this.requiredQuantity = 1,
    this.sortOrder,
  }) : itemType = textSessionItemType,
       itemId = null;

  const SessionEntryInput.raw({
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

class EditableSessionEntryInput {
  const EditableSessionEntryInput.registered({
    this.id,
    required this.itemId,
    this.requiredQuantity = 1,
  }) : itemType = registeredSessionItemType,
       textName = null;

  const EditableSessionEntryInput.text({
    this.id,
    required this.textName,
    this.requiredQuantity = 1,
  }) : itemType = textSessionItemType,
       itemId = null;

  const EditableSessionEntryInput.raw({
    this.id,
    required this.itemType,
    this.itemId,
    this.textName,
    this.requiredQuantity = 1,
  });

  final int? id;
  final String itemType;
  final int? itemId;
  final String? textName;
  final int requiredQuantity;
}

class SessionDetail {
  const SessionDetail({required this.session, required this.entries});

  final OutgoingSession session;
  final List<SessionEntryDetail> entries;

  int get checkedCount => entries.where((entry) => entry.isChecked).length;

  int get uncheckedCount => entries.length - checkedCount;
}

class SessionEntryDetail {
  const SessionEntryDetail({
    required this.entry,
    this.registeredItem,
    required this.locationPath,
    required this.isCompleted,
  });

  final SessionItem entry;
  final Item? registeredItem;
  final String? locationPath;
  final bool isCompleted;

  bool get isRegisteredItem => entry.itemType == registeredSessionItemType;

  bool get isChecked => entry.checked == 1;

  String get displayName {
    if (isCompleted) {
      return entry.nameSnapshot;
    }
    if (registeredItem != null) {
      return registeredItem!.name;
    }
    if (entry.itemType == textSessionItemType) {
      return entry.textName!;
    }
    return entry.nameSnapshot;
  }
}

class SessionQuantityShortage {
  const SessionQuantityShortage({required this.entry, required this.item});

  final SessionItem entry;
  final Item item;

  int get itemId => item.id;

  int get currentQuantity => item.quantity;

  int get requiredQuantity => entry.requiredQuantity;

  int get shortage => entry.requiredQuantity - item.quantity;
}

class SessionRepository {
  SessionRepository(this.db);

  final AppDatabase db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<Item?> _findItem(int id) {
    return (db.select(
      db.items,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<OutgoingSession?> findById(int id) {
    return (db.select(
      db.outgoingSessions,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<OutgoingSession> getById(int id) async {
    final session = await _requireSession(id);
    return session;
  }

  Future<String> getStatus(int sessionId) async {
    return (await _requireSession(sessionId)).status;
  }

  Future<List<OutgoingSession>> listActive() {
    final query = db.select(db.outgoingSessions)
      ..where((table) => table.status.equals('IN_PROGRESS'))
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.updatedAt, mode: OrderingMode.desc),
        (table) => OrderingTerm(expression: table.id, mode: OrderingMode.desc),
      ]);
    return query.get();
  }

  Future<List<OutgoingSession>> listInProgress() => listActive();

  Future<SessionDetail> getDetail(int sessionId) {
    return _runWithDataGuard('读取出门任务失败', () {
      return db.transaction(() async {
        final session = await _requireSession(sessionId);
        final entries = await _readEntryDetails(session);
        return SessionDetail(
          session: session,
          entries: List.unmodifiable(entries),
        );
      });
    });
  }

  Future<List<SessionEntryDetail>> listEntries(int sessionId) {
    return _runWithDataGuard('读取出门任务条目失败', () {
      return db.transaction(() async {
        final session = await _requireSession(sessionId);
        return List.unmodifiable(await _readEntryDetails(session));
      });
    });
  }

  Future<List<SessionEntryDetail>> listUncheckedEntries(int sessionId) async {
    final entries = await listEntries(sessionId);
    return List.unmodifiable(
      entries.where((entry) => !entry.isChecked).toList(),
    );
  }

  Future<int> countUncheckedEntries(int sessionId) async {
    await _requireSession(sessionId);
    final row = await db
        .customSelect(
          '''
          SELECT COUNT(*) AS unchecked_count
          FROM session_items
          WHERE session_id = ? AND checked = 0
          ''',
          variables: [Variable.withInt(sessionId)],
          readsFrom: {db.sessionItems},
        )
        .getSingle();
    return row.read<int>('unchecked_count');
  }

  Future<int> createDirect({
    required String title,
    required List<SessionEntryInput> entries,
  }) {
    return _runWithDataGuard('直接创建出门任务失败', () {
      return db.transaction(() async {
        final normalizedTitle = _normalizeTitle(title);
        final normalizedEntries = await _normalizeEntries(entries);
        final sessionId = await _insertSession(title: normalizedTitle);
        await _insertEntries(sessionId, normalizedEntries);
        return sessionId;
      });
    });
  }

  Future<int> createFromTemplate(int templateId, {String? title}) {
    return _runWithDataGuard('从模板创建出门任务失败', () {
      return db.transaction(() async {
        final template = await _requireTemplate(templateId);
        final templateEntries = await _readTemplateEntries(templateId);
        if (templateEntries.isEmpty) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.emptySession,
            '空模板不能创建出门任务',
          );
        }

        final normalizedEntries = <_NormalizedSessionEntry>[];
        final registeredItemIds = <int>{};
        for (final entry in templateEntries) {
          final normalized = await _normalizeTemplateEntry(entry);
          final itemId = normalized.itemId;
          if (itemId != null && !registeredItemIds.add(itemId)) {
            throw const SessionRepositoryException(
              SessionRepositoryErrorCode.duplicateRegisteredItem,
              '同一出门任务中不能重复关联同一件登记物品',
            );
          }
          normalizedEntries.add(normalized);
        }

        final normalizedTitle = _normalizeTitle(title ?? template.name);
        final sessionId = await _insertSession(
          title: normalizedTitle,
          templateId: templateId,
        );
        await _insertEntries(sessionId, normalizedEntries);

        final updated =
            await (db.update(db.outgoingTemplates)
                  ..where((table) => table.id.equals(templateId)))
                .write(OutgoingTemplatesCompanion(lastUsedAt: Value(_now())));
        _ensureUpdated(updated, expected: 1, message: '更新模板最近使用时间失败');

        return sessionId;
      });
    });
  }

  Future<OutgoingSession> renameActive({
    required int sessionId,
    required String title,
  }) {
    return _runWithDataGuard('修改出门任务名称失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final normalizedTitle = _normalizeTitle(title);
        final updated =
            await (db.update(
              db.outgoingSessions,
            )..where((table) => table.id.equals(sessionId))).write(
              OutgoingSessionsCompanion(
                title: Value(normalizedTitle),
                updatedAt: Value(_now()),
              ),
            );
        _ensureUpdated(updated, expected: 1, message: '修改出门任务名称失败');
        return _requireSession(sessionId);
      });
    });
  }

  Future<int> addEntry({
    required int sessionId,
    required SessionEntryInput entry,
  }) {
    return _runWithDataGuard('新增出门任务条目失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final fallbackSortOrder = await _nextSortOrder(sessionId);
        final normalized = await _normalizeEntryInput(
          entry,
          fallbackSortOrder: fallbackSortOrder,
        );
        if (normalized.itemId != null &&
            await _hasRegisteredItem(
              sessionId: sessionId,
              itemId: normalized.itemId!,
            )) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.duplicateRegisteredItem,
            '同一出门任务中不能重复关联同一件登记物品',
          );
        }

        final id = await db
            .into(db.sessionItems)
            .insert(_entryCompanion(sessionId, normalized));
        await _touchSession(sessionId);
        return id;
      });
    });
  }

  Future<SessionItem> updateEntry({
    required int sessionId,
    required int entryId,
    required SessionEntryInput entry,
  }) {
    return _runWithDataGuard('修改出门任务条目失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final current = await _requireEntry(sessionId, entryId);
        final normalized = await _normalizeEntryInput(
          entry,
          fallbackSortOrder: current.sortOrder,
        );
        if (normalized.itemId != null &&
            await _hasRegisteredItem(
              sessionId: sessionId,
              itemId: normalized.itemId!,
              excludingEntryId: entryId,
            )) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.duplicateRegisteredItem,
            '同一出门任务中不能重复关联同一件登记物品',
          );
        }

        final shouldResetChecked =
            current.itemType != normalized.itemType ||
            current.itemId != normalized.itemId ||
            (normalized.itemType == textSessionItemType &&
                current.textName != normalized.textName) ||
            current.requiredQuantity != normalized.requiredQuantity;
        final updated =
            await (db.update(
              db.sessionItems,
            )..where((table) => table.id.equals(entryId))).write(
              SessionItemsCompanion(
                itemType: Value(normalized.itemType),
                itemId: Value(normalized.itemId),
                textName: Value(normalized.textName),
                nameSnapshot: Value(normalized.nameSnapshot),
                locationSnapshot: Value(normalized.locationSnapshot),
                requiredQuantity: Value(normalized.requiredQuantity),
                checked: shouldResetChecked
                    ? const Value(0)
                    : const Value.absent(),
                checkedAt: shouldResetChecked
                    ? const Value(null)
                    : const Value.absent(),
                sortOrder: Value(normalized.sortOrder),
              ),
            );
        _ensureUpdated(updated, expected: 1, message: '修改出门任务条目失败');
        await _touchSession(sessionId);
        return _requireEntry(sessionId, entryId);
      });
    });
  }

  Future<SessionItem> updateEntryQuantity({
    required int sessionId,
    required int entryId,
    required int requiredQuantity,
  }) async {
    _validateRequiredQuantity(requiredQuantity);
    return _runWithDataGuard('修改出门任务条目数量失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final current = await _requireEntry(sessionId, entryId);
        final shouldResetChecked = current.requiredQuantity != requiredQuantity;
        final updated =
            await (db.update(
              db.sessionItems,
            )..where((table) => table.id.equals(entryId))).write(
              SessionItemsCompanion(
                requiredQuantity: Value(requiredQuantity),
                checked: shouldResetChecked
                    ? const Value(0)
                    : const Value.absent(),
                checkedAt: shouldResetChecked
                    ? const Value(null)
                    : const Value.absent(),
              ),
            );
        _ensureUpdated(updated, expected: 1, message: '修改出门任务条目数量失败');
        await _touchSession(sessionId);
        return _requireEntry(sessionId, entryId);
      });
    });
  }

  Future<SessionItem> renameTextEntry({
    required int sessionId,
    required int entryId,
    required String name,
  }) {
    return _runWithDataGuard('修改普通文本条目失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final current = await _requireEntry(sessionId, entryId);
        if (current.itemType != textSessionItemType) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.invalidItem,
            '只有普通文本条目可以直接修改名称',
          );
        }
        final normalizedName = _normalizeItemName(name);
        final shouldResetChecked = current.textName != normalizedName;
        final updated =
            await (db.update(
              db.sessionItems,
            )..where((table) => table.id.equals(entryId))).write(
              SessionItemsCompanion(
                textName: Value(normalizedName),
                nameSnapshot: Value(normalizedName),
                checked: shouldResetChecked
                    ? const Value(0)
                    : const Value.absent(),
                checkedAt: shouldResetChecked
                    ? const Value(null)
                    : const Value.absent(),
              ),
            );
        _ensureUpdated(updated, expected: 1, message: '修改普通文本条目失败');
        await _touchSession(sessionId);
        return _requireEntry(sessionId, entryId);
      });
    });
  }

  Future<void> removeEntry({required int sessionId, required int entryId}) {
    return _runWithDataGuard('删除出门任务条目失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        await _requireEntry(sessionId, entryId);
        final count = await _entryCount(sessionId);
        if (count <= 1) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.emptySession,
            '不能删除出门任务的最后一个条目',
          );
        }

        final deleted = await (db.delete(
          db.sessionItems,
        )..where((table) => table.id.equals(entryId))).go();
        _ensureUpdated(deleted, expected: 1, message: '删除出门任务条目失败');
        await _touchSession(sessionId);
      });
    });
  }

  Future<void> setChecked(int sessionId, int entryId, bool checked) {
    return _runWithDataGuard('更新出门任务勾选状态失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final current = await _requireEntry(sessionId, entryId);
        final currentChecked = current.checked == 1;
        if (currentChecked == checked) {
          return;
        }

        final updated =
            await (db.update(
              db.sessionItems,
            )..where((table) => table.id.equals(entryId))).write(
              SessionItemsCompanion(
                checked: Value(checked ? 1 : 0),
                checkedAt: Value(checked ? _now() : null),
              ),
            );
        _ensureUpdated(updated, expected: 1, message: '更新出门任务勾选状态失败');
        await _touchSession(sessionId);
      });
    });
  }

  Future<void> reorderEntries({
    required int sessionId,
    required List<int> orderedEntryIds,
  }) {
    return _runWithDataGuard('调整出门任务条目排序失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final currentEntries = await _readEntries(sessionId);
        final currentIds = currentEntries.map((entry) => entry.id).toSet();
        final orderedIds = orderedEntryIds.toSet();
        if (orderedEntryIds.length != orderedIds.length ||
            orderedIds.length != currentIds.length ||
            !orderedIds.containsAll(currentIds)) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.sessionItemNotFound,
            '排序列表必须包含出门任务的全部条目',
          );
        }

        for (var index = 0; index < orderedEntryIds.length; index += 1) {
          final updated =
              await (db.update(db.sessionItems)..where(
                    (table) =>
                        table.id.equals(orderedEntryIds[index]) &
                        table.sessionId.equals(sessionId),
                  ))
                  .write(SessionItemsCompanion(sortOrder: Value(index)));
          _ensureUpdated(updated, expected: 1, message: '调整出门任务条目排序失败');
        }
        await _touchSession(sessionId);
      });
    });
  }

  Future<SessionDetail> saveActiveSession({
    required int sessionId,
    required String title,
    required List<EditableSessionEntryInput> entries,
  }) {
    return _runWithDataGuard('保存出门任务失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final normalizedTitle = _normalizeTitle(title);
        if (entries.isEmpty) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.emptySession,
            '出门任务至少需要一个条目',
          );
        }

        final seenEntryIds = <int>{};
        for (final entry in entries) {
          if (entry.id != null && !seenEntryIds.add(entry.id!)) {
            throw const SessionRepositoryException(
              SessionRepositoryErrorCode.invalidItem,
              '同一出门任务编辑请求中已有条目 ID 不能重复',
            );
          }
        }

        final registeredItemIds = <int>{};
        for (final entry in entries) {
          if (entry.itemType == registeredSessionItemType &&
              entry.itemId != null) {
            if (!registeredItemIds.add(entry.itemId!)) {
              throw const SessionRepositoryException(
                SessionRepositoryErrorCode.duplicateRegisteredItem,
                '同一出门任务中不能重复关联同一件登记物品',
              );
            }
          }
        }

        final currentEntries = await _readEntries(sessionId);
        final currentMap = {for (final e in currentEntries) e.id: e};
        final retainedIds = <int>{};

        for (var index = 0; index < entries.length; index += 1) {
          final input = entries[index];
          _validateRequiredQuantity(input.requiredQuantity);

          if (input.id != null) {
            final entryId = input.id!;
            final current = currentMap[entryId];
            if (current == null) {
              throw const SessionRepositoryException(
                SessionRepositoryErrorCode.sessionItemNotFound,
                '出门任务条目不存在或不属于当前任务',
              );
            }
            if (!retainedIds.add(entryId)) {
              throw const SessionRepositoryException(
                SessionRepositoryErrorCode.invalidItem,
                '同一出门任务编辑请求中已有条目 ID 不能重复',
              );
            }

            switch (input.itemType) {
              case registeredSessionItemType:
                if (input.itemId == null || input.textName != null) {
                  throw const SessionRepositoryException(
                    SessionRepositoryErrorCode.invalidItem,
                    '登记物品条目字段组合无效',
                  );
                }
                final live = await _readLiveItem(input.itemId!);
                final shouldResetChecked =
                    current.itemType != registeredSessionItemType ||
                    current.itemId != input.itemId ||
                    current.requiredQuantity != input.requiredQuantity;

                final updated =
                    await (db.update(
                      db.sessionItems,
                    )..where((t) => t.id.equals(entryId))).write(
                      SessionItemsCompanion(
                        itemType: const Value(registeredSessionItemType),
                        itemId: Value(input.itemId),
                        textName: const Value(null),
                        nameSnapshot: Value(live.item.name),
                        locationSnapshot: Value(live.locationPath),
                        requiredQuantity: Value(input.requiredQuantity),
                        checked: shouldResetChecked
                            ? const Value(0)
                            : const Value.absent(),
                        checkedAt: shouldResetChecked
                            ? const Value(null)
                            : const Value.absent(),
                        sortOrder: Value(index),
                      ),
                    );
                _ensureUpdated(updated, expected: 1, message: '保存出门任务条目失败');
              case textSessionItemType:
                if (input.itemId != null) {
                  throw const SessionRepositoryException(
                    SessionRepositoryErrorCode.invalidItem,
                    '普通文本条目不能保存物品引用',
                  );
                }
                final textName = _normalizeItemName(input.textName);
                final shouldResetChecked =
                    current.itemType != textSessionItemType ||
                    current.textName != textName ||
                    current.requiredQuantity != input.requiredQuantity;

                final updated =
                    await (db.update(
                      db.sessionItems,
                    )..where((t) => t.id.equals(entryId))).write(
                      SessionItemsCompanion(
                        itemType: const Value(textSessionItemType),
                        itemId: const Value(null),
                        textName: Value(textName),
                        nameSnapshot: Value(textName),
                        locationSnapshot: const Value(null),
                        requiredQuantity: Value(input.requiredQuantity),
                        checked: shouldResetChecked
                            ? const Value(0)
                            : const Value.absent(),
                        checkedAt: shouldResetChecked
                            ? const Value(null)
                            : const Value.absent(),
                        sortOrder: Value(index),
                      ),
                    );
                _ensureUpdated(updated, expected: 1, message: '保存出门任务条目失败');
              default:
                throw const SessionRepositoryException(
                  SessionRepositoryErrorCode.invalidItem,
                  '出门任务条目类型不合法',
                );
            }
          } else {
            switch (input.itemType) {
              case registeredSessionItemType:
                if (input.itemId == null || input.textName != null) {
                  throw const SessionRepositoryException(
                    SessionRepositoryErrorCode.invalidItem,
                    '登记物品条目字段组合无效',
                  );
                }
                final live = await _readLiveItem(input.itemId!);
                await db
                    .into(db.sessionItems)
                    .insert(
                      SessionItemsCompanion(
                        sessionId: Value(sessionId),
                        itemType: const Value(registeredSessionItemType),
                        itemId: Value(input.itemId),
                        textName: const Value(null),
                        nameSnapshot: Value(live.item.name),
                        locationSnapshot: Value(live.locationPath),
                        requiredQuantity: Value(input.requiredQuantity),
                        checked: const Value(0),
                        checkedAt: const Value(null),
                        sortOrder: Value(index),
                      ),
                    );
              case textSessionItemType:
                if (input.itemId != null) {
                  throw const SessionRepositoryException(
                    SessionRepositoryErrorCode.invalidItem,
                    '普通文本条目不能保存物品引用',
                  );
                }
                final textName = _normalizeItemName(input.textName);
                await db
                    .into(db.sessionItems)
                    .insert(
                      SessionItemsCompanion(
                        sessionId: Value(sessionId),
                        itemType: const Value(textSessionItemType),
                        itemId: const Value(null),
                        textName: Value(textName),
                        nameSnapshot: Value(textName),
                        locationSnapshot: const Value(null),
                        requiredQuantity: Value(input.requiredQuantity),
                        checked: const Value(0),
                        checkedAt: const Value(null),
                        sortOrder: Value(index),
                      ),
                    );
              default:
                throw const SessionRepositoryException(
                  SessionRepositoryErrorCode.invalidItem,
                  '出门任务条目类型不合法',
                );
            }
          }
        }

        final idsToDelete = currentEntries
            .map((e) => e.id)
            .where((id) => !retainedIds.contains(id))
            .toList();
        if (idsToDelete.isNotEmpty) {
          final deleted = await (db.delete(
            db.sessionItems,
          )..where((t) => t.id.isIn(idsToDelete))).go();
          _ensureUpdated(
            deleted,
            expected: idsToDelete.length,
            message: '删除未保留出门任务条目失败',
          );
        }

        final updatedSession =
            await (db.update(
              db.outgoingSessions,
            )..where((t) => t.id.equals(sessionId))).write(
              OutgoingSessionsCompanion(
                title: Value(normalizedTitle),
                updatedAt: Value(_now()),
              ),
            );
        _ensureUpdated(updatedSession, expected: 1, message: '更新出门任务失败');

        final session = await _requireSession(sessionId);
        final details = await _readEntryDetails(session);
        return SessionDetail(
          session: session,
          entries: List.unmodifiable(details),
        );
      });
    });
  }

  Future<List<SessionQuantityShortage>> listQuantityShortages(int sessionId) {
    return _runWithDataGuard('查询出门任务数量不足失败', () async {
      final session = await _requireSession(sessionId);
      if (session.status != 'IN_PROGRESS') {
        return const <SessionQuantityShortage>[];
      }

      final rows =
          await (db.select(db.sessionItems).join([
                  innerJoin(
                    db.items,
                    db.items.id.equalsExp(db.sessionItems.itemId),
                  ),
                ])
                ..where(
                  db.sessionItems.sessionId.equals(sessionId) &
                      db.sessionItems.itemType.equals(
                        registeredSessionItemType,
                      ) &
                      db.sessionItems.requiredQuantity.isBiggerThan(
                        db.items.quantity,
                      ),
                )
                ..orderBy([
                  OrderingTerm(expression: db.sessionItems.sortOrder),
                  OrderingTerm(expression: db.sessionItems.id),
                ]))
              .get();

      return List.unmodifiable(
        rows.map(
          (row) => SessionQuantityShortage(
            entry: row.readTable(db.sessionItems),
            item: row.readTable(db.items),
          ),
        ),
      );
    });
  }

  Future<void> complete(int sessionId, {bool confirmedUnchecked = false}) {
    return _runWithDataGuard('完成出门任务失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final entries = await _readEntries(sessionId);
        if (entries.isEmpty) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.emptySession,
            '空出门任务不能完成',
          );
        }
        if (entries.any((entry) => entry.checked == 0) && !confirmedUnchecked) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.incompleteItemsConfirmationRequired,
            '还有未勾选条目，必须先确认才能完成',
          );
        }

        for (final entry in entries) {
          switch (entry.itemType) {
            case registeredSessionItemType:
              final itemId = entry.itemId;
              if (itemId == null || entry.textName != null) {
                throw const SessionRepositoryException(
                  SessionRepositoryErrorCode.dataInconsistency,
                  '进行中的登记物品条目引用无效',
                );
              }
              final live = await _readLiveItem(itemId);
              final updated =
                  await (db.update(
                    db.sessionItems,
                  )..where((table) => table.id.equals(entry.id))).write(
                    SessionItemsCompanion(
                      nameSnapshot: Value(live.item.name),
                      locationSnapshot: Value(live.locationPath),
                    ),
                  );
              _ensureUpdated(updated, expected: 1, message: '冻结物品历史快照失败');
            case textSessionItemType:
              final textName = entry.textName;
              if (entry.itemId != null || textName == null) {
                throw const SessionRepositoryException(
                  SessionRepositoryErrorCode.dataInconsistency,
                  '普通文本条目字段组合无效',
                );
              }
              final updated =
                  await (db.update(
                    db.sessionItems,
                  )..where((table) => table.id.equals(entry.id))).write(
                    SessionItemsCompanion(
                      nameSnapshot: Value(_normalizeItemName(textName)),
                    ),
                  );
              _ensureUpdated(updated, expected: 1, message: '冻结文本历史快照失败');
            default:
              throw const SessionRepositoryException(
                SessionRepositoryErrorCode.dataInconsistency,
                '出门任务包含未知条目类型',
              );
          }
        }

        final timestamp = _now();
        final updated =
            await (db.update(
              db.outgoingSessions,
            )..where((table) => table.id.equals(sessionId))).write(
              OutgoingSessionsCompanion(
                status: const Value('COMPLETED'),
                completedAt: Value(timestamp),
                updatedAt: Value(timestamp),
              ),
            );
        _ensureUpdated(updated, expected: 1, message: '完成出门任务失败');
      });
    });
  }

  Future<void> deleteActiveConfirmed(int sessionId) {
    return _runWithDataGuard('删除进行中出门任务失败', () {
      return db.transaction(() async {
        await _requireActive(sessionId);
        final deleted =
            await (db.delete(db.outgoingSessions)..where(
                  (table) =>
                      table.id.equals(sessionId) &
                      table.status.equals('IN_PROGRESS'),
                ))
                .go();
        _ensureUpdated(deleted, expected: 1, message: '删除进行中出门任务失败');
      });
    });
  }

  Future<OutgoingSession> _requireSession(int id) async {
    final session = await findById(id);
    if (session == null) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.sessionNotFound,
        '出门任务不存在',
      );
    }
    return session;
  }

  Future<OutgoingSession> _requireActive(int id) async {
    final session = await _requireSession(id);
    switch (session.status) {
      case 'IN_PROGRESS':
        return session;
      case 'COMPLETED':
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.completedSessionReadOnly,
          '已完成出门任务为只读',
        );
      default:
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.illegalStatusTransition,
          '出门任务状态不合法',
        );
    }
  }

  Future<OutgoingTemplate> _requireTemplate(int id) async {
    final template = await (db.select(
      db.outgoingTemplates,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (template == null) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.templateNotFound,
        '出门模板不存在',
      );
    }
    return template;
  }

  Future<SessionItem> _requireEntry(int sessionId, int entryId) async {
    final entry =
        await (db.select(db.sessionItems)..where(
              (table) =>
                  table.id.equals(entryId) & table.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    if (entry == null) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.sessionItemNotFound,
        '出门任务条目不存在',
      );
    }
    return entry;
  }

  Future<List<SessionItem>> _readEntries(int sessionId) {
    final query = db.select(db.sessionItems)
      ..where((table) => table.sessionId.equals(sessionId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.sortOrder),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<List<TemplateItem>> _readTemplateEntries(int templateId) {
    final query = db.select(db.templateItems)
      ..where((table) => table.templateId.equals(templateId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.sortOrder),
        (table) => OrderingTerm(expression: table.id),
      ]);
    return query.get();
  }

  Future<List<SessionEntryDetail>> _readEntryDetails(
    OutgoingSession session,
  ) async {
    final entries = await _readEntries(session.id);
    final details = <SessionEntryDetail>[];
    for (final entry in entries) {
      switch (entry.itemType) {
        case registeredSessionItemType:
          if (entry.textName != null) {
            throw const SessionRepositoryException(
              SessionRepositoryErrorCode.dataInconsistency,
              '登记物品条目字段组合无效',
            );
          }
          if (session.status == 'IN_PROGRESS') {
            final itemId = entry.itemId;
            if (itemId == null) {
              throw const SessionRepositoryException(
                SessionRepositoryErrorCode.dataInconsistency,
                '进行中的登记物品条目缺少物品引用',
              );
            }
            final live = await _readLiveItem(itemId);
            details.add(
              SessionEntryDetail(
                entry: entry,
                registeredItem: live.item,
                locationPath: live.locationPath,
                isCompleted: false,
              ),
            );
          } else {
            details.add(
              SessionEntryDetail(
                entry: entry,
                locationPath: entry.locationSnapshot,
                isCompleted: true,
              ),
            );
          }
        case textSessionItemType:
          if (entry.itemId != null ||
              entry.textName == null ||
              entry.textName!.trim().isEmpty) {
            throw const SessionRepositoryException(
              SessionRepositoryErrorCode.dataInconsistency,
              '普通文本条目字段组合无效',
            );
          }
          details.add(
            SessionEntryDetail(
              entry: entry,
              locationPath: entry.locationSnapshot,
              isCompleted: session.status == 'COMPLETED',
            ),
          );
        default:
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.dataInconsistency,
            '出门任务包含未知条目类型',
          );
      }
    }
    return details;
  }

  Future<_LiveItem> _readLiveItem(int itemId) async {
    final item = await _findItem(itemId);
    if (item == null) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.itemNotFound,
        '登记物品不存在',
      );
    }
    return _LiveItem(item: item, locationPath: await _fullLocationPath(item));
  }

  Future<String> _fullLocationPath(Item item) async {
    final segments = <String>[];
    final visited = <int>{};
    Location? current = await (db.select(
      db.locations,
    )..where((table) => table.id.equals(item.locationId))).getSingleOrNull();

    if (current == null) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.dataInconsistency,
        '物品关联的收纳位置不存在',
      );
    }

    while (current != null) {
      if (!visited.add(current.id)) {
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.dataInconsistency,
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
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.dataInconsistency,
          '收纳位置父级不存在',
        );
      }
    }

    return segments.join(' / ');
  }

  Future<List<_NormalizedSessionEntry>> _normalizeEntries(
    List<SessionEntryInput> entries,
  ) async {
    if (entries.isEmpty) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.emptySession,
        '出门任务至少需要一个条目',
      );
    }

    final normalizedEntries = <_NormalizedSessionEntry>[];
    final registeredItemIds = <int>{};
    for (var index = 0; index < entries.length; index += 1) {
      final normalized = await _normalizeEntryInput(
        entries[index],
        fallbackSortOrder: index,
      );
      final itemId = normalized.itemId;
      if (itemId != null && !registeredItemIds.add(itemId)) {
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.duplicateRegisteredItem,
          '同一出门任务中不能重复关联同一件登记物品',
        );
      }
      normalizedEntries.add(normalized);
    }
    return normalizedEntries;
  }

  Future<_NormalizedSessionEntry> _normalizeEntryInput(
    SessionEntryInput input, {
    required int fallbackSortOrder,
  }) async {
    _validateRequiredQuantity(input.requiredQuantity);
    final sortOrder = input.sortOrder ?? fallbackSortOrder;
    if (sortOrder < 0) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.invalidItem,
        '出门任务条目排序值不能为负数',
      );
    }

    switch (input.itemType) {
      case registeredSessionItemType:
        if (input.itemId == null || input.textName != null) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.invalidItem,
            '登记物品条目字段组合无效',
          );
        }
        final live = await _readLiveItem(input.itemId!);
        return _NormalizedSessionEntry(
          itemType: registeredSessionItemType,
          itemId: input.itemId,
          textName: null,
          nameSnapshot: live.item.name,
          locationSnapshot: live.locationPath,
          requiredQuantity: input.requiredQuantity,
          sortOrder: sortOrder,
        );
      case textSessionItemType:
        if (input.itemId != null) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.invalidItem,
            '普通文本条目不能保存物品引用',
          );
        }
        final textName = _normalizeItemName(input.textName);
        return _NormalizedSessionEntry(
          itemType: textSessionItemType,
          itemId: null,
          textName: textName,
          nameSnapshot: textName,
          locationSnapshot: null,
          requiredQuantity: input.requiredQuantity,
          sortOrder: sortOrder,
        );
      default:
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.invalidItem,
          '出门任务条目类型不合法',
        );
    }
  }

  Future<_NormalizedSessionEntry> _normalizeTemplateEntry(
    TemplateItem entry,
  ) async {
    _validateRequiredQuantity(entry.requiredQuantity);
    if (entry.sortOrder < 0) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.invalidItem,
        '模板条目排序值不能为负数',
      );
    }

    switch (entry.itemType) {
      case registeredSessionItemType:
        if (entry.itemId == null || entry.textName != null) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.dataInconsistency,
            '模板登记物品条目字段组合无效',
          );
        }
        final live = await _readLiveItem(entry.itemId!);
        return _NormalizedSessionEntry(
          itemType: registeredSessionItemType,
          itemId: entry.itemId,
          textName: null,
          nameSnapshot: live.item.name,
          locationSnapshot: live.locationPath,
          requiredQuantity: entry.requiredQuantity,
          sortOrder: entry.sortOrder,
        );
      case textSessionItemType:
        if (entry.itemId != null ||
            entry.textName == null ||
            entry.textName!.trim().isEmpty) {
          throw const SessionRepositoryException(
            SessionRepositoryErrorCode.dataInconsistency,
            '模板普通文本条目字段组合无效',
          );
        }
        final textName = _normalizeItemName(entry.textName);
        return _NormalizedSessionEntry(
          itemType: textSessionItemType,
          itemId: null,
          textName: textName,
          nameSnapshot: textName,
          locationSnapshot: null,
          requiredQuantity: entry.requiredQuantity,
          sortOrder: entry.sortOrder,
        );
      default:
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.dataInconsistency,
          '模板包含未知条目类型',
        );
    }
  }

  Future<int> _insertSession({required String title, int? templateId}) {
    final timestamp = _now();
    return db
        .into(db.outgoingSessions)
        .insert(
          OutgoingSessionsCompanion(
            templateId: Value(templateId),
            title: Value(title),
            status: const Value('IN_PROGRESS'),
            createdAt: Value(timestamp),
            updatedAt: Value(timestamp),
            completedAt: const Value(null),
          ),
        );
  }

  Future<void> _insertEntries(
    int sessionId,
    List<_NormalizedSessionEntry> entries,
  ) async {
    for (final entry in entries) {
      await db.into(db.sessionItems).insert(_entryCompanion(sessionId, entry));
    }
  }

  SessionItemsCompanion _entryCompanion(
    int sessionId,
    _NormalizedSessionEntry entry,
  ) {
    return SessionItemsCompanion(
      sessionId: Value(sessionId),
      itemType: Value(entry.itemType),
      itemId: Value(entry.itemId),
      textName: Value(entry.textName),
      nameSnapshot: Value(entry.nameSnapshot),
      locationSnapshot: Value(entry.locationSnapshot),
      requiredQuantity: Value(entry.requiredQuantity),
      checked: const Value(0),
      checkedAt: const Value(null),
      sortOrder: Value(entry.sortOrder),
    );
  }

  Future<bool> _hasRegisteredItem({
    required int sessionId,
    required int itemId,
    int? excludingEntryId,
  }) async {
    final query = db.select(db.sessionItems)
      ..where(
        (table) =>
            table.sessionId.equals(sessionId) &
            table.itemType.equals(registeredSessionItemType) &
            table.itemId.equals(itemId),
      )
      ..limit(1);
    final rows = await query.get();
    return rows.any((row) => row.id != excludingEntryId);
  }

  Future<int> _nextSortOrder(int sessionId) async {
    final row = await db
        .customSelect(
          '''
          SELECT COALESCE(MAX(sort_order) + 1, 0) AS next_sort_order
          FROM session_items
          WHERE session_id = ?
          ''',
          variables: [Variable.withInt(sessionId)],
          readsFrom: {db.sessionItems},
        )
        .getSingle();
    return row.read<int>('next_sort_order');
  }

  Future<int> _entryCount(int sessionId) async {
    final row = await db
        .customSelect(
          '''
          SELECT COUNT(*) AS entry_count
          FROM session_items
          WHERE session_id = ?
          ''',
          variables: [Variable.withInt(sessionId)],
          readsFrom: {db.sessionItems},
        )
        .getSingle();
    return row.read<int>('entry_count');
  }

  Future<void> _touchSession(int sessionId) async {
    final updated =
        await (db.update(db.outgoingSessions)
              ..where((table) => table.id.equals(sessionId)))
            .write(OutgoingSessionsCompanion(updatedAt: Value(_now())));
    _ensureUpdated(updated, expected: 1, message: '更新出门任务修改时间失败');
  }

  String _normalizeTitle(String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.invalidTitle,
        '出门任务名称不能为空',
      );
    }
    return normalized;
  }

  String _normalizeItemName(String? name) {
    final normalized = name?.trim() ?? '';
    if (normalized.isEmpty) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.invalidItemName,
        '普通文本条目名称不能为空',
      );
    }
    return normalized;
  }

  void _validateRequiredQuantity(int requiredQuantity) {
    if (requiredQuantity < 1) {
      throw const SessionRepositoryException(
        SessionRepositoryErrorCode.invalidRequiredQuantity,
        '出门任务条目所需数量必须是正整数',
      );
    }
  }

  Future<T> _runWithDataGuard<T>(
    String message,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on SessionRepositoryException {
      rethrow;
    } catch (error) {
      throw SessionRepositoryException(
        SessionRepositoryErrorCode.dataInconsistency,
        message,
        cause: error,
      );
    }
  }

  void _ensureUpdated(
    int actual, {
    required int expected,
    required String message,
  }) {
    if (actual != expected) {
      throw SessionRepositoryException(
        SessionRepositoryErrorCode.dataInconsistency,
        message,
      );
    }
  }
}

class _LiveItem {
  const _LiveItem({required this.item, required this.locationPath});

  final Item item;
  final String locationPath;
}

class _NormalizedSessionEntry {
  const _NormalizedSessionEntry({
    required this.itemType,
    required this.itemId,
    required this.textName,
    required this.nameSnapshot,
    required this.locationSnapshot,
    required this.requiredQuantity,
    required this.sortOrder,
  });

  final String itemType;
  final int? itemId;
  final String? textName;
  final String nameSnapshot;
  final String? locationSnapshot;
  final int requiredQuantity;
  final int sortOrder;
}
