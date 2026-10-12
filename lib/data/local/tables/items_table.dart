import 'package:drift/drift.dart';

import 'locations_table.dart';

class Items extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 150)();

  TextColumn get category => text().nullable()();

  IntColumn get locationId => integer().nullable().references(Locations, #id)();

  BoolColumn get isEssential => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
