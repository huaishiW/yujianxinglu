import 'package:drift/drift.dart';

@TableIndex.sql('''
CREATE INDEX idx_templates_recent
    ON outgoing_templates(last_used_at DESC, created_at DESC);
''')
class OutgoingTemplates extends Table {
  @override
  String get tableName => 'outgoing_templates';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name =>
      text().customConstraint('NOT NULL CHECK (length(trim(name)) > 0)')();

  TextColumn get description => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get lastUsedAt => integer().nullable()();
}
