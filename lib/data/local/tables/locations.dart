import 'package:drift/drift.dart';

@TableIndex.sql('''
CREATE UNIQUE INDEX uq_locations_root_name
    ON locations(name) WHERE parent_id IS NULL;
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX uq_locations_sibling_name
    ON locations(parent_id, name) WHERE parent_id IS NOT NULL;
''')
@TableIndex(name: 'idx_locations_parent', columns: {#parentId})
class Locations extends Table {
  @override
  String get tableName => 'locations';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name =>
      text().customConstraint('NOT NULL CHECK (length(trim(name)) > 0)')();

  IntColumn get parentId => integer().nullable().references(
    Locations,
    #id,
    onDelete: KeyAction.restrict,
  )();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  List<String> get customConstraints => [
    'CHECK (parent_id IS NULL OR parent_id <> id)',
  ];
}
