extension DateTimeFormatting on DateTime {
  String get isoDate => toIso8601String().split('T').first;
}
