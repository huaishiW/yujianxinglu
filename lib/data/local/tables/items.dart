import 'package:drift/drift.dart';

import 'locations.dart';

@TableIndex(name: 'idx_items_location', columns: {#locationId})
@TableIndex(name: 'idx_items_name', columns: {#name})
class Items extends Table {
  @override
  String get tableName => 'items';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name =>
      text().customConstraint('NOT NULL CHECK (length(trim(name)) > 0)')();

  IntColumn get quantity =>
      integer().customConstraint('NOT NULL DEFAULT 1 CHECK (quantity >= 1)')();

  IntColumn get locationId =>
      integer().references(Locations, #id, onDelete: KeyAction.restrict)();

  TextColumn get category => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}
