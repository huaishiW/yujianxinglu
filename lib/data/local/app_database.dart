import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants/app_constants.dart';
import 'tables/items.dart';
import 'tables/locations.dart';
import 'tables/outgoing_sessions.dart';
import 'tables/outgoing_templates.dart';
import 'tables/session_items.dart';
import 'tables/template_items.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Locations,
    Items,
    OutgoingTemplates,
    TemplateItems,
    OutgoingSessions,
    SessionItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults()
    : super(driftDatabase(name: AppConstants.databaseName));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      throw UnsupportedError(
        'No database migration is defined for schema $from to $to.',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
