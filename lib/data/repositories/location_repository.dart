import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../local/app_database.dart';

enum LocationRepositoryErrorCode {
  invalidName,
  locationNotFound,
  parentNotFound,
  duplicateName,
  cycleMove,
  notEmpty,
}

class LocationRepositoryException extends AppException {
  const LocationRepositoryException(this.code, String message, {super.cause})
    : super(message);

  final LocationRepositoryErrorCode code;
}

class LocationRepository {
  LocationRepository(this.db);

  final AppDatabase db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  String _normalizeName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const LocationRepositoryException(
        LocationRepositoryErrorCode.invalidName,
        '位置名称不能为空',
      );
    }
    return normalized;
  }

  Future<Location?> findById(int id) {
    return (db.select(
      db.locations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Location> getById(int id) async {
    final location = await findById(id);
    if (location == null) {
      throw const LocationRepositoryException(
        LocationRepositoryErrorCode.locationNotFound,
        '收纳位置不存在',
      );
    }
    return location;
  }

  Future<int> create({required String name, int? parentId}) async {
    final normalizedName = _normalizeName(name);

    return db.transaction(() async {
      if (parentId != null && await findById(parentId) == null) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.parentNotFound,
          '父位置不存在',
        );
      }

      if (await _hasSiblingName(normalizedName, parentId)) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.duplicateName,
          '同一层级下已存在同名位置',
        );
      }

      final timestamp = _now();
      return db
          .into(db.locations)
          .insert(
            LocationsCompanion(
              name: Value(normalizedName),
              parentId: Value(parentId),
              createdAt: Value(timestamp),
              updatedAt: Value(timestamp),
            ),
          );
    });
  }

  Future<List<Location>> listTopLevel() => listChildren(null);

  Future<List<Location>> listChildren(int? parentId) async {
    if (parentId != null) {
      await getById(parentId);
    }
    return _listChildren(parentId);
  }

  Future<List<Location>> _listChildren(int? parentId) {
    final query = db.select(db.locations)
      ..where(
        (t) => parentId == null
            ? t.parentId.isNull()
            : t.parentId.equals(parentId),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.name),
        (t) => OrderingTerm(expression: t.id),
      ]);
    return query.get();
  }

  Future<List<Item>> listDirectItems(int locationId) async {
    await getById(locationId);

    final query = db.select(db.items)
      ..where((t) => t.locationId.equals(locationId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.name),
        (t) => OrderingTerm(expression: t.id),
      ]);
    return query.get();
  }

  Future<String> fullPath(int id) {
    return db.transaction(() async {
      final segments = <String>[];
      final visited = <int>{};
      Location? current = await getById(id);

      while (current != null) {
        if (!visited.add(current.id)) {
          throw const LocationRepositoryException(
            LocationRepositoryErrorCode.cycleMove,
            '收纳位置存在循环引用',
          );
        }
        segments.insert(0, current.name);
        current = current.parentId == null
            ? null
            : await getById(current.parentId!);
      }

      return segments.join(' / ');
    });
  }

  Future<void> rename(int id, String name) async {
    final normalizedName = _normalizeName(name);

    await db.transaction(() async {
      final location = await getById(id);
      if (location.name == normalizedName) {
        return;
      }

      if (await _hasSiblingName(
        normalizedName,
        location.parentId,
        excludingId: id,
      )) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.duplicateName,
          '同一层级下已存在同名位置',
        );
      }

      await (db.update(db.locations)..where((t) => t.id.equals(id))).write(
        LocationsCompanion(
          name: Value(normalizedName),
          updatedAt: Value(_now()),
        ),
      );
    });
  }

  Future<bool> move({required int id, int? targetParentId}) async {
    return db.transaction(() async {
      final source = await getById(id);
      if (source.parentId == targetParentId) {
        return false;
      }

      if (targetParentId != null) {
        if (await findById(targetParentId) == null) {
          throw const LocationRepositoryException(
            LocationRepositoryErrorCode.parentNotFound,
            '目标父位置不存在',
          );
        }

        if (await _isSelfOrDescendant(id, targetParentId)) {
          throw const LocationRepositoryException(
            LocationRepositoryErrorCode.cycleMove,
            '不能移动到自身或其后代位置',
          );
        }
      }

      if (await _hasSiblingName(source.name, targetParentId, excludingId: id)) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.duplicateName,
          '目标层级下已存在同名位置',
        );
      }

      final updated =
          await (db.update(db.locations)..where((t) => t.id.equals(id))).write(
            LocationsCompanion(
              parentId: Value(targetParentId),
              updatedAt: Value(_now()),
            ),
          );
      if (updated != 1) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.locationNotFound,
          '收纳位置不存在',
        );
      }
      return true;
    });
  }

  Future<void> deleteEmpty(int id) async {
    await db.transaction(() async {
      await getById(id);

      final children =
          await (db.select(db.locations)
                ..where((t) => t.parentId.equals(id))
                ..limit(1))
              .get();
      final directItems =
          await (db.select(db.items)
                ..where((t) => t.locationId.equals(id))
                ..limit(1))
              .get();

      if (children.isNotEmpty || directItems.isNotEmpty) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.notEmpty,
          '位置仍包含子位置或直接存放的物品，不能删除',
        );
      }

      await (db.delete(db.locations)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<bool> _hasSiblingName(
    String name,
    int? parentId, {
    int? excludingId,
  }) async {
    final query = db.select(db.locations)
      ..where(
        (t) =>
            t.name.equals(name) &
            (parentId == null
                ? t.parentId.isNull()
                : t.parentId.equals(parentId)),
      )
      ..limit(1);
    final rows = await query.get();
    return rows.any((row) => row.id != excludingId);
  }

  Future<bool> _isSelfOrDescendant(int sourceId, int targetParentId) async {
    final result = await db
        .customSelect(
          '''
      WITH RECURSIVE descendants(id) AS (
        SELECT id
        FROM locations
        WHERE id = ?
        UNION
        SELECT child.id
        FROM locations child
        JOIN descendants ancestor ON child.parent_id = ancestor.id
      )
      SELECT EXISTS(
        SELECT 1
        FROM descendants
        WHERE id = ?
      ) AS is_invalid_target
      ''',
          variables: [
            Variable.withInt(sourceId),
            Variable.withInt(targetParentId),
          ],
          readsFrom: {db.locations},
        )
        .getSingle();
    return result.read<int>('is_invalid_target') == 1;
  }
}
