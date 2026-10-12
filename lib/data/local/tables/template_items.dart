import 'package:drift/drift.dart';

import 'items.dart';
import 'outgoing_templates.dart';

@TableIndex.sql('''
CREATE UNIQUE INDEX uq_template_registered_item
    ON template_items(template_id, item_id)
    WHERE item_type = 'REGISTERED_ITEM';
''')
@TableIndex.sql('''
CREATE INDEX idx_template_items_order
    ON template_items(template_id, sort_order, id);
''')
@TableIndex.sql('''
CREATE INDEX idx_template_items_item
    ON template_items(item_id) WHERE item_id IS NOT NULL;
''')
class TemplateItems extends Table {
  @override
  String get tableName => 'template_items';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get templateId => integer().references(
    OutgoingTemplates,
    #id,
    onDelete: KeyAction.cascade,
  )();

  TextColumn get itemType => text().customConstraint(
    "NOT NULL CHECK (item_type IN ('REGISTERED_ITEM', 'TEXT_ITEM'))",
  )();

  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get textName => text().nullable()();

  IntColumn get requiredQuantity => integer().customConstraint(
    'NOT NULL DEFAULT 1 CHECK (required_quantity >= 1)',
  )();

  IntColumn get sortOrder => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (sort_order >= 0)',
  )();

  @override
  List<String> get customConstraints => [
    '''CHECK (
          (item_type = 'REGISTERED_ITEM' AND item_id IS NOT NULL
              AND text_name IS NULL)
          OR
          (item_type = 'TEXT_ITEM' AND item_id IS NULL
              AND text_name IS NOT NULL AND length(trim(text_name)) > 0)
        )''',
  ];
}
