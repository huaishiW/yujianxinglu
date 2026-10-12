import 'package:drift/drift.dart';

import 'outgoing_templates.dart';

@TableIndex.sql('''
CREATE INDEX idx_sessions_status_recent
    ON outgoing_sessions(status, updated_at DESC);
''')
@TableIndex(name: 'idx_sessions_template', columns: {#templateId})
class OutgoingSessions extends Table {
  @override
  String get tableName => 'outgoing_sessions';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get templateId => integer().nullable().references(
    OutgoingTemplates,
    #id,
    onDelete: KeyAction.setNull,
  )();

  TextColumn get title =>
      text().customConstraint('NOT NULL CHECK (length(trim(title)) > 0)')();

  TextColumn get status => text().customConstraint(
    "NOT NULL DEFAULT 'IN_PROGRESS' "
    "CHECK (status IN ('IN_PROGRESS', 'COMPLETED'))",
  )();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get completedAt => integer().nullable()();

  @override
  List<String> get customConstraints => [
    '''CHECK (
          (status = 'IN_PROGRESS' AND completed_at IS NULL)
          OR
          (status = 'COMPLETED' AND completed_at IS NOT NULL)
        )''',
  ];
}
