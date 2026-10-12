import 'package:drift/drift.dart';

import 'items.dart';
import 'outgoing_sessions.dart';

@TableIndex.sql('''
CREATE UNIQUE INDEX uq_session_registered_item
    ON session_items(session_id, item_id)
    WHERE item_type = 'REGISTERED_ITEM' AND item_id IS NOT NULL;
''')
@TableIndex.sql('''
CREATE INDEX idx_session_items_order
    ON session_items(session_id, sort_order, id);
''')
@TableIndex.sql('''
CREATE INDEX idx_session_items_item
    ON session_items(item_id) WHERE item_id IS NOT NULL;
''')
class SessionItems extends Table {
  @override
  String get tableName => 'session_items';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get sessionId => integer().references(
    OutgoingSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  TextColumn get itemType => text().customConstraint(
    "NOT NULL CHECK (item_type IN ('REGISTERED_ITEM', 'TEXT_ITEM'))",
  )();

  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.setNull,
  )();

  TextColumn get textName => text().nullable()();

  TextColumn get nameSnapshot => text().customConstraint(
    'NOT NULL CHECK (length(trim(name_snapshot)) > 0)',
  )();

  TextColumn get locationSnapshot => text().nullable()();

  IntColumn get requiredQuantity => integer().customConstraint(
    'NOT NULL DEFAULT 1 CHECK (required_quantity >= 1)',
  )();

  IntColumn get checked => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (checked IN (0, 1))',
  )();

  IntColumn get checkedAt => integer().nullable()();

  IntColumn get sortOrder => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (sort_order >= 0)',
  )();

  @override
  List<String> get customConstraints => [
    '''CHECK (
          (item_type = 'REGISTERED_ITEM' AND text_name IS NULL)
          OR
          (item_type = 'TEXT_ITEM' AND item_id IS NULL
              AND text_name IS NOT NULL AND length(trim(text_name)) > 0)
        )''',
    '''CHECK (
          (checked = 0 AND checked_at IS NULL)
          OR
          (checked = 1 AND checked_at IS NOT NULL)
        )''',
  ];
}
