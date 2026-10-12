import 'package:drift/drift.dart';

import 'outing_templates_table.dart';

class OutingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get templateId =>
      integer().nullable().references(OutingTemplates, #id)();

  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get endedAt => dateTime().nullable()();
}
