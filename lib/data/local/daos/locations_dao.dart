import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/locations_table.dart';

part 'locations_dao.g.dart';

@DriftAccessor(tables: [Locations])
class LocationsDao extends DatabaseAccessor<AppDatabase>
    with _$LocationsDaoMixin {
  LocationsDao(super.attachedDatabase);

  Stream<List<Location>> watchAll() {
    return (select(
      locations,
    )..orderBy([(row) => OrderingTerm(expression: row.name)])).watch();
  }

  Future<int> insertOne(LocationsCompanion entry) {
    return into(locations).insert(entry);
  }

  Future<int> deleteById(int id) {
    return (delete(locations)..where((row) => row.id.equals(id))).go();
  }
}
