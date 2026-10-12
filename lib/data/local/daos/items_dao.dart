import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/items_table.dart';

part 'items_dao.g.dart';

@DriftAccessor(tables: [Items])
class ItemsDao extends DatabaseAccessor<AppDatabase> with _$ItemsDaoMixin {
  ItemsDao(super.attachedDatabase);

  Stream<List<Item>> watchAll() {
    return (select(
      items,
    )..orderBy([(row) => OrderingTerm(expression: row.name)])).watch();
  }

  Future<int> insertOne(ItemsCompanion entry) {
    return into(items).insert(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(items)..where((row) => row.id.equals(id))).go();
  }
}
