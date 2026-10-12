import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants/app_constants.dart';
import 'daos/items_dao.dart';
import 'daos/locations_dao.dart';
import 'tables/items_table.dart';
import 'tables/locations_table.dart';
import 'tables/outing_sessions_table.dart';
import 'tables/outing_templates_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Locations, Items, OutingTemplates, OutingSessions],
  daos: [LocationsDao, ItemsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: AppConstants.databaseName));

  @override
  int get schemaVersion => 1;
}
